// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

contract InvoiceTokenWrapper is ERC20, Owned {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address owner
    ) ERC20(name, symbol, decimals) Owned(owner) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}
