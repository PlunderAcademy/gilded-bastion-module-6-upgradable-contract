// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TrainingRegistryV2 is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    ERC1155Upgradeable
{
    using ECDSA for bytes32;

    struct CompletionVoucher {
        uint256 taskCode;
        address wallet;
    }

    bytes32 private constant VOUCHER_TYPEHASH = keccak256(
        "CompletionVoucher(uint256 taskCode,address wallet)"
    );

    // ========================================
    // V1 STORAGE (DO NOT MODIFY!)
    // ========================================
    mapping(address => bool) public isIssuer;
    mapping(address => mapping(uint256 => bool)) public completed;
    mapping(address => uint256[]) private _walletTokenIds;
    mapping(address => mapping(uint256 => bool)) private _hasTokenId;
    address public claimant;

    event IssuerUpdated(address indexed issuer, bool allowed);
    event TaskCompleted(uint256 indexed taskCode, address indexed wallet);
    event BatchSubmitted(address indexed wallet, uint256[] taskCodes, uint256 count);  // NEW EVENT
    event BaseURISet(string newBaseURI);
    event UriPadDigitsSet(uint8 newPadDigits);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // NO NEW INITIALIZER - upgrade preserves existing initialization
    // Never add initialize() to V2+, only V1 has it!

    function setIssuer(address issuer, bool allowed) external onlyOwner {
        isIssuer[issuer] = allowed;
        emit IssuerUpdated(issuer, allowed);
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _setURI(newBaseURI);
        _baseDirectoryURI = newBaseURI;
        emit BaseURISet(newBaseURI);
    }

    function setUriPadDigits(uint8 newPad) external onlyOwner {
        uriPadDigits = newPad;
        emit UriPadDigitsSet(newPad);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // V1 function - UNCHANGED
    function submitVoucher(uint256 taskCode, bytes calldata signature) external whenNotPaused {
        require(!completed[msg.sender][taskCode], "already completed");

        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, taskCode, msg.sender));
        bytes32 digest = MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
        address signer = ECDSA.recover(digest, signature);
        require(isIssuer[signer], "invalid issuer");

        completed[msg.sender][taskCode] = true;
        _mint(msg.sender, taskCode, 1, "");
        emit TaskCompleted(taskCode, msg.sender);
    }

    // ========================================
    // V2 NEW FEATURE: BATCH SUBMISSION
    // ========================================
    
    /// @notice Submit multiple vouchers in one transaction
    /// @param taskCodes Array of task codes to claim
    /// @param signatures Array of signatures (one per task)
    function submitVoucherBatch(
        uint256[] calldata taskCodes,
        bytes[] calldata signatures
    ) external whenNotPaused {
        require(taskCodes.length > 0, "empty batch");
        require(taskCodes.length == signatures.length, "length mismatch");
        require(taskCodes.length <= 20, "batch too large");  // Prevent gas limit issues

        uint256 successCount = 0;

        for (uint256 i = 0; i < taskCodes.length; i++) {
            uint256 taskCode = taskCodes[i];
            
            // Skip if already completed (don't revert entire batch)
            if (completed[msg.sender][taskCode]) {
                continue;
            }

            // Verify signature
            bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, taskCode, msg.sender));
            bytes32 digest = MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
            address signer = ECDSA.recover(digest, signatures[i]);
            
            if (!isIssuer[signer]) {
                continue;  // Skip invalid signatures
            }

            // Mark complete and mint
            completed[msg.sender][taskCode] = true;
            _mint(msg.sender, taskCode, 1, "");
            emit TaskCompleted(taskCode, msg.sender);
            successCount++;
        }

        require(successCount > 0, "no valid vouchers");
        
        batchSubmissionCount++;
        emit BatchSubmitted(msg.sender, taskCodes, successCount);
    }

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal override {
        require(from == address(0) || to == address(0), "SBT: non-transferable");
        super._update(from, to, ids, amounts);

        if (to != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenId = ids[i];
                if (!_hasTokenId[to][tokenId] && balanceOf(to, tokenId) > 0) {
                    _hasTokenId[to][tokenId] = true;
                    _walletTokenIds[to].push(tokenId);
                }
            }
        }
        if (from != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenId = ids[i];
                if (_hasTokenId[from][tokenId] && balanceOf(from, tokenId) == 0) {
                    _hasTokenId[from][tokenId] = false;
                    _removeWalletTokenId(from, tokenId);
                }
            }
        }
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(_baseDirectoryURI, _paddedDecimal(tokenId, uriPadDigits), ".json"));
    }

    function _paddedDecimal(uint256 value, uint8 minDigits) internal pure returns (string memory) {
        string memory dec = Strings.toString(value);
        uint256 len = bytes(dec).length;
        if (len >= minDigits) return dec;
        uint256 pad = uint256(minDigits) - len;
        bytes memory zeros = new bytes(pad);
        for (uint256 i = 0; i < pad; i++) zeros[i] = bytes1("0");
        return string(abi.encodePacked(zeros, dec));
    }

    function _removeWalletTokenId(address wallet, uint256 tokenId) internal {
        uint256[] storage list = _walletTokenIds[wallet];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == tokenId) {
                uint256 last = list[list.length - 1];
                list[i] = last;
                list.pop();
                break;
            }
        }
    }

    function getWalletAchievements(address wallet) external view returns (uint256[] memory) {
        return _walletTokenIds[wallet];
    }

    function hasAchievement(address wallet, uint256 tokenId) external view returns (bool) {
        return _hasTokenId[wallet][tokenId];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ========================================
    // STORAGE LAYOUT (matches V1 exactly, then adds V2)
    // ========================================
    string private _baseDirectoryURI;     // Slot 5 (from V1)
    uint8 public uriPadDigits;            // Slot 6 (from V1)
    uint256[37] private __gap;            // Slots 7-43 (reduced from 38)
    uint256 public batchSubmissionCount;  // Slot 44 (NEW in V2)
}
