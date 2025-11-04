// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract InvoiceTokenWrapper is ERC20, Owned {
    address public immutable invoiceTokenAddress;
    uint256 public immutable invoiceSlotId;

    constructor(
        address invoiceToken,
        uint256 slotId,
        uint8 decimals,
        address owner
    ) ERC20(
        _constructName(slotId),
        _constructSymbol(slotId),
        decimals
    ) Owned(owner) {
        invoiceTokenAddress = invoiceToken;
        invoiceSlotId = slotId;
    }

    function _constructName(uint256 slotId) internal pure returns (string memory) {
        return string(abi.encodePacked("Invoice Wrapper ", Strings.toString(slotId)));
    }

    function _constructSymbol(uint256 slotId) internal pure returns (string memory) {
        return string(abi.encodePacked("INVW-", Strings.toString(slotId)));
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}
