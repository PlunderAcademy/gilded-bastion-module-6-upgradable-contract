// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TrainingRegistryV1} from "../src/TrainingRegistryV1.sol";

contract Deploy is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address claimantAddress = vm.envAddress("CLAIMANT_ADDRESS");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console2.log("=== TrainingRegistry V1 Deployment ===");
        console2.log("Deployer:", deployerAddress);
        console2.log("Claimant:", claimantAddress);
        console2.log("Chain ID:", block.chainid);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy implementation
        console2.log("\n1. Deploying implementation...");
        TrainingRegistryV1 implementation = new TrainingRegistryV1();
        console2.log("Implementation deployed:", address(implementation));
        
        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            TrainingRegistryV1.initialize.selector,
            deployerAddress,  // initialOwner
            "https://static.plunderswap.com/training/",  // baseURI
            "TrainingCert",   // eip712Name
            "1",              // eip712Version
            claimantAddress   // claimant (your training portal wallet!)
        );
        
        // 3. Deploy proxy
        console2.log("\n2. Deploying proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console2.log("Proxy deployed:", address(proxy));
        
        vm.stopBroadcast();
        
        // 4. Verify deployment
        console2.log("\n3. Verifying deployment...");
        TrainingRegistryV1 registry = TrainingRegistryV1(address(proxy));
        
        address owner = registry.owner();
        address registeredClaimant = registry.claimant();
        uint8 padDigits = registry.uriPadDigits();
        string memory uri1 = registry.uri(1);
        
        console2.log("Owner:", owner);
        console2.log("Claimant:", registeredClaimant);
        console2.log("URI Pad Digits:", padDigits);
        console2.log("Sample URI (token 1):", uri1);
        
        // Validation checks
        require(owner == deployerAddress, "Owner mismatch");
        require(registeredClaimant == claimantAddress, "Claimant mismatch");
        
        console2.log("\n=== Deployment Successful! ===");
        console2.log("Proxy Address:", address(proxy));
        console2.log("Implementation Address:", address(implementation));
        console2.log("\nNext steps:");
        console2.log("1. Fund development wallet with testnet ZIL");
        console2.log("2. Run: forge script script/Deploy.s.sol --rpc-url zilliqaTestnet --broadcast --legacy");
        console2.log("3. Submit deployment transaction to training portal");
        console2.log("4. Verify claimant matches your connected wallet");
    }
}
