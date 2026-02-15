// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";
import "../src/AnduinSecurity.sol";
import "../src/SecurityTokenVault.sol";

contract SecurityTokenVaultTest is Test {
    MockUSDC usdc;
    SecurityTokenVault vault;
    AnduinSecurity aaplToken;

    address admin = makeAddr("admin");
    address settlementRole = makeAddr("settlement");
    address minterRole = makeAddr("minter");
    address treasury = makeAddr("treasury");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address nobody = makeAddr("nobody");

    uint256 constant INITIAL_USDC = 100_000e6;
    bytes32 constant AAPL_ID = keccak256("AAPL");

    function setUp() public {
        usdc = new MockUSDC();
        vault = new SecurityTokenVault(
            address(usdc),
            admin,
            settlementRole,
            minterRole,
            treasury
        );

        // Deploy security token with proper constructor args
        aaplToken = new AnduinSecurity(
            "Anduin Apple",      // tokenName
            "vAAPL",             // tokenSymbol
            "AAPL",              // securitySymbol
            "Apple Inc.",        // securityName
            "US0378331005",      // isin
            admin,               // issuer
            admin,               // admin role
            address(vault),      // minter — vault needs mint/burn
            8                    // decimals
        );

        // Register token in vault
        vm.prank(admin);
        vault.registerSecurityToken(
            address(aaplToken),
            AAPL_ID,
            1e8,        // minOrderSize: 1 token
            1000e8,     // maxOrderSize: 1000 tokens
            10_000e8    // dailyMintLimit
        );

        // Fund actors
        usdc.mint(user1, INITIAL_USDC);
        usdc.mint(user2, INITIAL_USDC);
        usdc.mint(treasury, INITIAL_USDC);

        // Approvals
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(treasury);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════ BUY FLOW ═══════════════════════

    function test_initiateBuy() public {
        bytes32 refId = keccak256("buy1");

        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 10e8, 1500e6, refId);

        // USDC moved to escrow
        assertEq(usdc.balanceOf(user1), INITIAL_USDC - 1500e6);
        assertEq(vault.escrowBalance(), 1500e6);
    }

    function test_executeBuy() public {
        bytes32 refId = keccak256("buy2");

        // Initiate
        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, refId);

        // Execute at lower actual price → refund excess
        vm.prank(settlementRole);
        vault.executeBuy(refId, 700e6);

        // User got tokens
        assertEq(aaplToken.balanceOf(user1), 5e8);
        // User refunded 50 USDC
        assertEq(usdc.balanceOf(user1), INITIAL_USDC - 700e6);
        // Treasury got payment
        assertEq(usdc.balanceOf(treasury), INITIAL_USDC + 700e6);
        // Escrow cleared
        assertEq(vault.escrowBalance(), 0);
    }

    function test_executeBuy_revertsDoubleExecute() public {
        bytes32 refId = keccak256("buy_dup");

        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, refId);

        vm.prank(settlementRole);
        vault.executeBuy(refId, 700e6);

        vm.prank(settlementRole);
        vm.expectRevert(SecurityTokenVault.SettlementAlreadyExecuted.selector);
        vault.executeBuy(refId, 700e6);
    }

    function test_initiateBuy_revertsDuplicateRefId() public {
        bytes32 refId = keccak256("dup_ref");

        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, refId);

        vm.prank(user2);
        vm.expectRevert(SecurityTokenVault.DuplicateRefId.selector);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, refId);
    }

    function test_initiateBuy_revertsTokenNotRegistered() public {
        address fakeToken = makeAddr("fake");

        vm.prank(user1);
        vm.expectRevert(SecurityTokenVault.TokenNotRegistered.selector);
        vault.initiateBuy(fakeToken, 5e8, 750e6, keccak256("fake"));
    }

    function test_initiateBuy_revertsTokenDisabled() public {
        vm.prank(admin);
        vault.setSecurityTokenEnabled(address(aaplToken), false);

        vm.prank(user1);
        vm.expectRevert(SecurityTokenVault.TokenDisabled.selector);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, keccak256("disabled"));
    }

    function test_initiateBuy_revertsOrderTooSmall() public {
        vm.prank(user1);
        vm.expectRevert(SecurityTokenVault.OrderTooSmall.selector);
        vault.initiateBuy(address(aaplToken), 0.5e8, 100e6, keccak256("small"));
    }

    function test_initiateBuy_revertsOrderTooLarge() public {
        usdc.mint(user1, 1_000_000e6); // need more USDC
        vm.prank(user1);
        vm.expectRevert(SecurityTokenVault.OrderTooLarge.selector);
        vault.initiateBuy(address(aaplToken), 1001e8, 200_000e6, keccak256("large"));
    }

    // ═══════════════════════ SELL FLOW ═══════════════════════

    function test_initiateSell() public {
        // Give user tokens first via tokenize
        bytes32 tokRefId = keccak256("give_tokens");
        vm.prank(settlementRole);
        vault.executeTokenize(user1, address(aaplToken), 10e8, tokRefId);

        // Approve vault to take tokens
        vm.prank(user1);
        aaplToken.approve(address(vault), type(uint256).max);

        bytes32 refId = keccak256("sell1");
        vm.prank(user1);
        vault.initiateSell(address(aaplToken), 5e8, 700e6, refId);

        // Tokens locked in vault
        assertEq(aaplToken.balanceOf(user1), 5e8);
        assertEq(aaplToken.balanceOf(address(vault)), 5e8);
    }

    function test_executeSell() public {
        // Give user tokens
        vm.prank(settlementRole);
        vault.executeTokenize(user1, address(aaplToken), 10e8, keccak256("give"));

        vm.prank(user1);
        aaplToken.approve(address(vault), type(uint256).max);

        bytes32 refId = keccak256("sell2");
        vm.prank(user1);
        vault.initiateSell(address(aaplToken), 5e8, 700e6, refId);

        uint256 actualPrice = 750e6;
        vm.prank(settlementRole);
        vault.executeSell(refId, actualPrice);

        // User got USDC
        assertEq(usdc.balanceOf(user1), INITIAL_USDC + actualPrice);
        // Treasury paid
        assertEq(usdc.balanceOf(treasury), INITIAL_USDC - actualPrice);
        // Tokens burned (vault balance = 0)
        assertEq(aaplToken.balanceOf(address(vault)), 0);
    }

    // ═══════════════════════ TOKENIZE FLOW ═══════════════════════

    function test_executeTokenize() public {
        bytes32 refId = keccak256("tokenize1");

        vm.prank(settlementRole);
        vault.executeTokenize(user1, address(aaplToken), 10e8, refId);

        assertEq(aaplToken.balanceOf(user1), 10e8);
        // No USDC movement
        assertEq(usdc.balanceOf(user1), INITIAL_USDC);
    }

    function test_executeTokenize_revertsDuplicate() public {
        bytes32 refId = keccak256("tok_dup");

        vm.prank(settlementRole);
        vault.executeTokenize(user1, address(aaplToken), 10e8, refId);

        vm.prank(settlementRole);
        vm.expectRevert(SecurityTokenVault.DuplicateRefId.selector);
        vault.executeTokenize(user1, address(aaplToken), 10e8, refId);
    }

    function test_executeTokenize_dailyMintLimit() public {
        // Mint in chunks up to daily limit (maxOrderSize = 1000e8)
        for (uint i = 0; i < 10; i++) {
            vm.prank(settlementRole);
            vault.executeTokenize(user1, address(aaplToken), 1000e8, keccak256(abi.encodePacked("chunk", i)));
        }

        // Next one should fail — daily limit (10_000e8) reached
        vm.prank(settlementRole);
        vm.expectRevert(SecurityTokenVault.DailyMintLimitExceeded.selector);
        vault.executeTokenize(user1, address(aaplToken), 1e8, keccak256("over"));
    }

    // ═══════════════════════ DETOKENIZE FLOW ═══════════════════════

    function test_executeDetokenize() public {
        // Give tokens first
        vm.prank(settlementRole);
        vault.executeTokenize(user1, address(aaplToken), 10e8, keccak256("give2"));

        // User approves vault
        vm.prank(user1);
        aaplToken.approve(address(vault), type(uint256).max);

        bytes32 refId = keccak256("detok1");
        vm.prank(settlementRole);
        vault.executeDetokenize(user1, address(aaplToken), 5e8, refId);

        assertEq(aaplToken.balanceOf(user1), 5e8);
        // No USDC movement
        assertEq(usdc.balanceOf(user1), INITIAL_USDC);
    }

    // ═══════════════════════ CANCEL ═══════════════════════

    function test_cancelBuy_refundsUsdc() public {
        bytes32 refId = keccak256("cancel_buy");

        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 10e8, 1500e6, refId);
        assertEq(usdc.balanceOf(user1), INITIAL_USDC - 1500e6);

        vm.prank(settlementRole);
        vault.cancelSettlement(refId, "Market closed");

        assertEq(usdc.balanceOf(user1), INITIAL_USDC);
        assertEq(vault.escrowBalance(), 0);
    }

    function test_cancelSell_refundsTokens() public {
        // Give tokens
        vm.prank(settlementRole);
        vault.executeTokenize(user1, address(aaplToken), 10e8, keccak256("give3"));

        vm.prank(user1);
        aaplToken.approve(address(vault), type(uint256).max);

        bytes32 refId = keccak256("cancel_sell");
        vm.prank(user1);
        vault.initiateSell(address(aaplToken), 5e8, 700e6, refId);
        assertEq(aaplToken.balanceOf(user1), 5e8);

        vm.prank(settlementRole);
        vault.cancelSettlement(refId, "Price moved");

        assertEq(aaplToken.balanceOf(user1), 10e8);
    }

    // ═══════════════════════ ACCESS CONTROL ═══════════════════════

    function test_onlySettlement_executeBuy() public {
        bytes32 refId = keccak256("auth_buy");
        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, refId);

        vm.prank(nobody);
        vm.expectRevert(SecurityTokenVault.Unauthorized.selector);
        vault.executeBuy(refId, 700e6);
    }

    function test_onlySettlement_executeTokenize() public {
        vm.prank(nobody);
        vm.expectRevert(SecurityTokenVault.Unauthorized.selector);
        vault.executeTokenize(user1, address(aaplToken), 10e8, keccak256("auth_tok"));
    }

    function test_onlySettlement_cancelSettlement() public {
        bytes32 refId = keccak256("auth_cancel");
        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, refId);

        vm.prank(nobody);
        vm.expectRevert(SecurityTokenVault.Unauthorized.selector);
        vault.cancelSettlement(refId, "nope");
    }

    function test_onlyAdmin_registerToken() public {
        vm.prank(nobody);
        vm.expectRevert(SecurityTokenVault.Unauthorized.selector);
        vault.registerSecurityToken(address(aaplToken), keccak256("X"), 1, 100, 1000);
    }

    function test_onlyAdmin_pause() public {
        vm.prank(nobody);
        vm.expectRevert();
        vault.pause();
    }

    // ═══════════════════════ PAUSE ═══════════════════════

    function test_pause_blocksInitiateBuy() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(user1);
        vm.expectRevert();
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, keccak256("paused"));
    }

    function test_pause_blocksExecute() public {
        bytes32 refId = keccak256("pause_exec");
        vm.prank(user1);
        vault.initiateBuy(address(aaplToken), 5e8, 750e6, refId);

        vm.prank(admin);
        vault.pause();

        vm.prank(settlementRole);
        vm.expectRevert();
        vault.executeBuy(refId, 700e6);
    }
}
