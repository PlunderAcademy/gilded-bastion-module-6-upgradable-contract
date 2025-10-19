// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TrainingRegistryV1} from "../src/TrainingRegistryV1.sol";
import {TrainingRegistryV2} from "../src/TrainingRegistryV2.sol";

contract Upgrade is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        
        console2.log("=== Upgrading to TrainingRegistry V2 ===");
        console2.log("Proxy Address:", proxyAddress);
        console2.log("Deployer:", vm.addr(deployerPrivateKey));
        
        // Cast proxy to V1 for upgrade call
        TrainingRegistryV1 registryV1 = TrainingRegistryV1(proxyAddress);
        
        // Verify current state before upgrade
        console2.log("\nPre-upgrade state:");
        address owner = registryV1.owner();
        address claimant = registryV1.claimant();
        console2.log("Owner:", owner);
        console2.log("Claimant:", claimant);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy V2 implementation
        console2.log("\n1. Deploying V2 implementation...");
        TrainingRegistryV2 implementationV2 = new TrainingRegistryV2();
        console2.log("V2 Implementation:", address(implementationV2));
        
        // 2. Upgrade proxy to V2
        console2.log("\n2. Upgrading proxy...");
        registryV1.upgradeToAndCall(address(implementationV2), "");
        console2.log("Proxy upgraded!");
        
        vm.stopBroadcast();
        
        // 3. Verify upgrade
        console2.log("\n3. Verifying upgrade...");
        TrainingRegistryV2 registryV2 = TrainingRegistryV2(proxyAddress);
        
        // Check V1 state preserved
        address newOwner = registryV2.owner();
        address newClaimant = registryV2.claimant();
        
        require(newOwner == owner, "Owner changed!");
        require(newClaimant == claimant, "Claimant changed!");
        
        console2.log("Owner (preserved):", newOwner);
        console2.log("Claimant (preserved):", newClaimant);
        
        // Check V2 features available
        uint256 batchCount = registryV2.batchSubmissionCount();
        console2.log("Batch submission count:", batchCount);
        
        console2.log("\n=== Upgrade Successful! ===");
        console2.log("V2 Implementation:", address(implementationV2));
        console2.log("Proxy (unchanged):", proxyAddress);
        console2.log("\nNew features:");
        console2.log("- submitVoucherBatch() for gas savings");
        console2.log("- batchSubmissionCount tracking");
    }
}
