// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/UnifiedAccountVault.sol";

contract UnifiedAccountVaultTest is Test {
    MockUSDC usdc;
    UnifiedAccountVault vault;

    address admin = makeAddr("admin");
    address settlementRole = makeAddr("settlement");
    address brokerRole = makeAddr("broker");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address nobody = makeAddr("nobody");

    uint256 constant INITIAL_MINT = 100_000e6; // 100k USDC

    function setUp() public {
        usdc = new MockUSDC();
        vault = new UnifiedAccountVault(
            address(usdc),
            admin,
            settlementRole,
            brokerRole
        );

        // Mint USDC to test actors
        usdc.mint(user1, INITIAL_MINT);
        usdc.mint(user2, INITIAL_MINT);
        usdc.mint(brokerRole, INITIAL_MINT);

        // Approve vault
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(brokerRole);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════ Helpers ═══════════════════════

    function _depositCollateral(address user, uint256 amt) internal {
        vm.prank(user);
        vault.depositCollateral(amt);
    }

    function _brokerDeposit(uint256 amt) internal {
        vm.prank(brokerRole);
        vault.brokerDeposit(amt);
    }

    function _creditPnl(address user, uint256 amt, bytes32 refId) internal {
        vm.prank(settlementRole);
        vault.creditPnl(user, amt, refId);
    }

    function _seize(address user, uint256 amt, bytes32 refId) internal {
        vm.prank(settlementRole);
        vault.seizeCollateral(user, amt, refId);
    }

    // ═══════════════════════ MockUSDC ═══════════════════════

    function test_MockUSDC_decimals() public view {
        assertEq(usdc.decimals(), 6);
    }

    function test_MockUSDC_name() public view {
        assertEq(usdc.name(), "Mock USDC");
        assertEq(usdc.symbol(), "USDC");
    }

    function test_MockUSDC_anyoneCanMint() public {
        vm.prank(nobody);
        usdc.mint(nobody, 1000e6);
        assertEq(usdc.balanceOf(nobody), 1000e6);
    }

    // ═══════════════════════ Deposit Collateral ═══════════════════════

    function test_depositCollateral() public {
        _depositCollateral(user1, 1000e6);
        assertEq(vault.collateral(user1), 1000e6);
        assertEq(usdc.balanceOf(address(vault)), 1000e6);
    }

    function test_depositCollateral_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit UnifiedAccountVault.CollateralDeposited(user1, 500e6);
        _depositCollateral(user1, 500e6);
    }

    function test_depositCollateral_revertsZero() public {
        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.ZeroAmount.selector);
        vault.depositCollateral(0);
    }

    // ═══════════════════════ Withdraw Collateral ═══════════════════════

    function test_withdrawCollateral() public {
        _depositCollateral(user1, 1000e6);
        vm.prank(user1);
        vault.withdrawCollateral(400e6);
        assertEq(vault.collateral(user1), 600e6);
        assertEq(usdc.balanceOf(user1), INITIAL_MINT - 600e6);
    }

    function test_withdrawCollateral_emitsEvent() public {
        _depositCollateral(user1, 1000e6);
        vm.expectEmit(true, false, false, true);
        emit UnifiedAccountVault.CollateralWithdrawn(user1, 400e6);
        vm.prank(user1);
        vault.withdrawCollateral(400e6);
    }

    function test_withdrawCollateral_revertsInsufficientBalance() public {
        _depositCollateral(user1, 100e6);
        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.InsufficientBalance.selector);
        vault.withdrawCollateral(200e6);
    }

    function test_withdrawCollateral_revertsZero() public {
        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.ZeroAmount.selector);
        vault.withdrawCollateral(0);
    }

    // ═══════════════════════ Happy Path: Win ═══════════════════════

    function test_happyPath_win() public {
        // 1. User deposits collateral
        _depositCollateral(user1, 5000e6);
        // 2. Broker funds pool
        _brokerDeposit(10_000e6);
        // 3. User wins trade → credit PnL
        bytes32 refId = keccak256("trade-win-001");
        _creditPnl(user1, 100e6, refId);

        assertEq(vault.pnl(user1), 100e6);
        assertEq(vault.brokerPool(), 10_000e6 - 100e6);

        // 4. User withdraws PnL
        vm.prank(user1);
        vault.withdrawPnL(100e6);
        assertEq(vault.pnl(user1), 0);
        assertEq(usdc.balanceOf(user1), INITIAL_MINT - 5000e6 + 100e6);
    }

    // ═══════════════════════ Happy Path: Loss ═══════════════════════

    function test_happyPath_loss() public {
        // 1. User deposits collateral
        _depositCollateral(user1, 5000e6);
        // 2. Broker funds pool
        _brokerDeposit(10_000e6);
        // 3. User loses trade → seize collateral
        _seize(user1, 200e6, keccak256("seize1"));

        assertEq(vault.collateral(user1), 4800e6);
        assertEq(vault.brokerPool(), 10_000e6 + 200e6);
    }

    // ═══════════════════════ WithdrawPnL ═══════════════════════

    function test_withdrawPnL_revertsInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.InsufficientBalance.selector);
        vault.withdrawPnL(1e6);
    }

    function test_withdrawPnL_emitsEvent() public {
        _depositCollateral(user1, 1000e6);
        _brokerDeposit(5000e6);
        _creditPnl(user1, 100e6, keccak256("ref1"));

        vm.expectEmit(true, false, false, true);
        emit UnifiedAccountVault.PnLWithdrawn(user1, 50e6);
        vm.prank(user1);
        vault.withdrawPnL(50e6);
    }

    function test_withdrawPnL_revertsZero() public {
        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.ZeroAmount.selector);
        vault.withdrawPnL(0);
    }

    // ═══════════════════════ CreditPnL ═══════════════════════

    function test_creditPnl_emitsEvent() public {
        _brokerDeposit(5000e6);
        bytes32 refId = keccak256("ref-emit");

        vm.expectEmit(true, false, true, true);
        emit UnifiedAccountVault.PnLCredited(user1, 100e6, refId);
        _creditPnl(user1, 100e6, refId);
    }

    function test_creditPnl_idempotent() public {
        _brokerDeposit(5000e6);
        bytes32 refId = keccak256("dup-ref");
        _creditPnl(user1, 100e6, refId);

        // Second call with same refId should revert
        vm.prank(settlementRole);
        vm.expectRevert(UnifiedAccountVault.DuplicateRefId.selector);
        vault.creditPnl(user1, 100e6, refId);

        // Balance should only reflect one credit
        assertEq(vault.pnl(user1), 100e6);
    }

    function test_creditPnl_revertsInsufficientBrokerPool() public {
        _brokerDeposit(50e6);
        vm.prank(settlementRole);
        vm.expectRevert(UnifiedAccountVault.InsufficientBrokerPool.selector);
        vault.creditPnl(user1, 100e6, keccak256("ref"));
    }

    function test_creditPnl_revertsZero() public {
        _brokerDeposit(5000e6);
        vm.prank(settlementRole);
        vm.expectRevert(UnifiedAccountVault.ZeroAmount.selector);
        vault.creditPnl(user1, 0, keccak256("ref"));
    }

    // ═══════════════════════ SeizeCollateral ═══════════════════════

    function test_seizeCollateral_emitsEvent() public {
        _depositCollateral(user1, 1000e6);
        bytes32 refId = keccak256("seize_event");
        vm.expectEmit(true, false, true, true);
        emit UnifiedAccountVault.CollateralSeized(user1, 300e6, refId);
        _seize(user1, 300e6, refId);
    }

    function test_seizeCollateral_revertsExceedsCollateral() public {
        _depositCollateral(user1, 100e6);
        vm.prank(settlementRole);
        vm.expectRevert(UnifiedAccountVault.InsufficientBalance.selector);
        vault.seizeCollateral(user1, 200e6, keccak256("exceed"));
    }

    function test_seizeCollateral_revertsZero() public {
        vm.prank(settlementRole);
        vm.expectRevert(UnifiedAccountVault.ZeroAmount.selector);
        vault.seizeCollateral(user1, 0, keccak256("zero"));
    }

    function test_seizeCollateral_idempotent() public {
        _depositCollateral(user1, 1000e6);
        bytes32 refId = keccak256("duplicate_seize");
        
        _seize(user1, 200e6, refId);
        assertEq(vault.collateral(user1), 800e6);
        
        // Attempt to seize again with same refId should revert
        vm.prank(settlementRole);
        vm.expectRevert(UnifiedAccountVault.DuplicateRefId.selector);
        vault.seizeCollateral(user1, 200e6, refId);
        
        // Collateral should remain unchanged
        assertEq(vault.collateral(user1), 800e6);
    }

    // ═══════════════════════ Broker Deposit / Withdraw ═══════════════════════

    function test_brokerDeposit() public {
        _brokerDeposit(5000e6);
        assertEq(vault.brokerPool(), 5000e6);
        assertEq(usdc.balanceOf(address(vault)), 5000e6);
    }

    function test_brokerDeposit_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit UnifiedAccountVault.BrokerDeposited(5000e6);
        _brokerDeposit(5000e6);
    }

    function test_brokerWithdraw() public {
        _brokerDeposit(5000e6);
        vm.prank(brokerRole);
        vault.brokerWithdraw(2000e6);
        assertEq(vault.brokerPool(), 3000e6);
    }

    function test_brokerWithdraw_emitsEvent() public {
        _brokerDeposit(5000e6);
        vm.expectEmit(false, false, false, true);
        emit UnifiedAccountVault.BrokerWithdrawn(2000e6);
        vm.prank(brokerRole);
        vault.brokerWithdraw(2000e6);
    }

    function test_brokerWithdraw_revertsInsufficientPool() public {
        _brokerDeposit(100e6);
        vm.prank(brokerRole);
        vm.expectRevert(UnifiedAccountVault.InsufficientBrokerPool.selector);
        vault.brokerWithdraw(200e6);
    }

    // ═══════════════════════ Access Control ═══════════════════════

    function test_onlySettlement_creditPnl() public {
        _brokerDeposit(5000e6);
        vm.prank(nobody);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.creditPnl(user1, 100e6, keccak256("ref"));
    }

    function test_onlySettlement_seizeCollateral() public {
        _depositCollateral(user1, 1000e6);
        vm.prank(nobody);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.seizeCollateral(user1, 100e6, keccak256("unauth"));
    }

    function test_onlyBroker_brokerDeposit() public {
        usdc.mint(nobody, 1000e6);
        vm.startPrank(nobody);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.brokerDeposit(1000e6);
        vm.stopPrank();
    }

    function test_onlyBroker_brokerWithdraw() public {
        _brokerDeposit(1000e6);
        vm.prank(nobody);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.brokerWithdraw(100e6);
    }

    function test_onlyAdmin_pause() public {
        vm.prank(nobody);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.pause();
    }

    function test_onlyAdmin_unpause() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(nobody);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.unpause();
    }

    function test_onlyAdmin_setCaps() public {
        vm.prank(nobody);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.setPerUserDailyCap(1000e6);

        vm.prank(nobody);
        vm.expectRevert(UnifiedAccountVault.Unauthorized.selector);
        vault.setGlobalDailyCap(10_000e6);
    }

    // ═══════════════════════ Pause ═══════════════════════

    function test_pause_blocksDeposit() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.depositCollateral(100e6);
    }

    function test_pause_blocksWithdrawCollateral() public {
        _depositCollateral(user1, 1000e6);
        vm.prank(admin);
        vault.pause();
        vm.prank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.withdrawCollateral(100e6);
    }

    function test_pause_blocksWithdrawPnL() public {
        _brokerDeposit(5000e6);
        _creditPnl(user1, 100e6, keccak256("ref"));
        vm.prank(admin);
        vault.pause();
        vm.prank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.withdrawPnL(50e6);
    }

    function test_pause_blocksCreditPnl() public {
        _brokerDeposit(5000e6);
        vm.prank(admin);
        vault.pause();
        vm.prank(settlementRole);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.creditPnl(user1, 100e6, keccak256("ref"));
    }

    function test_pause_blocksSeize() public {
        _depositCollateral(user1, 1000e6);
        vm.prank(admin);
        vault.pause();
        vm.prank(settlementRole);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.seizeCollateral(user1, 100e6, keccak256("pause_seize"));
    }

    function test_pause_blocksBrokerDeposit() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(brokerRole);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.brokerDeposit(100e6);
    }

    function test_pause_blocksBrokerWithdraw() public {
        _brokerDeposit(1000e6);
        vm.prank(admin);
        vault.pause();
        vm.prank(brokerRole);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.brokerWithdraw(100e6);
    }

    function test_unpause_resumesOperations() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(admin);
        vault.unpause();

        // Should work again
        _depositCollateral(user1, 100e6);
        assertEq(vault.collateral(user1), 100e6);
    }

    // ═══════════════════════ Per-User Daily Cap ═══════════════════════

    function test_perUserDailyCap_enforced() public {
        vm.prank(admin);
        vault.setPerUserDailyCap(500e6);

        _depositCollateral(user1, 5000e6);

        vm.prank(user1);
        vault.withdrawCollateral(300e6);

        vm.prank(user1);
        vault.withdrawCollateral(200e6); // total 500 = cap

        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.ExceedsUserDailyCap.selector);
        vault.withdrawCollateral(1e6); // over cap
    }

    function test_perUserDailyCap_resetsNextDay() public {
        vm.prank(admin);
        vault.setPerUserDailyCap(500e6);

        _depositCollateral(user1, 5000e6);

        vm.prank(user1);
        vault.withdrawCollateral(500e6); // hit cap

        // Warp to next day
        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vault.withdrawCollateral(500e6); // should work again
        assertEq(vault.collateral(user1), 4000e6);
    }

    function test_perUserDailyCap_perUser() public {
        vm.prank(admin);
        vault.setPerUserDailyCap(500e6);

        _depositCollateral(user1, 5000e6);
        _depositCollateral(user2, 5000e6);

        vm.prank(user1);
        vault.withdrawCollateral(500e6); // user1 at cap

        // user2 should still be able to withdraw
        vm.prank(user2);
        vault.withdrawCollateral(500e6);
    }

    function test_perUserDailyCap_appliesToPnLWithdraw() public {
        vm.prank(admin);
        vault.setPerUserDailyCap(500e6);

        _brokerDeposit(10_000e6);
        _creditPnl(user1, 1000e6, keccak256("ref1"));

        vm.prank(user1);
        vault.withdrawPnL(500e6); // hit cap

        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.ExceedsUserDailyCap.selector);
        vault.withdrawPnL(1e6);
    }

    function test_perUserDailyCap_combinedCollateralAndPnl() public {
        vm.prank(admin);
        vault.setPerUserDailyCap(500e6);

        _depositCollateral(user1, 5000e6);
        _brokerDeposit(10_000e6);
        _creditPnl(user1, 1000e6, keccak256("ref1"));

        vm.prank(user1);
        vault.withdrawCollateral(300e6);

        vm.prank(user1);
        vault.withdrawPnL(200e6); // total 500 = cap

        vm.prank(user1);
        vm.expectRevert(UnifiedAccountVault.ExceedsUserDailyCap.selector);
        vault.withdrawCollateral(1e6);
    }

    // ═══════════════════════ Global Daily Cap ═══════════════════════

    function test_globalDailyCap_enforced() public {
        vm.prank(admin);
        vault.setGlobalDailyCap(1000e6);

        _depositCollateral(user1, 5000e6);
        _depositCollateral(user2, 5000e6);

        vm.prank(user1);
        vault.withdrawCollateral(600e6);

        vm.prank(user2);
        vault.withdrawCollateral(400e6); // total 1000 = global cap

        vm.prank(user2);
        vm.expectRevert(UnifiedAccountVault.ExceedsGlobalDailyCap.selector);
        vault.withdrawCollateral(1e6);
    }

    function test_globalDailyCap_resetsNextDay() public {
        vm.prank(admin);
        vault.setGlobalDailyCap(1000e6);

        _depositCollateral(user1, 5000e6);

        vm.prank(user1);
        vault.withdrawCollateral(1000e6); // hit global cap

        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vault.withdrawCollateral(500e6); // should work
    }

    // ═══════════════════════ Invariant: Seize Cannot Touch PnL ═══════════════════════

    function test_invariant_seizeOnlyTouchesCollateral() public {
        _depositCollateral(user1, 1000e6);
        _brokerDeposit(5000e6);
        _creditPnl(user1, 200e6, keccak256("ref1"));

        uint256 pnlBefore = vault.pnl(user1);
        _seize(user1, 300e6, keccak256("seize2"));

        assertEq(vault.pnl(user1), pnlBefore, "PnL must not change on seize");
        assertEq(vault.collateral(user1), 700e6);
    }

    // ═══════════════════════ Invariant: Credit Cannot Touch Collateral ═══════════════════════

    function test_invariant_creditOnlyTouchesPnl() public {
        _depositCollateral(user1, 1000e6);
        _brokerDeposit(5000e6);

        uint256 collateralBefore = vault.collateral(user1);
        _creditPnl(user1, 200e6, keccak256("ref1"));

        assertEq(vault.collateral(user1), collateralBefore, "Collateral must not change on credit");
        assertEq(vault.pnl(user1), 200e6);
    }

    // ═══════════════════════ Invariant: USDC Balance == Sum of Ledgers ═══════════════════════

    function test_invariant_balanceEqualsLedgers() public {
        // Complex sequence of operations
        _depositCollateral(user1, 3000e6);
        _depositCollateral(user2, 2000e6);
        _brokerDeposit(10_000e6);

        _creditPnl(user1, 500e6, keccak256("ref1"));
        _creditPnl(user2, 300e6, keccak256("ref2"));
        _seize(user1, 200e6, keccak256("seize3"));

        vm.prank(user1);
        vault.withdrawPnL(100e6);
        vm.prank(user2);
        vault.withdrawCollateral(500e6);

        // Sum all sub-ledgers
        uint256 totalLedger = vault.collateral(user1)
            + vault.collateral(user2)
            + vault.pnl(user1)
            + vault.pnl(user2)
            + vault.brokerPool();

        assertEq(
            usdc.balanceOf(address(vault)),
            totalLedger,
            "USDC balance must equal sum of all sub-ledgers"
        );
    }

    // ═══════════════════════ Role Management ═══════════════════════

    function test_admin_canChangeRoles() public {
        address newSettlement = makeAddr("newSettlement");
        address newBroker = makeAddr("newBroker");
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(admin);
        vault.setSettlement(newSettlement);
        vault.setBroker(newBroker);
        vault.setAdmin(newAdmin);
        vm.stopPrank();

        assertEq(vault.settlement(), newSettlement);
        assertEq(vault.broker(), newBroker);
        assertEq(vault.admin(), newAdmin);
    }

    // ═══════════════════════ Edge: Multiple Users ═══════════════════════

    function test_multipleUsers_independentBalances() public {
        _depositCollateral(user1, 1000e6);
        _depositCollateral(user2, 2000e6);

        assertEq(vault.collateral(user1), 1000e6);
        assertEq(vault.collateral(user2), 2000e6);

        _brokerDeposit(5000e6);
        _creditPnl(user1, 100e6, keccak256("ref1"));
        _creditPnl(user2, 200e6, keccak256("ref2"));

        assertEq(vault.pnl(user1), 100e6);
        assertEq(vault.pnl(user2), 200e6);
    }

    // ═══════════════════════ Edge: Withdraw Exact Balance ═══════════════════════

    function test_withdrawExactCollateral() public {
        _depositCollateral(user1, 1000e6);
        vm.prank(user1);
        vault.withdrawCollateral(1000e6);
        assertEq(vault.collateral(user1), 0);
    }

    function test_withdrawExactPnL() public {
        _brokerDeposit(5000e6);
        _creditPnl(user1, 500e6, keccak256("ref1"));
        vm.prank(user1);
        vault.withdrawPnL(500e6);
        assertEq(vault.pnl(user1), 0);
    }

    // ═══════════════════════ Cap = 0 means unlimited ═══════════════════════

    function test_zeroCap_meansUnlimited() public {
        // Default caps are 0
        assertEq(vault.perUserDailyCap(), 0);
        assertEq(vault.globalDailyCap(), 0);

        _depositCollateral(user1, 50_000e6);
        // Should be able to withdraw full amount with no cap
        vm.prank(user1);
        vault.withdrawCollateral(50_000e6);
        assertEq(vault.collateral(user1), 0);
    }
}
