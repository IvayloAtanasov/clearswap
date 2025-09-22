// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "lib/v4-periphery/lib/v4-core/src/types/Currency.sol";

library Utils {
    function sort(address tokenA, address tokenB)
        internal
        pure
        returns (Currency _currency0, Currency _currency1)
    {
        if (tokenA < tokenB) {
            (_currency0, _currency1) = (Currency.wrap(tokenA), Currency.wrap(tokenB));
        } else {
            (_currency0, _currency1) = (Currency.wrap(tokenB), Currency.wrap(tokenA));
        }
    }
}
