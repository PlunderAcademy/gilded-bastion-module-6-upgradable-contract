// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TrainingRegistryV1} from "../src/TrainingRegistryV1.sol";
import {TrainingRegistryV2} from "../src/TrainingRegistryV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract UpgradeTest is Test {
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

    function testUpgradePreservesState() public {
        // Create V1 state: submit 3 achievements
        vm.startPrank(learner);
        for (uint256 i = 1; i <= 3; i++) {
            registryV1.submitVoucher(i, _signVoucher(i, learner));
        }
        vm.stopPrank();

        // Verify V1 state
        assertTrue(registryV1.completed(learner, 1));
        assertTrue(registryV1.completed(learner, 2));
        assertTrue(registryV1.completed(learner, 3));
        assertEq(registryV1.balanceOf(learner, 1), 1);
        
        // Record V1 state
        address preOwner = registryV1.owner();
        address preClaimant = registryV1.claimant();
        uint8 prePadDigits = registryV1.uriPadDigits();

        // Upgrade to V2
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        
        // Cast to V2
        registryV2 = TrainingRegistryV2(address(proxy));

        // Verify all V1 state preserved
        assertEq(registryV2.owner(), preOwner);
        assertEq(registryV2.claimant(), preClaimant);
        assertEq(registryV2.uriPadDigits(), prePadDigits);
        
        // Verify achievement data intact
        assertTrue(registryV2.completed(learner, 1));
        assertTrue(registryV2.completed(learner, 2));
        assertTrue(registryV2.completed(learner, 3));
        assertEq(registryV2.balanceOf(learner, 1), 1);
        assertEq(registryV2.balanceOf(learner, 2), 1);
        assertEq(registryV2.balanceOf(learner, 3), 1);

        uint256[] memory achievements = registryV2.getWalletAchievements(learner);
        assertEq(achievements.length, 3);
    }

    function testV2BatchSubmission() public {
        // Upgrade to V2
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        // Prepare batch
        uint256[] memory taskCodes = new uint256[](5);
        bytes[] memory signatures = new bytes[](5);
        
        for (uint256 i = 0; i < 5; i++) {
            taskCodes[i] = i + 1;
            signatures[i] = _signVoucher(i + 1, learner);
        }

        // Submit batch
        vm.prank(learner);
        registryV2.submitVoucherBatch(taskCodes, signatures);

        // Verify all claimed
        for (uint256 i = 1; i <= 5; i++) {
            assertTrue(registryV2.completed(learner, i));
            assertEq(registryV2.balanceOf(learner, i), 1);
        }
        
        assertEq(registryV2.batchSubmissionCount(), 1);
    }

    function testV2BatchSkipsCompleted() public {
        // Upgrade to V2
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        // Submit task 1 individually first
        vm.prank(learner);
        registryV2.submitVoucher(1, _signVoucher(1, learner));

        // Try to batch submit including task 1 again
        uint256[] memory taskCodes = new uint256[](3);
        bytes[] memory signatures = new bytes[](3);
        
        taskCodes[0] = 1;  // Already completed
        taskCodes[1] = 2;  // New
        taskCodes[2] = 3;  // New
        
        signatures[0] = _signVoucher(1, learner);
        signatures[1] = _signVoucher(2, learner);
        signatures[2] = _signVoucher(3, learner);

        // Should succeed, skipping task 1
        vm.prank(learner);
        registryV2.submitVoucherBatch(taskCodes, signatures);

        // Verify: 1 was already there, 2 and 3 added
        assertEq(registryV2.balanceOf(learner, 1), 1);
        assertEq(registryV2.balanceOf(learner, 2), 1);
        assertEq(registryV2.balanceOf(learner, 3), 1);
    }

    function testV2OldFunctionStillWorks() public {
        // Upgrade to V2
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        // Use old V1 function
        vm.prank(learner);
        registryV2.submitVoucher(1, _signVoucher(1, learner));

        assertTrue(registryV2.completed(learner, 1));
    }

    function testV2BatchRevertsOnEmptyArray() public {
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        uint256[] memory taskCodes = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(learner);
        vm.expectRevert("empty batch");
        registryV2.submitVoucherBatch(taskCodes, signatures);
    }

    function testV2BatchRevertsOnLengthMismatch() public {
        implV2 = new TrainingRegistryV2();
        registryV1.upgradeToAndCall(address(implV2), "");
        registryV2 = TrainingRegistryV2(address(proxy));

        uint256[] memory taskCodes = new uint256[](2);
        bytes[] memory signatures = new bytes[](3);  // Mismatch!

        vm.prank(learner);
        vm.expectRevert("length mismatch");
        registryV2.submitVoucherBatch(taskCodes, signatures);
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
