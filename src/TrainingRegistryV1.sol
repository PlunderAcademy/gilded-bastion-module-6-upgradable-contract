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

contract TrainingRegistryV1 is
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

    mapping(address => bool) public isIssuer;
    mapping(address => mapping(uint256 => bool)) public completed;
    mapping(address => uint256[]) private _walletTokenIds;
    mapping(address => mapping(uint256 => bool)) private _hasTokenId;
    
    // Achievement tracking - LINE 1 ADDED
    address public claimant;

    event IssuerUpdated(address indexed issuer, bool allowed);
    event TaskCompleted(uint256 indexed taskCode, address indexed wallet);
    event BaseURISet(string newBaseURI);
    event UriPadDigitsSet(uint8 newPadDigits);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        string memory baseURI,
        string memory eip712Name,
        string memory eip712Version,
        address _claimant  // LINE 2 ADDED
    ) external initializer {
        __ERC1155_init(baseURI);
        __Pausable_init();
        __Ownable2Step_init();
        __EIP712_init(eip712Name, eip712Version);

        _transferOwnership(initialOwner);

        require(_claimant != address(0), "Invalid claimant address");  // LINE 3 ADDED
        claimant = _claimant;  // LINE 4 ADDED

        _baseDirectoryUri = baseURI;
        uriPadDigits = 4;
    }

    function setIssuer(address issuer, bool allowed) external onlyOwner {
        isIssuer[issuer] = allowed;
        emit IssuerUpdated(issuer, allowed);
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _setURI(newBaseURI);
        _baseDirectoryUri = newBaseURI;
        emit BaseURISet(newBaseURI);
    }

    function setUriPadDigits(uint8 newPad) external onlyOwner {
        uriPadDigits = newPad;
        emit UriPadDigitsSet(newPad);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function submitVoucher(uint256 taskCode, bytes calldata signature) external whenNotPaused {
        require(!completed[msg.sender][taskCode], "already completed");

        // using abi.encode instead of inline assembly as its more readable and easier to understand
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, taskCode, msg.sender));
        bytes32 digest = MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
        address signer = ECDSA.recover(digest, signature);
        require(isIssuer[signer], "invalid issuer");

        completed[msg.sender][taskCode] = true;
        _mint(msg.sender, taskCode, 1, "");
        emit TaskCompleted(taskCode, msg.sender);
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
        return string(abi.encodePacked(_baseDirectoryUri, _paddedDecimal(tokenId, uriPadDigits), ".json"));
    }

    function _paddedDecimal(uint256 value, uint8 minDigits) internal pure returns (string memory) {
        string memory dec = Strings.toString(value);
        uint256 len = bytes(dec).length;
        if (len >= minDigits) return dec;
        uint256 pad = uint256(minDigits) - len;
        bytes memory zeros = new bytes(pad);
        for (uint256 i = 0; i < pad; i++) zeros[i] = 0x30;
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

    string private _baseDirectoryUri;
    uint8 public uriPadDigits;
    uint256[38] private _gap;
}