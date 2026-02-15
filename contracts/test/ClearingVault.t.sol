// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/ClearingVault.sol";
import "../src/MarginVault.sol";

contract ClearingVaultTest is Test {
    MockUSDC usdc;
    ClearingVault clearing;
    MarginVault vaultA;
    MarginVault vaultB;
    MarginVault vaultC;

    address governance = makeAddr("governance");
    address settlement = makeAddr("settlement");
    address brokerA = makeAddr("brokerA");
    address brokerB = makeAddr("brokerB");
    address brokerC = makeAddr("brokerC");

    uint256 constant INITIAL_MINT = 1_000_000e6; // 1M USDC
    uint256 constant NETTING_WINDOW = 3600; // 1 hour

    function setUp() public {
        usdc = new MockUSDC();
        
        clearing = new ClearingVault(
            address(usdc),
            governance,
            settlement,
            NETTING_WINDOW
        );

        // Create 3 margin vaults
        vaultA = new MarginVault(address(usdc), brokerA, settlement, 1000);
        vaultB = new MarginVault(address(usdc), brokerB, settlement, 1000);
        vaultC = new MarginVault(address(usdc), brokerC, settlement, 1000);

        // Set clearing vault on each margin vault
        vm.prank(brokerA);
        vaultA.setClearingVault(address(clearing));
        vm.prank(brokerB);
        vaultB.setClearingVault(address(clearing));
        vm.prank(brokerC);
        vaultC.setClearingVault(address(clearing));

        // Mint USDC
        usdc.mint(brokerA, INITIAL_MINT);
        usdc.mint(brokerB, INITIAL_MINT);
        usdc.mint(brokerC, INITIAL_MINT);

        // Approve
        vm.prank(brokerA);
        usdc.approve(address(vaultA), type(uint256).max);
        vm.prank(brokerB);
        usdc.approve(address(vaultB), type(uint256).max);
        vm.prank(brokerC);
        usdc.approve(address(vaultC), type(uint256).max);

        vm.prank(brokerA);
        usdc.approve(address(clearing), type(uint256).max);
        vm.prank(brokerB);
        usdc.approve(address(clearing), type(uint256).max);
        vm.prank(brokerC);
        usdc.approve(address(clearing), type(uint256).max);

        // Vaults approve clearing vault for transfers
        vm.prank(address(vaultA));
        usdc.approve(address(clearing), type(uint256).max);
        vm.prank(address(vaultB));
        usdc.approve(address(clearing), type(uint256).max);
        vm.prank(address(vaultC));
        usdc.approve(address(clearing), type(uint256).max);

        // Register vaults in clearing
        vm.startPrank(governance);
        clearing.registerVault(address(vaultA));
        clearing.registerVault(address(vaultB));
        clearing.registerVault(address(vaultC));
        vm.stopPrank();
    }

    // ═══════════════════════ Vault Registration ═══════════════════════

    function test_registerVault() public {
        MarginVault vaultD = new MarginVault(address(usdc), makeAddr("brokerD"), settlement, 1000);
        
        vm.prank(governance);
        clearing.registerVault(address(vaultD));
        
        assertTrue(clearing.registeredVaults(address(vaultD)));
    }

    function test_registerVault_emitsEvent() public {
        MarginVault vaultD = new MarginVault(address(usdc), makeAddr("brokerD"), settlement, 1000);
        
        vm.expectEmit(true, false, false, false);
        emit ClearingVault.VaultRegistered(address(vaultD));
        
        vm.prank(governance);
        clearing.registerVault(address(vaultD));
    }

    function test_registerVault_revertsUnauthorized() public {
        MarginVault vaultD = new MarginVault(address(usdc), makeAddr("brokerD"), settlement, 1000);
        
        vm.prank(makeAddr("nobody"));
        vm.expectRevert(ClearingVault.Unauthorized.selector);
        clearing.registerVault(address(vaultD));
    }

    function test_removeVault() public {
        vm.prank(governance);
        clearing.removeVault(address(vaultA));
        
        assertFalse(clearing.registeredVaults(address(vaultA)));
    }

    // ═══════════════════════ Guarantee Deposits ═══════════════════════

    function test_depositGuarantee() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        
        vm.prank(address(vaultA));
        clearing.depositGuarantee(1000e6);
        
        assertEq(clearing.guaranteeDeposits(address(vaultA)), 1000e6);
    }

    function test_depositGuarantee_emitsEvent() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        
        vm.expectEmit(true, false, false, true);
        emit ClearingVault.GuaranteeDeposited(address(vaultA), 1000e6);
        
        vm.prank(address(vaultA));
        clearing.depositGuarantee(1000e6);
    }

    function test_withdrawGuarantee() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        
        vm.prank(address(vaultA));
        clearing.depositGuarantee(1000e6);
        
        vm.prank(address(vaultA));
        clearing.withdrawGuarantee(500e6);
        
        assertEq(clearing.guaranteeDeposits(address(vaultA)), 500e6);
    }

    function test_withdrawGuarantee_revertsBelowMinimum() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        
        vm.prank(address(vaultA));
        clearing.depositGuarantee(1000e6);
        
        vm.prank(governance);
        clearing.setMinimumGuarantee(address(vaultA), 800e6);
        
        vm.prank(address(vaultA));
        vm.expectRevert(ClearingVault.BelowMinimumGuarantee.selector);
        clearing.withdrawGuarantee(300e6); // Would leave 700, below 800
    }

    // ═══════════════════════ Obligation Recording ═══════════════════════

    function test_recordObligation() public {
        vm.prank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        
        assertEq(clearing.pendingObligationCount(), 1);
    }

    function test_recordObligation_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit ClearingVault.ObligationRecorded(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        
        vm.prank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
    }

    function test_recordObligation_revertsDuplicate() public {
        vm.prank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        
        vm.prank(settlement);
        vm.expectRevert(ClearingVault.DuplicateObligation.selector);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
    }

    // ═══════════════════════ Netting - Bilateral ═══════════════════════

    function test_netting_bilateral_simple() public {
        // Fund broker stakes
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        // Record obligations: A owes B 1000, B owes A 600
        // Net: A owes B 400
        vm.startPrank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        clearing.recordObligation(address(vaultB), address(vaultA), 600e6, bytes32("ref2"));
        vm.stopPrank();

        // Wait for netting window
        vm.warp(block.timestamp + NETTING_WINDOW + 1);

        // Execute netting
        clearing.executeNetting();

        // Net result: A sent 400 to B
        assertEq(vaultA.brokerStake(), 9600e6);
        assertEq(vaultB.brokerStake(), 10400e6);
        assertEq(clearing.pendingObligationCount(), 0);
    }

    function test_netting_bilateral_reverseNet() public {
        // Fund broker stakes
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        // Record obligations: A owes B 600, B owes A 1000
        // Net: B owes A 400
        vm.startPrank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 600e6, bytes32("ref1"));
        clearing.recordObligation(address(vaultB), address(vaultA), 1000e6, bytes32("ref2"));
        vm.stopPrank();

        // Wait for netting window
        vm.warp(block.timestamp + NETTING_WINDOW + 1);

        // Execute netting
        clearing.executeNetting();

        // Net result: B sent 400 to A
        assertEq(vaultA.brokerStake(), 10400e6);
        assertEq(vaultB.brokerStake(), 9600e6);
    }

    function test_netting_bilateral_perfectOffset() public {
        // Fund broker stakes
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        // Record obligations: A owes B 1000, B owes A 1000
        // Net: 0 (perfect offset)
        vm.startPrank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        clearing.recordObligation(address(vaultB), address(vaultA), 1000e6, bytes32("ref2"));
        vm.stopPrank();

        // Wait for netting window
        vm.warp(block.timestamp + NETTING_WINDOW + 1);

        // Execute netting
        clearing.executeNetting();

        // No transfers
        assertEq(vaultA.brokerStake(), 10000e6);
        assertEq(vaultB.brokerStake(), 10000e6);
    }

    // ═══════════════════════ Netting - Multilateral ═══════════════════════

    function test_netting_multilateral_threeWay() public {
        // Fund broker stakes
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);
        vm.prank(brokerC);
        vaultC.depositBrokerStake(10000e6);

        // Obligations:
        // A → B: 1000
        // B → C: 800
        // C → A: 500
        vm.startPrank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        clearing.recordObligation(address(vaultB), address(vaultC), 800e6, bytes32("ref2"));
        clearing.recordObligation(address(vaultC), address(vaultA), 500e6, bytes32("ref3"));
        vm.stopPrank();

        // Wait for netting window
        vm.warp(block.timestamp + NETTING_WINDOW + 1);

        // Execute netting
        clearing.executeNetting();

        // Net calculations:
        // A: -1000 (to B) +500 (from C) = -500
        // B: +1000 (from A) -800 (to C) = +200
        // C: +800 (from B) -500 (to A) = +300
        
        assertEq(vaultA.brokerStake(), 9500e6);
        assertEq(vaultB.brokerStake(), 10200e6);
        assertEq(vaultC.brokerStake(), 10300e6);
    }

    function test_netting_multilateral_complex() public {
        // Fund broker stakes
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);
        vm.prank(brokerC);
        vaultC.depositBrokerStake(10000e6);

        // Complex obligations
        vm.startPrank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        clearing.recordObligation(address(vaultA), address(vaultC), 500e6, bytes32("ref2"));
        clearing.recordObligation(address(vaultB), address(vaultA), 300e6, bytes32("ref3"));
        clearing.recordObligation(address(vaultB), address(vaultC), 700e6, bytes32("ref4"));
        clearing.recordObligation(address(vaultC), address(vaultA), 200e6, bytes32("ref5"));
        clearing.recordObligation(address(vaultC), address(vaultB), 100e6, bytes32("ref6"));
        vm.stopPrank();

        // Wait for netting window
        vm.warp(block.timestamp + NETTING_WINDOW + 1);

        // Execute netting
        clearing.executeNetting();

        // Verify balances changed correctly
        assertEq(vaultA.brokerStake() + vaultB.brokerStake() + vaultC.brokerStake(), 30000e6);
    }

    // ═══════════════════════ Netting Window ═══════════════════════

    function test_netting_revertsBeforeWindowElapsed() public {
        vm.prank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        
        vm.expectRevert(ClearingVault.NettingWindowNotElapsed.selector);
        clearing.executeNetting();
    }

    function test_netting_allowsAfterWindow() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        vm.prank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        
        vm.warp(block.timestamp + NETTING_WINDOW + 1);
        clearing.executeNetting();
        
        assertEq(clearing.pendingObligationCount(), 0);
    }

    // ═══════════════════════ Default Waterfall ═══════════════════════

    function test_defaultWaterfall_guaranteeCovers() public {
        // Fund broker stakes
        vm.prank(brokerA);
        vaultA.depositBrokerStake(100e6); // Small stake
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        // Deposit guarantee from broker A's USDC
        usdc.mint(address(vaultA), 1000e6);
        vm.prank(address(vaultA));
        usdc.approve(address(clearing), 1000e6);
        vm.prank(address(vaultA));
        clearing.depositGuarantee(1000e6);

        // Record obligation: A owes B 500
        vm.prank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 500e6, bytes32("ref1"));

        vm.warp(block.timestamp + NETTING_WINDOW + 1);
        clearing.executeNetting();

        // A couldn't pay from broker stake, used guarantee
        assertEq(clearing.guaranteeDeposits(address(vaultA)), 500e6); // 1000 - 500
        assertEq(vaultB.brokerStake(), 10500e6);
    }

    function test_defaultWaterfall_defaultFundCovers() public {
        // Fund broker stakes
        vm.prank(brokerA);
        vaultA.depositBrokerStake(100e6); // Small stake
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        // Deposit default fund
        usdc.mint(makeAddr("donor"), 5000e6);
        vm.prank(makeAddr("donor"));
        usdc.approve(address(clearing), type(uint256).max);
        vm.prank(makeAddr("donor"));
        clearing.depositDefaultFund(5000e6);

        // Record obligation: A owes B 500
        vm.prank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 500e6, bytes32("ref1"));

        vm.warp(block.timestamp + NETTING_WINDOW + 1);
        clearing.executeNetting();

        // Used default fund
        assertEq(clearing.defaultFund(), 4500e6); // 5000 - 500
        assertEq(vaultB.brokerStake(), 10500e6);
    }

    // ═══════════════════════ Immediate Settlement ═══════════════════════

    function test_settleImmediate() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        vm.prank(settlement);
        clearing.settleImmediate(address(vaultA), address(vaultB), 500e6, bytes32("ref1"));

        assertEq(vaultA.brokerStake(), 9500e6);
        assertEq(vaultB.brokerStake(), 10500e6);
    }

    function test_settleImmediate_emitsEvent() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        vm.expectEmit(true, true, false, true);
        emit ClearingVault.ImmediateSettlement(address(vaultA), address(vaultB), 500e6, bytes32("ref1"));

        vm.prank(settlement);
        clearing.settleImmediate(address(vaultA), address(vaultB), 500e6, bytes32("ref1"));
    }

    // ═══════════════════════ View Functions ═══════════════════════

    function test_netObligation() public {
        vm.startPrank(settlement);
        clearing.recordObligation(address(vaultA), address(vaultB), 1000e6, bytes32("ref1"));
        clearing.recordObligation(address(vaultB), address(vaultA), 600e6, bytes32("ref2"));
        vm.stopPrank();

        int256 net = clearing.netObligation(address(vaultA), address(vaultB));
        assertEq(net, 400e6); // A owes B net 400
    }

    function test_totalGuaranteeDeposits() public {
        vm.prank(brokerA);
        vaultA.depositBrokerStake(10000e6);
        vm.prank(brokerB);
        vaultB.depositBrokerStake(10000e6);

        vm.prank(address(vaultA));
        clearing.depositGuarantee(1000e6);
        vm.prank(address(vaultB));
        clearing.depositGuarantee(2000e6);

        assertEq(clearing.totalGuaranteeDeposits(), 3000e6);
    }

    function test_getVaultList() public view {
        address[] memory vaults = clearing.getVaultList();
        assertEq(vaults.length, 3);
        assertEq(vaults[0], address(vaultA));
        assertEq(vaults[1], address(vaultB));
        assertEq(vaults[2], address(vaultC));
    }

    // ═══════════════════════ Default Fund ═══════════════════════

    function test_depositDefaultFund() public {
        usdc.mint(makeAddr("donor"), 5000e6);
        vm.prank(makeAddr("donor"));
        usdc.approve(address(clearing), type(uint256).max);
        
        vm.prank(makeAddr("donor"));
        clearing.depositDefaultFund(5000e6);
        
        assertEq(clearing.defaultFund(), 5000e6);
    }
}
