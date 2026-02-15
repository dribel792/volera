// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/MarginVault.sol";

contract MarginVaultTest is Test {
    MockUSDC usdc;
    MarginVault vault;

    address broker = makeAddr("broker");
    address settlement = makeAddr("settlement");
    address clearingVault = makeAddr("clearingVault");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address nobody = makeAddr("nobody");

    uint256 constant INITIAL_MINT = 100_000e6; // 100k USDC
    uint256 constant MIN_STAKE_RATIO = 1000; // 10%

    function setUp() public {
        usdc = new MockUSDC();
        vault = new MarginVault(
            address(usdc),
            broker,
            settlement,
            MIN_STAKE_RATIO
        );

        // Set clearing vault
        vm.prank(broker);
        vault.setClearingVault(clearingVault);

        // Mint USDC to test actors
        usdc.mint(user1, INITIAL_MINT);
        usdc.mint(user2, INITIAL_MINT);
        usdc.mint(broker, INITIAL_MINT);
        usdc.mint(clearingVault, INITIAL_MINT);

        // Approve vault
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(broker);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(clearingVault);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════ Helpers ═══════════════════════

    function _depositCollateral(address user, uint256 amt) internal {
        vm.prank(user);
        vault.depositCollateral(amt);
    }

    function _depositBrokerStake(uint256 amt) internal {
        vm.prank(broker);
        vault.depositBrokerStake(amt);
    }

    function _creditPnl(address user, uint256 amt, bytes32 refId) internal {
        vm.prank(settlement);
        vault.creditPnl(user, amt, refId);
    }

    function _seize(address user, uint256 amt, bytes32 refId) internal returns (uint256) {
        vm.prank(settlement);
        return vault.seizeCollateral(user, amt, refId);
    }

    function _lockMargin(address user, uint256 amt, bytes32 posId) internal {
        vm.prank(settlement);
        vault.lockMargin(user, amt, posId);
    }

    function _unlockMargin(address user, uint256 amt, bytes32 posId) internal {
        vm.prank(settlement);
        vault.unlockMargin(user, amt, posId);
    }

    // ═══════════════════════ User Deposit/Withdraw ═══════════════════════

    function test_depositCollateral() public {
        _depositCollateral(user1, 1000e6);
        assertEq(vault.balances(user1), 1000e6);
        assertEq(vault.balanceOf(user1), 1000e6);
        assertEq(usdc.balanceOf(address(vault)), 1000e6);
    }

    function test_depositCollateral_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit MarginVault.CollateralDeposited(user1, 500e6);
        _depositCollateral(user1, 500e6);
    }

    function test_depositCollateral_revertsZero() public {
        vm.prank(user1);
        vm.expectRevert(MarginVault.ZeroAmount.selector);
        vault.depositCollateral(0);
    }

    function test_withdrawAvailable() public {
        _depositCollateral(user1, 1000e6);
        
        vm.prank(user1);
        vault.withdrawAvailable(500e6);
        
        assertEq(vault.balances(user1), 500e6);
        assertEq(usdc.balanceOf(user1), INITIAL_MINT - 1000e6 + 500e6);
    }

    function test_withdrawAvailable_canAlwaysWithdrawAvailableFunds() public {
        _depositCollateral(user1, 1000e6);
        
        // Even when paused, user can withdraw available (pause only affects settlements)
        vm.prank(broker);
        vault.pauseSettlements();
        
        vm.prank(user1);
        vault.withdrawAvailable(500e6);
        
        assertEq(vault.balances(user1), 500e6);
    }

    function test_withdrawAvailable_revertsInsufficientBalance() public {
        _depositCollateral(user1, 1000e6);
        
        vm.prank(user1);
        vm.expectRevert(MarginVault.InsufficientBalance.selector);
        vault.withdrawAvailable(1001e6);
    }

    function test_withdrawAvailable_revertsWhenMarginLocked() public {
        _depositCollateral(user1, 1000e6);
        _lockMargin(user1, 600e6, bytes32("pos1"));
        
        // Available = 1000 - 600 = 400
        assertEq(vault.availableBalance(user1), 400e6);
        
        vm.prank(user1);
        vm.expectRevert(MarginVault.InsufficientBalance.selector);
        vault.withdrawAvailable(500e6); // Trying to withdraw more than available
    }

    function test_availableBalance() public {
        _depositCollateral(user1, 1000e6);
        assertEq(vault.availableBalance(user1), 1000e6);
        
        _lockMargin(user1, 300e6, bytes32("pos1"));
        assertEq(vault.availableBalance(user1), 700e6);
        
        _lockMargin(user1, 200e6, bytes32("pos2"));
        assertEq(vault.availableBalance(user1), 500e6);
    }

    // ═══════════════════════ Margin Locking ═══════════════════════

    function test_lockMargin() public {
        _depositCollateral(user1, 1000e6);
        _lockMargin(user1, 300e6, bytes32("pos1"));
        
        assertEq(vault.marginInUse(user1), 300e6);
        assertEq(vault.availableBalance(user1), 700e6);
    }

    function test_lockMargin_emitsEvent() public {
        _depositCollateral(user1, 1000e6);
        
        vm.expectEmit(true, false, false, true);
        emit MarginVault.MarginLocked(user1, 300e6, bytes32("pos1"));
        _lockMargin(user1, 300e6, bytes32("pos1"));
    }

    function test_lockMargin_revertsInsufficientBalance() public {
        _depositCollateral(user1, 1000e6);
        
        vm.prank(settlement);
        vm.expectRevert(MarginVault.InsufficientBalance.selector);
        vault.lockMargin(user1, 1001e6, bytes32("pos1"));
    }

    function test_lockMargin_revertsUnauthorized() public {
        _depositCollateral(user1, 1000e6);
        
        vm.prank(nobody);
        vm.expectRevert(MarginVault.Unauthorized.selector);
        vault.lockMargin(user1, 300e6, bytes32("pos1"));
    }

    function test_unlockMargin() public {
        _depositCollateral(user1, 1000e6);
        _lockMargin(user1, 300e6, bytes32("pos1"));
        
        _unlockMargin(user1, 300e6, bytes32("pos1"));
        
        assertEq(vault.marginInUse(user1), 0);
        assertEq(vault.availableBalance(user1), 1000e6);
    }

    function test_unlockMargin_partial() public {
        _depositCollateral(user1, 1000e6);
        _lockMargin(user1, 300e6, bytes32("pos1"));
        
        _unlockMargin(user1, 100e6, bytes32("pos1"));
        
        assertEq(vault.marginInUse(user1), 200e6);
        assertEq(vault.availableBalance(user1), 800e6);
    }

    // ═══════════════════════ PnL Settlement ═══════════════════════

    function test_creditPnl() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 1000e6);
        
        _creditPnl(user1, 500e6, bytes32("ref1"));
        
        assertEq(vault.balances(user1), 1500e6);
        assertEq(vault.brokerStake(), 9500e6);
    }

    function test_creditPnl_emitsEvent() public {
        _depositBrokerStake(10000e6);
        
        vm.expectEmit(true, false, false, true);
        emit MarginVault.PnLCredited(user1, 500e6, bytes32("ref1"));
        _creditPnl(user1, 500e6, bytes32("ref1"));
    }

    function test_creditPnl_revertsInsufficientBrokerStake() public {
        _depositBrokerStake(100e6);
        
        vm.prank(settlement);
        vm.expectRevert(MarginVault.InsufficientBrokerStake.selector);
        vault.creditPnl(user1, 200e6, bytes32("ref1"));
    }

    function test_creditPnl_revertsDuplicateRefId() public {
        _depositBrokerStake(10000e6);
        _creditPnl(user1, 500e6, bytes32("ref1"));
        
        vm.prank(settlement);
        vm.expectRevert(MarginVault.DuplicateRefId.selector);
        vault.creditPnl(user1, 500e6, bytes32("ref1"));
    }

    function test_seizeCollateral() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 1000e6);
        
        _seize(user1, 300e6, bytes32("ref1"));
        
        assertEq(vault.balances(user1), 700e6);
        assertEq(vault.brokerStake(), 10300e6);
    }

    function test_seizeCollateral_emitsEvent() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 1000e6);
        
        vm.expectEmit(true, false, false, true);
        emit MarginVault.CollateralSeized(user1, 300e6, bytes32("ref1"));
        _seize(user1, 300e6, bytes32("ref1"));
    }

    // ═══════════════════════ Insurance Waterfall ═══════════════════════

    function test_seizeCollateral_insuranceWaterfall_userHasEnough() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 1000e6);
        
        uint256 shortfall = _seize(user1, 800e6, bytes32("ref1"));
        
        assertEq(shortfall, 0);
        assertEq(vault.balances(user1), 200e6);
        assertEq(vault.brokerStake(), 10800e6);
    }

    function test_seizeCollateral_insuranceWaterfall_insuranceFundCovers() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 500e6);
        
        // Deposit insurance
        vm.prank(broker);
        vault.depositInsurance(1000e6);
        
        // Try to seize 800, user only has 500
        uint256 shortfall = _seize(user1, 800e6, bytes32("ref1"));
        
        assertEq(shortfall, 300e6);
        assertEq(vault.balances(user1), 0);
        assertEq(vault.insuranceFund(), 700e6); // 1000 - 300
        assertEq(vault.brokerStake(), 10800e6); // 10000 + 500 (seized) + 300 (insurance)
    }

    function test_seizeCollateral_insuranceWaterfall_brokerStakeCovers() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 500e6);
        
        // No insurance fund
        // Try to seize 800, user only has 500
        uint256 shortfall = _seize(user1, 800e6, bytes32("ref1"));
        
        assertEq(shortfall, 300e6);
        assertEq(vault.balances(user1), 0);
        assertEq(vault.insuranceFund(), 0);
        assertEq(vault.brokerStake(), 10500e6); // Absorbed by broker stake
    }

    function test_seizeCollateral_insuranceWaterfall_socializedLoss() public {
        _depositBrokerStake(100e6); // Small broker stake
        _depositCollateral(user1, 50e6);
        
        // Try to seize 300, user only has 50, broker stake only 100
        uint256 shortfall = _seize(user1, 300e6, bytes32("ref1"));
        
        assertEq(shortfall, 250e6);
        assertEq(vault.balances(user1), 0);
        assertEq(vault.brokerStake(), 150e6); // 100 + 50 (seized)
        // Shortfall = 250, broker can cover 150 (current stake after seizing), socialized = 100
        assertEq(vault.socializedLoss(), 100e6); // 250 - 150 (broker stake covers) = 100
    }

    // ═══════════════════════ Broker Stake ═══════════════════════

    function test_depositBrokerStake() public {
        _depositBrokerStake(5000e6);
        assertEq(vault.brokerStake(), 5000e6);
    }

    function test_withdrawBrokerStake() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 5000e6);
        
        // Min required = 5000 * 10% = 500
        vm.prank(broker);
        vault.withdrawBrokerStake(9000e6);
        
        assertEq(vault.brokerStake(), 1000e6);
    }

    function test_withdrawBrokerStake_revertsBelowMinimum() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 50000e6);
        
        // Min required = 50000 * 10% = 5000
        vm.prank(broker);
        vm.expectRevert(MarginVault.BelowMinimumStake.selector);
        vault.withdrawBrokerStake(6000e6); // Would leave 4000, below 5000
    }

    function test_minimumRequired() public {
        _depositCollateral(user1, 10000e6);
        _depositCollateral(user2, 20000e6);
        
        // Total deposits = 30000, min = 10% = 3000
        assertEq(vault.minimumRequired(), 3000e6);
    }

    // ═══════════════════════ Liquidation ═══════════════════════

    function test_liquidate() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 1000e6);
        _lockMargin(user1, 500e6, bytes32("pos1"));
        
        vm.prank(settlement);
        vault.liquidate(user1, bytes32("pos1"), 500e6, bytes32("liq1"));
        
        assertEq(vault.marginInUse(user1), 0);
        assertEq(vault.balances(user1), 500e6);
        assertEq(vault.brokerStake(), 10500e6);
    }

    function test_liquidate_emitsEvent() public {
        _depositBrokerStake(10000e6);
        _depositCollateral(user1, 1000e6);
        _lockMargin(user1, 500e6, bytes32("pos1"));
        
        vm.expectEmit(true, false, false, true);
        emit MarginVault.Liquidation(user1, bytes32("pos1"), 500e6);
        
        vm.prank(settlement);
        vault.liquidate(user1, bytes32("pos1"), 500e6, bytes32("liq1"));
    }

    // ═══════════════════════ Clearing Vault Integration ═══════════════════════

    function test_transferToClearing() public {
        _depositBrokerStake(10000e6);
        
        vm.prank(clearingVault);
        vault.transferToClearing(500e6);
        
        assertEq(vault.brokerStake(), 9500e6);
        assertEq(usdc.balanceOf(clearingVault), INITIAL_MINT + 500e6);
    }

    function test_transferToClearing_revertsUnauthorized() public {
        _depositBrokerStake(10000e6);
        
        vm.prank(nobody);
        vm.expectRevert(MarginVault.Unauthorized.selector);
        vault.transferToClearing(500e6);
    }

    function test_receiveFromClearing() public {
        _depositBrokerStake(10000e6);
        
        vm.prank(clearingVault);
        vault.receiveFromClearing(500e6);
        
        assertEq(vault.brokerStake(), 10500e6);
    }

    // ═══════════════════════ Refid Dedup ═══════════════════════

    function test_refIdDedup_creditPnl() public {
        _depositBrokerStake(10000e6);
        _creditPnl(user1, 100e6, bytes32("ref1"));
        
        vm.prank(settlement);
        vm.expectRevert(MarginVault.DuplicateRefId.selector);
        vault.creditPnl(user1, 100e6, bytes32("ref1"));
    }

    function test_refIdDedup_seizeCollateral() public {
        _depositCollateral(user1, 1000e6);
        _seize(user1, 100e6, bytes32("ref1"));
        
        vm.prank(settlement);
        vm.expectRevert(MarginVault.DuplicateRefId.selector);
        vault.seizeCollateral(user1, 100e6, bytes32("ref1"));
    }

    // ═══════════════════════ Vault Health ═══════════════════════

    function test_vaultHealth() public {
        _depositCollateral(user1, 10000e6);
        _depositCollateral(user2, 20000e6);
        _depositBrokerStake(5000e6);
        
        vm.prank(broker);
        vault.depositInsurance(1000e6);
        
        (uint256 totalDeposits, uint256 stake, uint256 insurance, uint256 ratio) = vault.vaultHealth();
        
        assertEq(totalDeposits, 30000e6);
        assertEq(stake, 5000e6);
        assertEq(insurance, 1000e6);
        assertEq(ratio, 1666); // 5000/30000 * 10000 = 1666 bps = 16.66%
    }
}
