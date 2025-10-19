// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TrainingRegistryV1} from "../src/TrainingRegistryV1.sol";

contract Verify is Script {
    function run() external view {
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address expectedClaimant = vm.envAddress("CLAIMANT_ADDRESS");
        
        console2.log("=== Verifying TrainingRegistry V1 ===");
        console2.log("Proxy Address:", proxyAddress);
        console2.log("Expected Claimant:", expectedClaimant);
        
        TrainingRegistryV1 registry = TrainingRegistryV1(proxyAddress);
        
        address owner = registry.owner();
        address claimant = registry.claimant();
        uint8 padDigits = registry.uriPadDigits();
        
        console2.log("\nContract State:");
        console2.log("Owner:", owner);
        console2.log("Claimant:", claimant);
        console2.log("URI Pad Digits:", padDigits);
        
        // Test URI generation
        string memory uri1 = registry.uri(1);
        string memory uri50 = registry.uri(50);
        console2.log("\nURI Examples:");
        console2.log("Token 1:", uri1);
        console2.log("Token 50:", uri50);
        
        // Validation
        if (claimant != expectedClaimant) {
            console2.log("WARNING: Claimant mismatch!");
            console2.log("Expected:", expectedClaimant);
            console2.log("Got:", claimant);
        } else {
            console2.log("Claimant correctly set!");
        }
        
        console2.log("=== Verification Complete ===");
    }
}
