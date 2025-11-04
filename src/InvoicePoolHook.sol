// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseHook } from "lib/v4-periphery/src/utils/BaseHook.sol";
import { Hooks } from "lib/v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import { SwapParams } from "lib/v4-periphery/lib/v4-core/src/types/PoolOperation.sol";
import { IPoolManager } from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { Currency } from "lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { BeforeSwapDelta } from "lib/v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";
import { InvoiceToken } from "./InvoiceToken.sol";
import { InvoiceTokenWrapper } from "./InvoiceTokenWrapper.sol";

contract InvoicePoolHook is BaseHook {
    error TokenExpired(address tokenAddress, uint256 slotId, uint256 dueDate, uint256 currentTime);

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        _checkTokenExpiration(key.currency0);
        _checkTokenExpiration(key.currency1);

        return (
            BaseHook.beforeSwap.selector,  // function selector
            BeforeSwapDelta.wrap(0),       // no delta modification
            0                              // no fee override
        );
    }

    function _checkTokenExpiration(Currency currency) internal view {
        address tokenAddress = Currency.unwrap(currency);

        if (_isInvoiceTokenWrapper(tokenAddress)) {
            InvoiceTokenWrapper wrapper = InvoiceTokenWrapper(tokenAddress);
            uint256 slotId = wrapper.invoiceSlotId();
            address erc3525Address = wrapper.invoiceTokenAddress();
            InvoiceToken invoiceToken = InvoiceToken(erc3525Address);

            InvoiceToken.SlotInfo memory slotInfo = invoiceToken.getSlotInfo(slotId);

            // freeze all invoice wrapper swaps once the due date is reached
            if (block.timestamp >= slotInfo.dueDate) {
                revert TokenExpired(erc3525Address, slotId, slotInfo.dueDate, block.timestamp);
            }
        }
    }

    function _isInvoiceTokenWrapper(address tokenAddress) internal view returns (bool) {
        try InvoiceTokenWrapper(tokenAddress).invoiceSlotId() returns (uint256) {
            // if the token has an invoice slot id, it's likely an invoice token wrapper
            return true;
        } catch {
            // fail, this is a regular ERC20
            return false;
        }
    }
}
