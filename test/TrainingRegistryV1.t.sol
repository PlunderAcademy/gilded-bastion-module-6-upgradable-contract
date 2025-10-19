// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TrainingRegistryV1} from "../src/TrainingRegistryV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract TrainingRegistryV1Test is Test {
    using MessageHashUtils for bytes32;

    TrainingRegistryV1 public implementation;
    TrainingRegistryV1 public registry;
    ERC1967Proxy public proxy;
    
    address public owner;
    address public issuer;
    uint256 public issuerPk;
    address public learner;
    address public claimant;

    string private constant EIP712_NAME = "TrainingCert";
    string private constant EIP712_VERSION = "1";
    string private constant BASE_URI = "https://static.plunderswap.com/training/";

    bytes32 private constant VOUCHER_TYPEHASH = keccak256(
        "CompletionVoucher(uint256 taskCode,address wallet)"
    );

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        (issuer, issuerPk) = makeAddrAndKey("ISSUER");
        learner = address(0xBEEF);
        claimant = address(0xC1A1);

        // Deploy implementation
        implementation = new TrainingRegistryV1();
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            TrainingRegistryV1.initialize.selector,
            owner,
            BASE_URI,
            EIP712_NAME,
            EIP712_VERSION,
            claimant
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        registry = TrainingRegistryV1(address(proxy));

        // Set up issuer
        registry.setIssuer(issuer, true);
    }

    // ============ DEPLOYMENT TESTS ============

    function testInitialization() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.claimant(), claimant);
        assertEq(registry.uriPadDigits(), 4);
        assertEq(registry.uri(1), string(abi.encodePacked(BASE_URI, "0001.json")));
    }

    function testInitializeRevertsOnZeroClaimant() public {
        TrainingRegistryV1 newImpl = new TrainingRegistryV1();
        
        bytes memory initData = abi.encodeWithSelector(
            TrainingRegistryV1.initialize.selector,
            owner,
            BASE_URI,
            EIP712_NAME,
            EIP712_VERSION,
            address(0)  // Zero claimant
        );
        
        vm.expectRevert("Invalid claimant address");
        new ERC1967Proxy(address(newImpl), initData);
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        registry.initialize(owner, BASE_URI, EIP712_NAME, EIP712_VERSION, claimant);
    }

    function testImplementationCannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(owner, BASE_URI, EIP712_NAME, EIP712_VERSION, claimant);
    }

    // ============ VOUCHER SUBMISSION TESTS ============

    function testSubmitVoucherSucceeds() public {
        uint256 taskCode = 1;
        bytes memory sig = _signVoucher(taskCode, learner);

        vm.prank(learner);
        registry.submitVoucher(taskCode, sig);

        assertTrue(registry.completed(learner, taskCode));
        assertEq(registry.balanceOf(learner, taskCode), 1);
        assertTrue(registry.hasAchievement(learner, taskCode));
    }

    function testSubmitVoucherEmitsEvent() public {
        uint256 taskCode = 5;
        bytes memory sig = _signVoucher(taskCode, learner);

        vm.expectEmit(true, true, false, true);
        emit TrainingRegistryV1.TaskCompleted(taskCode, learner);

        vm.prank(learner);
        registry.submitVoucher(taskCode, sig);
    }

    function testSubmitVoucherRevertsOnInvalidIssuer() public {
        (, uint256 badPk) = makeAddrAndKey("BAD");
        uint256 taskCode = 1;
        bytes memory sig = _signVoucherWith(badPk, taskCode, learner);

        vm.prank(learner);
        vm.expectRevert("invalid issuer");
        registry.submitVoucher(taskCode, sig);
    }

    function testSubmitVoucherRevertsOnWalletMismatch() public {
        uint256 taskCode = 1;
        bytes memory sig = _signVoucher(taskCode, learner);

        // Different sender than signed wallet
        vm.prank(address(0xCAFE));
        vm.expectRevert("invalid issuer");
        registry.submitVoucher(taskCode, sig);
    }

    function testSubmitVoucherRevertsOnDoubleSubmit() public {
        uint256 taskCode = 1;
        bytes memory sig = _signVoucher(taskCode, learner);

        vm.prank(learner);
        registry.submitVoucher(taskCode, sig);

        // Try again
        bytes memory sig2 = _signVoucher(taskCode, learner);
        vm.prank(learner);
        vm.expectRevert("already completed");
        registry.submitVoucher(taskCode, sig2);
    }

    function testMultipleTasksSameUser() public {
        vm.startPrank(learner);
        
        for (uint256 i = 1; i <= 5; i++) {
            bytes memory sig = _signVoucher(i, learner);
            registry.submitVoucher(i, sig);
        }
        
        vm.stopPrank();

        uint256[] memory achievements = registry.getWalletAchievements(learner);
        assertEq(achievements.length, 5);
        
        for (uint256 i = 1; i <= 5; i++) {
            assertTrue(registry.completed(learner, i));
            assertTrue(registry.hasAchievement(learner, i));
        }
    }

    // ============ SOULBOUND TESTS ============

    function testTransferReverts() public {
        uint256 taskCode = 1;
        bytes memory sig = _signVoucher(taskCode, learner);

        vm.prank(learner);
        registry.submitVoucher(taskCode, sig);

        // Try to transfer
        vm.prank(learner);
        vm.expectRevert("SBT: non-transferable");
        registry.safeTransferFrom(learner, address(0x1234), taskCode, 1, "");
    }

    function testBatchTransferReverts() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        // Mint both
        vm.startPrank(learner);
        registry.submitVoucher(1, _signVoucher(1, learner));
        registry.submitVoucher(2, _signVoucher(2, learner));
        vm.stopPrank();

        // Try batch transfer
        vm.prank(learner);
        vm.expectRevert("SBT: non-transferable");
        registry.safeBatchTransferFrom(learner, address(0x1234), ids, amounts, "");
    }

    // ============ ISSUER MANAGEMENT TESTS ============

    function testSetIssuer() public {
        address newIssuer = address(0x999);
        
        vm.expectEmit(true, false, false, true);
        emit TrainingRegistryV1.IssuerUpdated(newIssuer, true);
        
        registry.setIssuer(newIssuer, true);
        assertTrue(registry.isIssuer(newIssuer));
    }

    function testRemoveIssuer() public {
        registry.setIssuer(issuer, false);
        assertFalse(registry.isIssuer(issuer));
    }

    function testSetIssuerOnlyOwner() public {
        vm.prank(learner);
        vm.expectRevert();
        registry.setIssuer(address(0x999), true);
    }

    // ============ URI TESTS ============

    function testUriPadding() public view {
        assertEq(registry.uri(1), string(abi.encodePacked(BASE_URI, "0001.json")));
        assertEq(registry.uri(50), string(abi.encodePacked(BASE_URI, "0050.json")));
        assertEq(registry.uri(100), string(abi.encodePacked(BASE_URI, "0100.json")));
        assertEq(registry.uri(1000), string(abi.encodePacked(BASE_URI, "1000.json")));
    }

    function testSetBaseURI() public {
        string memory newURI = "https://new-base/";
        
        vm.expectEmit(false, false, false, true);
        emit TrainingRegistryV1.BaseURISet(newURI);
        
        registry.setBaseURI(newURI);
        assertEq(registry.uri(1), string(abi.encodePacked(newURI, "0001.json")));
    }

    function testSetUriPadDigits() public {
        registry.setUriPadDigits(6);
        assertEq(registry.uriPadDigits(), 6);
        assertEq(registry.uri(1), string(abi.encodePacked(BASE_URI, "000001.json")));
    }

    // ============ PAUSE TESTS ============

    function testPauseStopsSubmissions() public {
        registry.pause();
        
        uint256 taskCode = 1;
        bytes memory sig = _signVoucher(taskCode, learner);

        vm.prank(learner);
        vm.expectRevert();
        registry.submitVoucher(taskCode, sig);
    }

    function testUnpauseAllowsSubmissions() public {
        registry.pause();
        registry.unpause();
        
        uint256 taskCode = 1;
        bytes memory sig = _signVoucher(taskCode, learner);

        vm.prank(learner);
        registry.submitVoucher(taskCode, sig);
        
        assertTrue(registry.completed(learner, taskCode));
    }

    function testPauseOnlyOwner() public {
        vm.prank(learner);
        vm.expectRevert();
        registry.pause();
    }

    // ============ OWNERSHIP TESTS ============

    function testTransferOwnership() public {
        address newOwner = address(0x999);
        
        registry.transferOwnership(newOwner);
        assertEq(registry.pendingOwner(), newOwner);
        
        vm.prank(newOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner);
    }

    function testTransferOwnershipOnlyOwner() public {
        vm.prank(learner);
        vm.expectRevert();
        registry.transferOwnership(address(0x999));
    }

    // ============ ACHIEVEMENT TRACKING TESTS ============

    function testGetWalletAchievements() public {
        vm.startPrank(learner);
        
        for (uint256 i = 1; i <= 3; i++) {
            registry.submitVoucher(i, _signVoucher(i, learner));
        }
        
        vm.stopPrank();

        uint256[] memory achievements = registry.getWalletAchievements(learner);
        assertEq(achievements.length, 3);
        assertEq(achievements[0], 1);
        assertEq(achievements[1], 2);
        assertEq(achievements[2], 3);
    }

    function testHasAchievement() public {
        uint256 taskCode = 1;
        bytes memory sig = _signVoucher(taskCode, learner);

        assertFalse(registry.hasAchievement(learner, taskCode));
        
        vm.prank(learner);
        registry.submitVoucher(taskCode, sig);
        
        assertTrue(registry.hasAchievement(learner, taskCode));
    }

    // ============ UPGRADE AUTHORIZATION TESTS ============

    function testUpgradeOnlyOwner() public {
        TrainingRegistryV1 newImpl = new TrainingRegistryV1();
        
        vm.prank(learner);
        vm.expectRevert();
        registry.upgradeToAndCall(address(newImpl), "");
    }

    function testOwnerCanUpgrade() public {
        TrainingRegistryV1 newImpl = new TrainingRegistryV1();
        
        registry.upgradeToAndCall(address(newImpl), "");
        
        // Verify still works
        assertEq(registry.owner(), owner);
        assertEq(registry.claimant(), claimant);
    }

    // ============ HELPER FUNCTIONS ============

    function _signVoucher(uint256 taskCode, address wallet) internal view returns (bytes memory) {
        return _signVoucherWith(issuerPk, taskCode, wallet);
    }

    function _signVoucherWith(uint256 pk, uint256 taskCode, address wallet) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, taskCode, wallet));
        bytes32 domainSeparator = _domainSeparator();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 typehash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        return keccak256(
            abi.encode(
                typehash,
                keccak256(bytes(EIP712_NAME)),
                keccak256(bytes(EIP712_VERSION)),
                block.chainid,
                address(registry)
            )
        );
    }
}
