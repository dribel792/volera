// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/UnifiedAccountVault.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address settlementAddr = vm.envAddress("SETTLEMENT_ADDRESS");
        address brokerAddr = vm.envAddress("BROKER_ADDRESS");

        vm.startBroadcast();

        // 1. Deploy MockUSDC
        MockUSDC mockUsdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUsdc));

        // 2. Deploy UnifiedAccountVault
        UnifiedAccountVault vault = new UnifiedAccountVault(
            address(mockUsdc),
            admin,
            settlementAddr,
            brokerAddr
        );
        console.log("UnifiedAccountVault deployed at:", address(vault));

        // 3. Mint test USDC to broker (1,000,000 USDC)
        mockUsdc.mint(brokerAddr, 1_000_000e6);
        console.log("Minted 1M USDC to broker");

        // 4. Mint test USDC to admin (for testing)
        mockUsdc.mint(admin, 100_000e6);
        console.log("Minted 100K USDC to admin");

        vm.stopBroadcast();
    }
}
