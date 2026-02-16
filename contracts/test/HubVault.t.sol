// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/HubVault.sol";

contract HubVaultTest is Test {
    MockUSDC usdc;
    HubVault vault;

    address keeper = makeAddr("keeper");
    address governance = makeAddr("governance");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address venue1 = makeAddr("venue1");
    address venue2 = makeAddr("venue2");
    address venue3 = makeAddr("venue3");
    address nobody = makeAddr("nobody");

    uint256 constant INITIAL_MINT = 100_000e6; // 100k USDC
    uint256 constant DEFAULT_HAIRCUT = 5000; // 50%

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event VenueEquityUpdated(address indexed user, address indexed venue, uint256 newEquity, bytes32 eventId);
    event MarginLocked(address indexed user, uint256 totalMargin);
    event ShortfallProcessed(address indexed user, address indexed venue, uint256 amount, uint256 fromCollateral, uint256 fromInsurance, bytes32 refId);
    event InsuranceDeposited(address indexed from, uint256 amount);
    event OverspendDetected(address indexed user, uint256 totalMargin, uint256 collateral);
    event VenueRegistered(address venue);
    event VenueRemoved(address venue);

    function setUp() public {
        usdc = new MockUSDC();
        vault = new HubVault(
            address(usdc),
            keeper,
            governance,
            DEFAULT_HAIRCUT
        );

        // Mint USDC to test actors
        usdc.mint(user1, INITIAL_MINT);
        usdc.mint(user2, INITIAL_MINT);
        usdc.mint(keeper, INITIAL_MINT);
        usdc.mint(venue1, INITIAL_MINT);
        usdc.mint(venue2, INITIAL_MINT);

        // Approve vault
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(keeper);
        usdc.approve(address(vault), type(uint256).max);

        // Register venues
        vm.startPrank(governance);
        vault.registerVenue(venue1);
        vault.registerVenue(venue2);
        vm.stopPrank();
    }

    // ──────────────────────────── Constructor Tests ────────────────────────────

    function test_Constructor() public view {
        assertEq(address(vault.usdc()), address(usdc));
        assertEq(vault.keeper(), keeper);
        assertEq(vault.governance(), governance);
        assertEq(vault.haircutBps(), DEFAULT_HAIRCUT);
        assertEq(vault.maxVenueAllocationBps(), 8000);
        assertEq(vault.overspendThresholdBps(), 9000);
    }

    function test_ConstructorRevertsZeroAddressUSDC() public {
        vm.expectRevert("HubVault: zero address usdc");
        new HubVault(address(0), keeper, governance, DEFAULT_HAIRCUT);
    }

    function test_ConstructorRevertsZeroAddressKeeper() public {
        vm.expectRevert("HubVault: zero address keeper");
        new HubVault(address(usdc), address(0), governance, DEFAULT_HAIRCUT);
    }

    function test_ConstructorRevertsZeroAddressGovernance() public {
        vm.expectRevert("HubVault: zero address governance");
        new HubVault(address(usdc), keeper, address(0), DEFAULT_HAIRCUT);
    }

    function test_ConstructorRevertsExcessiveHaircut() public {
        vm.expectRevert("HubVault: haircut exceeds 100%");
        new HubVault(address(usdc), keeper, governance, 10001);
    }

    // ──────────────────────────── Deposit Tests ────────────────────────────

    function test_DepositCollateral() public {
        uint256 amount = 10_000e6;
        
        vm.expectEmit(true, false, false, true);
        emit CollateralDeposited(user1, amount);
        
        vm.prank(user1);
        vault.depositCollateral(amount);

        assertEq(vault.collateral(user1), amount);
        assertEq(vault.totalDeposits(), amount);
        assertEq(usdc.balanceOf(address(vault)), amount);
        assertEq(usdc.balanceOf(user1), INITIAL_MINT - amount);
    }

    function test_DepositCollateralMultipleUsers() public {
        uint256 amount1 = 10_000e6;
        uint256 amount2 = 20_000e6;

        vm.prank(user1);
        vault.depositCollateral(amount1);

        vm.prank(user2);
        vault.depositCollateral(amount2);

        assertEq(vault.collateral(user1), amount1);
        assertEq(vault.collateral(user2), amount2);
        assertEq(vault.totalDeposits(), amount1 + amount2);
    }

    function test_DepositCollateralRevertsZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("HubVault: zero amount");
        vault.depositCollateral(0);
    }

    // ──────────────────────────── Withdraw Tests ────────────────────────────

    function test_WithdrawAvailable() public {
        uint256 depositAmount = 10_000e6;
        uint256 withdrawAmount = 5_000e6;

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.expectEmit(true, false, false, true);
        emit CollateralWithdrawn(user1, withdrawAmount);

        vm.prank(user1);
        vault.withdrawAvailable(withdrawAmount);

        assertEq(vault.collateral(user1), depositAmount - withdrawAmount);
        assertEq(vault.totalDeposits(), depositAmount - withdrawAmount);
        assertEq(usdc.balanceOf(user1), INITIAL_MINT - depositAmount + withdrawAmount);
    }

    function test_WithdrawEntireBalance() public {
        uint256 amount = 10_000e6;

        vm.prank(user1);
        vault.depositCollateral(amount);

        vm.prank(user1);
        vault.withdrawAvailable(amount);

        assertEq(vault.collateral(user1), 0);
        assertEq(vault.totalDeposits(), 0);
        assertEq(usdc.balanceOf(user1), INITIAL_MINT);
    }

    function test_WithdrawRevertsInsufficientBalance() public {
        uint256 depositAmount = 10_000e6;
        uint256 marginLocked = 7_000e6;

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        // Lock margin
        vm.prank(keeper);
        vault.updateMarginLocked(user1, marginLocked);

        // Try to withdraw more than available
        vm.prank(user1);
        vm.expectRevert("HubVault: insufficient available balance");
        vault.withdrawAvailable(depositAmount - marginLocked + 1);
    }

    function test_WithdrawRevertsZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("HubVault: zero amount");
        vault.withdrawAvailable(0);
    }

    function test_WithdrawWithZeroMargin() public {
        uint256 amount = 10_000e6;

        vm.prank(user1);
        vault.depositCollateral(amount);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, 0);

        vm.prank(user1);
        vault.withdrawAvailable(amount);

        assertEq(vault.collateral(user1), 0);
    }

    // ──────────────────────────── Available Balance Tests ────────────────────────────

    function test_AvailableBalance() public {
        uint256 depositAmount = 10_000e6;
        uint256 marginLocked = 3_000e6;

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, marginLocked);

        uint256 available = vault.availableBalance(user1);
        assertEq(available, depositAmount - marginLocked);
    }

    function test_AvailableBalanceZeroWhenOverlocked() public {
        uint256 depositAmount = 10_000e6;
        uint256 marginLocked = 15_000e6; // More than deposit

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, marginLocked);

        uint256 available = vault.availableBalance(user1);
        assertEq(available, 0);
    }

    // ──────────────────────────── Venue Equity Tests ────────────────────────────

    function test_UpdateVenueEquity() public {
        uint256 equity = 5_000e6;
        bytes32 eventId = keccak256("event1");

        vm.expectEmit(true, true, false, true);
        emit VenueEquityUpdated(user1, venue1, equity, eventId);

        vm.prank(keeper);
        vault.updateVenueEquity(user1, venue1, equity, eventId);

        assertEq(vault.venueEquity(user1, venue1), equity);
        assertTrue(vault.processedEvents(eventId));
    }

    function test_UpdateVenueEquityRevertsUnregisteredVenue() public {
        bytes32 eventId = keccak256("event1");

        vm.prank(keeper);
        vm.expectRevert("HubVault: venue not registered");
        vault.updateVenueEquity(user1, venue3, 5_000e6, eventId);
    }

    function test_UpdateVenueEquityRevertsDuplicate() public {
        bytes32 eventId = keccak256("event1");

        vm.prank(keeper);
        vault.updateVenueEquity(user1, venue1, 5_000e6, eventId);

        vm.prank(keeper);
        vm.expectRevert("HubVault: event already processed");
        vault.updateVenueEquity(user1, venue1, 6_000e6, eventId);
    }

    function test_UpdateVenueEquityRevertsNonKeeper() public {
        bytes32 eventId = keccak256("event1");

        vm.prank(nobody);
        vm.expectRevert("HubVault: caller is not keeper");
        vault.updateVenueEquity(user1, venue1, 5_000e6, eventId);
    }

    // ──────────────────────────── Margin Locked Tests ────────────────────────────

    function test_UpdateMarginLocked() public {
        uint256 margin = 5_000e6;

        vm.expectEmit(true, false, false, true);
        emit MarginLocked(user1, margin);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, margin);

        assertEq(vault.totalMarginLocked(user1), margin);
    }

    function test_UpdateMarginLockedDetectsOverspend() public {
        uint256 depositAmount = 10_000e6;
        uint256 marginAmount = 9_500e6; // 95% utilization, triggers overspend (threshold = 90%)

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.expectEmit(true, false, false, true);
        emit OverspendDetected(user1, marginAmount, depositAmount);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, marginAmount);
    }

    function test_UpdateMarginLockedNoOverspendBelowThreshold() public {
        uint256 depositAmount = 10_000e6;
        uint256 marginAmount = 8_000e6; // 80% utilization, below 90% threshold

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, marginAmount);

        assertEq(vault.totalMarginLocked(user1), marginAmount);
    }

    function test_UpdateMarginLockedRevertsNonKeeper() public {
        vm.prank(nobody);
        vm.expectRevert("HubVault: caller is not keeper");
        vault.updateMarginLocked(user1, 5_000e6);
    }

    // ──────────────────────────── Shortfall Processing Tests ────────────────────────────

    function test_ProcessShortfallFromCollateral() public {
        uint256 depositAmount = 10_000e6;
        uint256 shortfallAmount = 3_000e6;
        bytes32 refId = keccak256("ref1");

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        uint256 venueBefore = usdc.balanceOf(venue1);

        vm.expectEmit(true, true, false, true);
        emit ShortfallProcessed(user1, venue1, shortfallAmount, shortfallAmount, 0, refId);

        vm.prank(keeper);
        vault.processShortfall(user1, venue1, shortfallAmount, refId);

        assertEq(vault.collateral(user1), depositAmount - shortfallAmount);
        assertEq(usdc.balanceOf(venue1), venueBefore + shortfallAmount);
        assertTrue(vault.processedEvents(refId));
    }

    function test_ProcessShortfallFromInsurance() public {
        uint256 insuranceAmount = 20_000e6;
        uint256 shortfallAmount = 5_000e6;
        bytes32 refId = keccak256("ref1");

        // Deposit insurance
        vm.prank(keeper);
        vault.depositInsurance(insuranceAmount);

        uint256 venueBefore = usdc.balanceOf(venue1);

        vm.expectEmit(true, true, false, true);
        emit ShortfallProcessed(user1, venue1, shortfallAmount, 0, shortfallAmount, refId);

        vm.prank(keeper);
        vault.processShortfall(user1, venue1, shortfallAmount, refId);

        assertEq(vault.insurancePool(), insuranceAmount - shortfallAmount);
        assertEq(usdc.balanceOf(venue1), venueBefore + shortfallAmount);
    }

    function test_ProcessShortfallWaterfall() public {
        uint256 depositAmount = 5_000e6;
        uint256 insuranceAmount = 10_000e6;
        uint256 shortfallAmount = 12_000e6;
        bytes32 refId = keccak256("ref1");

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.prank(keeper);
        vault.depositInsurance(insuranceAmount);

        uint256 venueBefore = usdc.balanceOf(venue1);

        // Waterfall: depositAmount from collateral, then remaining (7_000e6) from insurance
        vm.expectEmit(true, true, false, true);
        emit ShortfallProcessed(user1, venue1, shortfallAmount, depositAmount, 7_000e6, refId);

        vm.prank(keeper);
        vault.processShortfall(user1, venue1, shortfallAmount, refId);

        assertEq(vault.collateral(user1), 0);
        assertEq(vault.insurancePool(), 3_000e6); // 10_000e6 - 7_000e6
        // Covered amount = depositAmount + 7_000e6 = 12_000e6
        assertEq(usdc.balanceOf(venue1), venueBefore + shortfallAmount);
    }

    function test_ProcessShortfallPartialCollateral() public {
        uint256 depositAmount = 10_000e6;
        uint256 marginLocked = 7_000e6;
        uint256 shortfallAmount = 5_000e6;
        bytes32 refId = keccak256("ref1");

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, marginLocked);

        // Available = 3_000e6, shortfall = 5_000e6
        // Should take 3_000e6 from collateral, need insurance for rest

        uint256 insuranceAmount = 10_000e6;
        vm.prank(keeper);
        vault.depositInsurance(insuranceAmount);

        uint256 venueBefore = usdc.balanceOf(venue1);

        vm.expectEmit(true, true, false, true);
        emit ShortfallProcessed(user1, venue1, shortfallAmount, 3_000e6, 2_000e6, refId);

        vm.prank(keeper);
        vault.processShortfall(user1, venue1, shortfallAmount, refId);

        assertEq(vault.collateral(user1), marginLocked);
        assertEq(vault.insurancePool(), insuranceAmount - 2_000e6);
        assertEq(usdc.balanceOf(venue1), venueBefore + shortfallAmount);
    }

    function test_ProcessShortfallRevertsUnregisteredVenue() public {
        bytes32 refId = keccak256("ref1");

        vm.prank(keeper);
        vm.expectRevert("HubVault: venue not registered");
        vault.processShortfall(user1, venue3, 1_000e6, refId);
    }

    function test_ProcessShortfallRevertsDuplicate() public {
        bytes32 refId = keccak256("ref1");

        vm.prank(user1);
        vault.depositCollateral(10_000e6);

        vm.prank(keeper);
        vault.processShortfall(user1, venue1, 1_000e6, refId);

        vm.prank(keeper);
        vm.expectRevert("HubVault: refId already processed");
        vault.processShortfall(user1, venue1, 1_000e6, refId);
    }

    function test_ProcessShortfallRevertsZeroAmount() public {
        bytes32 refId = keccak256("ref1");

        vm.prank(keeper);
        vm.expectRevert("HubVault: zero amount");
        vault.processShortfall(user1, venue1, 0, refId);
    }

    function test_ProcessShortfallRevertsNonKeeper() public {
        bytes32 refId = keccak256("ref1");

        vm.prank(nobody);
        vm.expectRevert("HubVault: caller is not keeper");
        vault.processShortfall(user1, venue1, 1_000e6, refId);
    }

    // ──────────────────────────── Batch Equity Update Tests ────────────────────────────

    function test_BatchUpdateEquity() public {
        address[] memory users = new address[](3);
        address[] memory venues = new address[](3);
        uint256[] memory equities = new uint256[](3);

        users[0] = user1;
        users[1] = user1;
        users[2] = user2;

        venues[0] = venue1;
        venues[1] = venue2;
        venues[2] = venue1;

        equities[0] = 5_000e6;
        equities[1] = 7_000e6;
        equities[2] = 3_000e6;

        bytes32 eventId = keccak256("batch1");

        vm.prank(keeper);
        vault.batchUpdateEquity(users, venues, equities, eventId);

        assertEq(vault.venueEquity(user1, venue1), 5_000e6);
        assertEq(vault.venueEquity(user1, venue2), 7_000e6);
        assertEq(vault.venueEquity(user2, venue1), 3_000e6);
        assertTrue(vault.processedEvents(eventId));
    }

    function test_BatchUpdateEquityRevertsLengthMismatch() public {
        address[] memory users = new address[](2);
        address[] memory venues = new address[](3);
        uint256[] memory equities = new uint256[](2);
        bytes32 eventId = keccak256("batch1");

        vm.prank(keeper);
        vm.expectRevert("HubVault: array length mismatch");
        vault.batchUpdateEquity(users, venues, equities, eventId);
    }

    function test_BatchUpdateEquityRevertsDuplicate() public {
        address[] memory users = new address[](1);
        address[] memory venues = new address[](1);
        uint256[] memory equities = new uint256[](1);

        users[0] = user1;
        venues[0] = venue1;
        equities[0] = 5_000e6;

        bytes32 eventId = keccak256("batch1");

        vm.prank(keeper);
        vault.batchUpdateEquity(users, venues, equities, eventId);

        vm.prank(keeper);
        vm.expectRevert("HubVault: event already processed");
        vault.batchUpdateEquity(users, venues, equities, eventId);
    }

    function test_BatchUpdateEquityRevertsUnregisteredVenue() public {
        address[] memory users = new address[](1);
        address[] memory venues = new address[](1);
        uint256[] memory equities = new uint256[](1);

        users[0] = user1;
        venues[0] = venue3; // Not registered
        equities[0] = 5_000e6;

        bytes32 eventId = keccak256("batch1");

        vm.prank(keeper);
        vm.expectRevert("HubVault: venue not registered");
        vault.batchUpdateEquity(users, venues, equities, eventId);
    }

    // ──────────────────────────── Insurance Tests ────────────────────────────

    function test_DepositInsurance() public {
        uint256 amount = 20_000e6;

        vm.expectEmit(true, false, false, true);
        emit InsuranceDeposited(keeper, amount);

        vm.prank(keeper);
        vault.depositInsurance(amount);

        assertEq(vault.insurancePool(), amount);
        assertEq(usdc.balanceOf(address(vault)), amount);
    }

    function test_DepositInsuranceMultiple() public {
        uint256 amount1 = 10_000e6;
        uint256 amount2 = 5_000e6;

        vm.prank(keeper);
        vault.depositInsurance(amount1);

        // user1 approval already done in setUp, just deposit
        vm.prank(user1);
        vault.depositInsurance(amount2);

        assertEq(vault.insurancePool(), amount1 + amount2);
    }

    function test_DepositInsuranceRevertsZeroAmount() public {
        vm.prank(keeper);
        vm.expectRevert("HubVault: zero amount");
        vault.depositInsurance(0);
    }

    // ──────────────────────────── Governance Tests ────────────────────────────

    function test_RegisterVenue() public {
        vm.expectEmit(true, false, false, false);
        emit VenueRegistered(venue3);

        vm.prank(governance);
        vault.registerVenue(venue3);

        assertTrue(vault.registeredVenues(venue3));
        assertEq(vault.venueCount(), 3);
    }

    function test_RegisterVenueRevertsZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert("HubVault: zero address");
        vault.registerVenue(address(0));
    }

    function test_RegisterVenueRevertsDuplicate() public {
        vm.prank(governance);
        vm.expectRevert("HubVault: venue already registered");
        vault.registerVenue(venue1);
    }

    function test_RegisterVenueRevertsNonGovernance() public {
        vm.prank(nobody);
        vm.expectRevert("HubVault: caller is not governance");
        vault.registerVenue(venue3);
    }

    function test_RemoveVenue() public {
        vm.expectEmit(true, false, false, false);
        emit VenueRemoved(venue1);

        vm.prank(governance);
        vault.removeVenue(venue1);

        assertFalse(vault.registeredVenues(venue1));
        assertEq(vault.venueCount(), 1);
    }

    function test_RemoveVenueRevertsNotRegistered() public {
        vm.prank(governance);
        vm.expectRevert("HubVault: venue not registered");
        vault.removeVenue(venue3);
    }

    function test_RemoveVenueRevertsNonGovernance() public {
        vm.prank(nobody);
        vm.expectRevert("HubVault: caller is not governance");
        vault.removeVenue(venue1);
    }

    function test_SetKeeper() public {
        address newKeeper = makeAddr("newKeeper");

        vm.prank(governance);
        vault.setKeeper(newKeeper);

        assertEq(vault.keeper(), newKeeper);
    }

    function test_SetKeeperRevertsZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert("HubVault: zero address");
        vault.setKeeper(address(0));
    }

    function test_SetKeeperRevertsNonGovernance() public {
        vm.prank(nobody);
        vm.expectRevert("HubVault: caller is not governance");
        vault.setKeeper(makeAddr("newKeeper"));
    }

    function test_SetHaircutBps() public {
        uint256 newHaircut = 6000;

        vm.prank(governance);
        vault.setHaircutBps(newHaircut);

        assertEq(vault.haircutBps(), newHaircut);
    }

    function test_SetHaircutBpsRevertsExceedsMax() public {
        vm.prank(governance);
        vm.expectRevert("HubVault: haircut exceeds 100%");
        vault.setHaircutBps(10001);
    }

    function test_SetHaircutBpsRevertsNonGovernance() public {
        vm.prank(nobody);
        vm.expectRevert("HubVault: caller is not governance");
        vault.setHaircutBps(6000);
    }

    function test_SetMaxVenueAllocationBps() public {
        uint256 newMax = 7000;

        vm.prank(governance);
        vault.setMaxVenueAllocationBps(newMax);

        assertEq(vault.maxVenueAllocationBps(), newMax);
    }

    function test_SetMaxVenueAllocationBpsRevertsExceedsMax() public {
        vm.prank(governance);
        vm.expectRevert("HubVault: allocation exceeds 100%");
        vault.setMaxVenueAllocationBps(10001);
    }

    function test_SetOverspendThresholdBps() public {
        uint256 newThreshold = 8500;

        vm.prank(governance);
        vault.setOverspendThresholdBps(newThreshold);

        assertEq(vault.overspendThresholdBps(), newThreshold);
    }

    function test_SetOverspendThresholdBpsRevertsExceedsMax() public {
        vm.prank(governance);
        vm.expectRevert("HubVault: threshold exceeds 100%");
        vault.setOverspendThresholdBps(10001);
    }

    // ──────────────────────────── View Function Tests ────────────────────────────

    function test_GetUserPortfolio() public {
        uint256 depositAmount = 10_000e6;
        uint256 marginAmount = 3_000e6;
        uint256 insuranceAmount = 5_000e6;

        vm.prank(user1);
        vault.depositCollateral(depositAmount);

        vm.prank(keeper);
        vault.updateMarginLocked(user1, marginAmount);

        vm.prank(keeper);
        vault.depositInsurance(insuranceAmount);

        (
            uint256 userCollateral,
            uint256 marginLocked,
            uint256 available,
            uint256 insurancePoolBalance
        ) = vault.getUserPortfolio(user1);

        assertEq(userCollateral, depositAmount);
        assertEq(marginLocked, marginAmount);
        assertEq(available, depositAmount - marginAmount);
        assertEq(insurancePoolBalance, insuranceAmount);
    }

    function test_GetVenueEquity() public {
        uint256 equity = 5_000e6;
        bytes32 eventId = keccak256("event1");

        vm.prank(keeper);
        vault.updateVenueEquity(user1, venue1, equity, eventId);

        assertEq(vault.getVenueEquity(user1, venue1), equity);
    }

    function test_VenueCount() public view {
        assertEq(vault.venueCount(), 2); // venue1 and venue2 registered in setUp
    }

    function test_GetVenueList() public view {
        address[] memory venues = vault.getVenueList();
        assertEq(venues.length, 2);
        assertEq(venues[0], venue1);
        assertEq(venues[1], venue2);
    }

    // ──────────────────────────── Integration Tests ────────────────────────────

    function test_MultiUserMultiVenueScenario() public {
        // User1 deposits
        vm.prank(user1);
        vault.depositCollateral(50_000e6);

        // User2 deposits
        vm.prank(user2);
        vault.depositCollateral(30_000e6);

        // Update equities
        bytes32 event1 = keccak256("event1");
        vm.prank(keeper);
        vault.updateVenueEquity(user1, venue1, 25_000e6, event1);

        bytes32 event2 = keccak256("event2");
        vm.prank(keeper);
        vault.updateVenueEquity(user1, venue2, 25_000e6, event2);

        bytes32 event3 = keccak256("event3");
        vm.prank(keeper);
        vault.updateVenueEquity(user2, venue1, 30_000e6, event3);

        // Lock margins
        vm.prank(keeper);
        vault.updateMarginLocked(user1, 40_000e6);

        vm.prank(keeper);
        vault.updateMarginLocked(user2, 20_000e6);

        // Verify state
        assertEq(vault.availableBalance(user1), 10_000e6);
        assertEq(vault.availableBalance(user2), 10_000e6);
        assertEq(vault.getVenueEquity(user1, venue1), 25_000e6);
        assertEq(vault.getVenueEquity(user1, venue2), 25_000e6);
        assertEq(vault.getVenueEquity(user2, venue1), 30_000e6);
    }
}
