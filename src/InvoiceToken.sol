// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC3525} from "lib/erc-3525/contracts/ERC3525.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract InvoiceToken is ERC3525, Ownable {
    struct SlotInfo {
        uint256 dueDate;        // Unix timestamp
        uint8 riskProfile;      // 1=Low, 2=Medium, 3=High
        bool exists;
    }

    // slot => SlotInfo
    mapping(uint256 => SlotInfo) public slotInfo;

    // tokenId => IPFS CID (each token has its own invoice document)
    mapping(uint256 => string) public tokenToIPFS;

    uint256 private _tokenIdCounter;
    uint256 private _slotCounter;

    event SlotCreated(uint256 indexed slot, uint256 dueDate, uint8 riskProfile);
    event InvoiceMinted(uint256 indexed tokenId, uint256 indexed slot, string ipfsHash);

    constructor() ERC3525("Invoice Token", "INVOICE", 6) Ownable(msg.sender) {}

    function getSlotInfo(uint256 slot) public view returns (SlotInfo memory) {
        return slotInfo[slot];
    }

    function createSlot(
        uint256 dueDate,
        uint8 riskProfile
    ) external onlyOwner() returns (uint256 slot) {
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

    function getWrapperAddress() public view returns (address) {
        // TODO
        return address(0);
    }

    function mintInvoice(
        address to,
        uint256 slot,
        uint256 value,
        string calldata ipfsCid
    ) external onlyOwner() returns (uint256 tokenId) {
        require(slotInfo[slot].exists, "Slot does not exist");
        require(slotInfo[slot].dueDate > block.timestamp, "Slot expired");
        require(bytes(ipfsCid).length > 0, "IPFS CID required");

        _tokenIdCounter++;
        tokenId = _tokenIdCounter;

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
}
