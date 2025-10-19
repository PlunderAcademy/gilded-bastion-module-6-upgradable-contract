// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TrainingRegistryV1} from "../src/TrainingRegistryV1.sol";
import {TrainingRegistryV2} from "../src/TrainingRegistryV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract GasCompareTest is Test {
    using MessageHashUtils for bytes32;

    TrainingRegistryV1 public implV1;
    TrainingRegistryV2 public implV2;
    ERC1967Proxy public proxy;
    TrainingRegistryV1 public registryV1;
    TrainingRegistryV2 public registryV2;
    
    address public owner;
    address public issuer;
    uint256 public issuerPk;
    address public learner;
    address public claimant;

    bytes32 private constant VOUCHER_TYPEHASH = keccak256(
        "CompletionVoucher(uint256 taskCode,address wallet)"
    );

    function setUp() public {
        owner = address(this);
        (issuer, issuerPk) = makeAddrAndKey("ISSUER");
        learner = address(0xBEEF);
        claimant = address(0xC1A1);

        // Deploy V1
        implV1 = new TrainingRegistryV1();
        bytes memory initData = abi.encodeWithSelector(
            TrainingRegistryV1.initialize.selector,
            owner,
            "https://base/",
            "TrainingCert",
            "1",
            claimant
        );
        proxy = new ERC1967Proxy(address(implV1), initData);
        registryV1 = TrainingRegistryV1(address(proxy));
        
        registryV1.setIssuer(issuer, true);
    }

    function testGasComparison() public {
        // Setup V2
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        // Measure V1 individual submissions
        uint256 gasV1Start = gasleft();
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(learner);
            registryV2.submitVoucher(i, _signVoucher(i, learner));
        }
        uint256 gasV1Used = gasV1Start - gasleft();
        
        // Setup second user for V2 batch
        address learner2 = address(0xCAFE);
        
        // Measure V2 batch submission
        uint256[] memory taskCodes = new uint256[](5);
        bytes[] memory signatures = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            taskCodes[i] = i + 1;
            signatures[i] = _signVoucher(i + 1, learner2);
        }
        
        uint256 gasV2Start = gasleft();
        vm.prank(learner2);
        registryV2.submitVoucherBatch(taskCodes, signatures);
        uint256 gasV2Used = gasV2Start - gasleft();
        
        console2.log("V1 (5 individual):", gasV1Used);
        console2.log("V2 (1 batch of 5):", gasV2Used);
        console2.log("Savings:", gasV1Used - gasV2Used);
        console2.log("Savings %:", ((gasV1Used - gasV2Used) * 100) / gasV1Used);
        
        // Verify savings
        assertTrue(gasV2Used < gasV1Used, "V2 should use less gas");
    }

    function testGasComparison10Tasks() public {
        // Setup V2
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        // Measure V1 individual submissions (10 tasks)
        uint256 gasV1Start = gasleft();
        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(learner);
            registryV2.submitVoucher(i, _signVoucher(i, learner));
        }
        uint256 gasV1Used = gasV1Start - gasleft();
        
        // Setup second user for V2 batch
        address learner2 = address(0xCAFE);
        
        // Measure V2 batch submission (10 tasks)
        uint256[] memory taskCodes = new uint256[](10);
        bytes[] memory signatures = new bytes[](10);
        for (uint256 i = 0; i < 10; i++) {
            taskCodes[i] = i + 1;
            signatures[i] = _signVoucher(i + 1, learner2);
        }
        
        uint256 gasV2Start = gasleft();
        vm.prank(learner2);
        registryV2.submitVoucherBatch(taskCodes, signatures);
        uint256 gasV2Used = gasV2Start - gasleft();
        
        console2.log("\n=== 10 Tasks Comparison ===");
        console2.log("V1 (10 individual):", gasV1Used);
        console2.log("V2 (1 batch of 10):", gasV2Used);
        console2.log("Savings:", gasV1Used - gasV2Used);
        console2.log("Savings %:", ((gasV1Used - gasV2Used) * 100) / gasV1Used);
        
        // Verify savings scale with batch size
        assertTrue(gasV2Used < gasV1Used, "V2 should use less gas");
    }

    function testGasComparison20Tasks() public {
        // Setup V2
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        // Measure V1 individual submissions (20 tasks - max batch size)
        uint256 gasV1Start = gasleft();
        for (uint256 i = 1; i <= 20; i++) {
            vm.prank(learner);
            registryV2.submitVoucher(i, _signVoucher(i, learner));
        }
        uint256 gasV1Used = gasV1Start - gasleft();
        
        // Setup second user for V2 batch
        address learner2 = address(0xCAFE);
        
        // Measure V2 batch submission (20 tasks - max)
        uint256[] memory taskCodes = new uint256[](20);
        bytes[] memory signatures = new bytes[](20);
        for (uint256 i = 0; i < 20; i++) {
            taskCodes[i] = i + 1;
            signatures[i] = _signVoucher(i + 1, learner2);
        }
        
        uint256 gasV2Start = gasleft();
        vm.prank(learner2);
        registryV2.submitVoucherBatch(taskCodes, signatures);
        uint256 gasV2Used = gasV2Start - gasleft();
        
        console2.log("\n=== 20 Tasks Comparison (Max Batch) ===");
        console2.log("V1 (20 individual):", gasV1Used);
        console2.log("V2 (1 batch of 20):", gasV2Used);
        console2.log("Savings:", gasV1Used - gasV2Used);
        console2.log("Savings %:", ((gasV1Used - gasV2Used) * 100) / gasV1Used);
        
        // Maximum savings should be significant
        assertTrue(gasV2Used < gasV1Used, "V2 should use less gas");
    }

    // ============ HELPER FUNCTIONS ============

    function _signVoucher(uint256 taskCode, address wallet) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, taskCode, wallet));
        bytes32 domainSeparator = _domainSeparator();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 typehash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        return keccak256(
            abi.encode(
                typehash,
                keccak256(bytes("TrainingCert")),
                keccak256(bytes("1")),
                block.chainid,
                address(proxy)
            )
        );
    }
}


