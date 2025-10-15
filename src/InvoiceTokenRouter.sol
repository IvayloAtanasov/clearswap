// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {IStateView} from "lib/v4-periphery/src/interfaces/IStateView.sol";
import {Actions} from "lib/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "lib/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {ModifyLiquidityParams} from "lib/v4-periphery/lib/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "lib/v4-periphery/lib/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import {Constants} from "lib/v4-periphery/lib/v4-core/test/utils/Constants.sol";
import {IHooks} from "lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import {InvoiceToken} from "./InvoiceToken.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC3525Receiver} from "lib/erc-3525/contracts/IERC3525Receiver.sol";
import {ActionConstants} from "lib/v4-periphery/src/libraries/ActionConstants.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {InvoiceTokenWrapper} from "./InvoiceTokenWrapper.sol";
import {Utils} from "./Utils.sol";

contract InvoiceTokenRouter is ERC165, IERC3525Receiver {
    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    IStateView public immutable stateView;
    IPermit2 public immutable permit2;
    InvoiceToken public immutable invoiceToken;
    IHooks public immutable hook;

    // all pools use the same fee and tick spacing for simplicity
    uint24 public immutable poolFee = Constants.FEE_MEDIUM;
    int24 public immutable poolTickSpacing = 60;

    struct CallbackData {
        address sender;
        PoolKey poolKey;
        SwapParams params;
        bytes hookData;
    }

    // ERC3525 slot to ERC20 wrapper address
    mapping(uint256 => address) public slotToWrapper;

    constructor(
        address poolManagerAddress,
        address positionManagerAddress,
        address stateViewAddress,
        address permit2Address,
        address invoiceTokenAddress,
        address hookAddress
    ) {
        poolManager = IPoolManager(poolManagerAddress);
        positionManager = IPositionManager(positionManagerAddress);
        stateView = IStateView(stateViewAddress);
        permit2 = IPermit2(permit2Address);
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
                6,
                address(this)
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
            poolFee,
            poolTickSpacing,
            hook
        );

        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        return poolKey;
    }

    function getWrapperAddress(uint256 tokenId) public view returns (address) {
        uint256 slot = invoiceToken.slotOf(tokenId);
        return slotToWrapper[slot];
    }

    function addLiquidity(
        uint256 tokenId,
        address swapTokenAddress,
        uint256 invoiceTokenAmount,
        uint256 swapTokenAmount,
        bytes calldata hookData
    ) public {
        uint256 slotId = invoiceToken.slotOf(tokenId);
        require(
            slotToWrapper[slotId] != Constants.ADDRESS_ZERO,
            "InvoiceTokenRouter: Wrapper not initialized for slot"
        );

        // lock invoice tokens in router for wrapper tokens
        invoiceToken.transferFrom(tokenId, address(this), invoiceTokenAmount);
        // mint wrapper tokens directly to position manager
        InvoiceTokenWrapper wrapperToken = InvoiceTokenWrapper(slotToWrapper[slotId]);
        wrapperToken.mint(address(positionManager), invoiceTokenAmount);
        // transfer swap tokens from user to position manager via permit2
        permit2.transferFrom(
            msg.sender,
            address(positionManager),
            uint160(swapTokenAmount), // Note: potential conversion issue here
            swapTokenAddress
        );

        // build pool key
        PoolKey memory poolKey = _buildPoolKeyFromSlotAndSwapToken(slotId, swapTokenAddress);

        // 1. ACTIONS
        // Note: actions conversion to 1 byte (uint8) is missing from docs
        // https://docs.uniswap.org/contracts/v4/guides/position-manager
        // but can be found in the tests
        // https://github.com/Uniswap/v4-periphery/blob/main/test/shared/Planner.sol#L32
        // and in this implementation
        // https://github.com/ScoutiFi-xyz/blockchain/blob/main/deploy/local/03-swap.ts#L106-L109
        bytes memory actions = abi.encodePacked(
            // mint position for amount of liquidity calculated
            uint8(Actions.MINT_POSITION),
            // settle currency0 from PositionManager balance
            uint8(Actions.SETTLE),
            // settle currency1 from PositionManager balance
            uint8(Actions.SETTLE),
            // return leftover currency0 tokens to user
            uint8(Actions.SWEEP),
            // return leftover currency1 tokens to user
            uint8(Actions.SWEEP)
        );

        // 2. ACTIONS PARAMS
        bytes[] memory params = new bytes[](5);

        // 2.1. Parameters for MINT_POSITION
        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(poolKey.toId());
        (int24 tickLower, int24 tickUpper) = adjustTicks(TickMath.MIN_TICK, TickMath.MAX_TICK, poolKey.tickSpacing);
        uint256 amount0Max = Currency.unwrap(poolKey.currency0) == swapTokenAddress ? swapTokenAmount : invoiceTokenAmount;
        uint256 amount1Max = Currency.unwrap(poolKey.currency1) == swapTokenAddress ? swapTokenAmount : invoiceTokenAmount;

        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );

        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,    // Amount of liquidity to mint
            amount0Max,   // Maximum amount of token0 to use
            amount1Max,   // Maximum amount of token1 to use
            msg.sender,   // Who receives the NFT
            hookData
        );

        // 2.2. Parameters for SETTLE
        // payerIsUser = false (use contract balance)
        params[1] = abi.encode(poolKey.currency0, ActionConstants.OPEN_DELTA, false);
        // 2.3. Parameters for SETTLE
        params[2] = abi.encode(poolKey.currency1, ActionConstants.OPEN_DELTA, false);

        // 2.4. Parameters for SWEEP
        params[3] = abi.encode(poolKey.currency0, msg.sender);
        // 2.5. Parameters for SWEEP
        params[4] = abi.encode(poolKey.currency1, msg.sender);

        uint256 expectedTokenId = positionManager.nextTokenId();

        // ENCODE COMMANDS
        bytes memory unlockData = abi.encode(
            actions,
            params
        );
        // EXECUTE
        positionManager.modifyLiquidities(
            unlockData,
            block.timestamp + 60  // 60 second deadline
        );

        // Transfer the NFT that was just minted (expectedTokenId)
        IERC721(address(positionManager)).transferFrom(address(this), msg.sender, expectedTokenId);
    }

    function removeLiquidity(
        uint256 slotId,
        address swapTokenAddress,
        uint256 amount,
        bytes calldata hookData
    ) public {
        // TODO:
    }

    // swap for invoice token pools, created by this router
    function swapInvoice(
        uint256 slotId,
        address swapTokenAddress,
        bool sellInvoice,
        int256 amountSpecified,
        bytes calldata hookData
    ) public {
        address wrapperTokenAddress = slotToWrapper[slotId];

        // Check that the wrapper token exists for the given slot
        require(
            wrapperTokenAddress != address(0),
            "InvoiceTokenRouter: Wrapper not initialized for slot"
        );

        PoolKey memory poolKey = _buildPoolKeyFromSlotAndSwapToken(slotId, swapTokenAddress);

        Currency swapTokenCurrency = Currency.wrap(swapTokenAddress);
        Currency wrapperTokenCurrency = Currency.wrap(wrapperTokenAddress);

        // determine zeroForOne for the pool based on trade directuon
        bool swapTokenIsCurrency0 = swapTokenCurrency == poolKey.currency0;
        bool wrapperTokenIsCurrency0 = wrapperTokenCurrency == poolKey.currency0;
        // If selling invoice (invoice wrapper → swap token):
        //     wrapper is currency0 → zeroForOne = true (0→1)
        //     wrapper is currency1 → zeroForOne = false (1→0)
        // If selling swap token (swap token → invoice wrapper):
        //     swap token is currency0 → zeroForOne = true (0→1)
        //     swap token is currency1 → zeroForOne = false (1→0)
        bool zeroForOne = sellInvoice ? wrapperTokenIsCurrency0 : swapTokenIsCurrency0;

        _unlock(poolKey, zeroForOne, amountSpecified, hookData);
    }

    // a regular swap, for testing regular Uniswap V4 pools
    function swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata hookData
    ) public {
        _unlock(poolKey, zeroForOne, amountSpecified, hookData);
    }

    function unlockCallback(bytes calldata rawData) external returns (int128 reciprocalAmount) {
        require(msg.sender == address(poolManager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        return _swap(
            data.poolKey,
            data.params.zeroForOne,
            data.params.amountSpecified,
            data.params.sqrtPriceLimitX96,
            data.hookData
        );

        // TODO: settle invoce tokens from/to router after swap?
    }

    // Mark that this contract can safely receive ERC-3525 tokens
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC3525Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // Hook for received ERC-3525 tokens, must exist along with supportsInterface
    function onERC3525Received(
        address operator_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 value_,
        bytes calldata data_
    ) external pure override returns (bytes4) {
        return IERC3525Receiver.onERC3525Received.selector;
    }

    function _buildPoolKeyFromSlotAndSwapToken(
        uint256 slotId,
        address swapTokenAddress
    ) private view returns (PoolKey memory) {
        address wrapperTokenAddress = slotToWrapper[slotId];

        // Check that the wrapper token exists for the given slot
        require(
            wrapperTokenAddress != Constants.ADDRESS_ZERO,
            "InvoiceTokenRouter: Wrapper not initialized for slot"
        );

        (Currency currency0, Currency currency1) = Utils.sort(
            swapTokenAddress,
            wrapperTokenAddress
        );

        PoolKey memory poolKey = PoolKey(
            currency0,
            currency1,
            poolFee,
            poolTickSpacing,
            hook
        );

        return poolKey;
    }

    function _unlock(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata hookData
    ) private {
        // TODO: should be configurable
        uint160 priceBuffer = 1000;
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + priceBuffer : TickMath.MAX_SQRT_PRICE - priceBuffer;
        SwapParams memory params = SwapParams(
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96
        );
        poolManager.unlock(
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
            BalanceDelta delta = poolManager.swap(
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

    /// @notice Adjusts ticks to the nearest multiples of tickSpacing.
    /// @dev Returns the adjusted lower and upper ticks.
    /// @param tickLower The lower tick (can be negative).
    /// @param tickUpper The upper tick (can be negative).
    /// @param tickSpacing The tick spacing (must be positive).
    /// @return tickLowerAdjusted The lower tick, rounded up to the nearest multiple of tickSpacing.
    /// @return tickUpperAdjusted The upper tick, rounded down to the nearest multiple of tickSpacing.
    function adjustTicks(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing
    ) internal pure returns (int24 tickLowerAdjusted, int24 tickUpperAdjusted) {
        require(tickSpacing > 0, "tickSpacing must be positive");

        // Round up tickLower to the nearest multiple of tickSpacing
        if (tickLower % tickSpacing == 0) {
            tickLowerAdjusted = tickLower;
        } else if (tickLower > 0) {
            tickLowerAdjusted = ((tickLower + tickSpacing - 1) / tickSpacing) * tickSpacing;
        } else {
            tickLowerAdjusted = (tickLower / tickSpacing) * tickSpacing;
        }

        // Round down tickUpper to the nearest multiple of tickSpacing
        if (tickUpper % tickSpacing == 0) {
            tickUpperAdjusted = tickUpper;
        } else if (tickUpper > 0) {
            tickUpperAdjusted = (tickUpper / tickSpacing) * tickSpacing;
        } else {
            tickUpperAdjusted = ((tickUpper - tickSpacing + 1) / tickSpacing) * tickSpacing;
        }
    }
}
