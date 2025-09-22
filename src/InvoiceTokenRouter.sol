// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "lib/v4-periphery/lib/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import {Constants} from "lib/v4-periphery/lib/v4-core/test/utils/Constants.sol";
import {IHooks} from "lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import {InvoiceToken} from "./InvoiceToken.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {InvoiceTokenWrapper} from "./InvoiceTokenWrapper.sol";
import {Utils} from "./Utils.sol";

contract InvoiceTokenRouter {
    IPoolManager public immutable manager;
    InvoiceToken public immutable invoiceToken;
    IHooks public immutable hook;

    struct CallbackData {
        address sender;
        PoolKey poolKey;
        SwapParams params;
        bytes hookData;
    }

    mapping(uint256 => address) public slotToWrapper;

    constructor(
        address poolManagerAddress,
        address invoiceTokenAddress,
        address hookAddress
    ) {
        manager = IPoolManager(poolManagerAddress);
        invoiceToken = InvoiceToken(invoiceTokenAddress); // TODO: use interface
        hook = IHooks(hookAddress);
    }

    function initializeInvoicePool(
        uint256 slotId,
        address swapTokenAddress
    ) public returns (PoolKey memory) {
        // create wrapper for this slot if not exists
        if (slotToWrapper[slotId] == Constants.ADDRESS_ZERO) {
            string memory slotWrapperName = string(
                abi.encodePacked("Invoice ", Strings.toString(slotId))
            );
            InvoiceTokenWrapper invoiceTokenWrapper = new InvoiceTokenWrapper(
                "Invoice Token Wrapper",
                slotWrapperName,
                6
            );
            slotToWrapper[slotId] = address(invoiceTokenWrapper);
        }

        (Currency currency0, Currency currency1) = Utils.sort(
            swapTokenAddress,
            slotToWrapper[slotId]
        );

        PoolKey memory poolKey = PoolKey(
            currency0,
            currency1,
            Constants.FEE_MEDIUM,
            60, // tick spacing
            hook
        );

        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        return poolKey;
    }

    function swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata hookData
    ) public {
        _unlock(poolKey, zeroForOne, amountSpecified, hookData);
    }

    function unlockCallback(bytes calldata rawData) external returns (int128 reciprocalAmount) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        return _swap(
            data.poolKey,
            data.params.zeroForOne,
            data.params.amountSpecified,
            data.params.sqrtPriceLimitX96,
            data.hookData
        );
    }

    function _unlock(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata hookData
    ) private {
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        SwapParams memory params = SwapParams(
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );
        manager.unlock(
            abi.encode(
                CallbackData(msg.sender, poolKey, params, hookData)
            )
        );
    }

    function _swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes memory hookData
    ) private returns (int128 reciprocalAmount) {
        unchecked {
            BalanceDelta delta = manager.swap(
                poolKey,
                SwapParams(
                    zeroForOne,
                    amountSpecified,
                    sqrtPriceLimitX96
                ),
                hookData
            );

            reciprocalAmount = (zeroForOne == amountSpecified < 0) ? delta.amount1() : delta.amount0();
        }
    }
}
