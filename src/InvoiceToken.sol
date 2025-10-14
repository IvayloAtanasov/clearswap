// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC3525} from "lib/erc-3525/contracts/ERC3525.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

contract InvoiceToken is ERC3525, Owned {
    struct SlotInfo {
        uint256 dueDate;        // Unix timestamp
        uint8 riskProfile;      // 1=Low, 2=Medium, 3=High
        bool exists;
    }

    // slot => SlotInfo
    mapping(uint256 => SlotInfo) public slotInfo;

    // tokenId => IPFS CID (each token has its own invoice document)
    mapping(uint256 => string) public tokenToIPFS;

    uint256 private _slotCounter;

    event SlotCreated(uint256 indexed slot, uint256 dueDate, uint8 riskProfile);
    event InvoiceMinted(uint256 indexed tokenId, uint256 indexed slot, string ipfsHash);

    constructor() ERC3525("Invoice Token", "INVOICE", 6) Owned(msg.sender) {}

    function getSlotInfo(uint256 slot) public view returns (SlotInfo memory) {
        return slotInfo[slot];
    }

    function createSlot(
        uint256 dueDate,
        uint8 riskProfile
    ) external onlyOwner returns (uint256 slot) {
        require(riskProfile >= 1 && riskProfile <= 3, "Invalid risk profile");
        require(dueDate > block.timestamp, "Due date must be in future");

        _slotCounter++;
        slot = _slotCounter;

        slotInfo[slot] = SlotInfo({
            dueDate: dueDate,
            riskProfile: riskProfile,
            exists: true
        });

        emit SlotCreated(slot, dueDate, riskProfile);
        return slot;
    }

    function mintInvoice(
        address to,
        uint256 slot,
        uint256 value,
        string calldata ipfsCid
    ) external onlyOwner returns (uint256 tokenId) {
        require(slotInfo[slot].exists, "Slot does not exist");
        require(slotInfo[slot].dueDate > block.timestamp, "Slot expired");
        require(bytes(ipfsCid).length > 0, "IPFS CID required");

        tokenId = _createOriginalTokenId();

        // Store IPFS CID for this specific token
        tokenToIPFS[tokenId] = ipfsCid;

        // Mint the ERC-3525 token
        _mint(to, tokenId, slot, value);

        emit InvoiceMinted(tokenId, slot, ipfsCid);
        return tokenId;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");

        string memory ipfsCid = tokenToIPFS[tokenId];
        require(bytes(ipfsCid).length > 0, "No IPFS CID for token");

        return string(abi.encodePacked("ipfs://", ipfsCid));
    }

    function balanceOfSlot(address owner, uint256 slot) external view returns (uint256 totalValue) {
        uint256 tokenCount = balanceOf(owner); // Number of tokens

        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            if (slotOf(tokenId) == slot) {
                // Note: balanceOf(tokenId) returns balance of all tokens in emission for this id,
                // as a given tokenId can be owned by one user at a time
                totalValue += balanceOf(tokenId); // Token value
            }
        }

        return totalValue;
    }

    // override transfer between token ids
    // in order to ensure tokenId (many) >- ipfs document (one) relation is always kept
    function transferFrom(
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 value_
    ) public payable virtual override {
        require(
            keccak256(bytes(tokenToIPFS[toTokenId_])) == keccak256(bytes(tokenToIPFS[fromTokenId_])),
            "InvoiceToken: IPFS CID mismatch"
        );

        _spendAllowance(_msgSender(), fromTokenId_, value_);
        _transferValue(fromTokenId_, toTokenId_, value_);
    }

    function _createDerivedTokenId(uint256 fromTokenId) internal override returns (uint256) {
        // derived token id inherits the ipfs invoice document
        string memory ipfsCid = tokenToIPFS[fromTokenId];
        require(bytes(ipfsCid).length > 0, "InvoiceToken: No IPFS CID for token");

        uint256 newTokenId = _createOriginalTokenId();
        tokenToIPFS[newTokenId] = ipfsCid;

        return newTokenId;
    }
}
