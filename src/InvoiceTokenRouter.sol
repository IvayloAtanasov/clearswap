// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniversalRouter} from "lib/universal-router/contracts/UniversalRouter.sol";
import {IPoolManager} from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {UnsupportedProtocol} from "lib/universal-router/contracts/deploy/UnsupportedProtocol.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {RouterParameters} from "lib/universal-router/contracts/types/RouterParameters.sol";

contract InvoiceTokenRouter is UniversalRouter {
    constructor(
        IPermit2 _permit2,
        IPoolManager _poolManager,
        IPositionManager _positionManager,
        UnsupportedProtocol _unsupportedProtocol
    ) UniversalRouter(
        RouterParameters({
            permit2: address(_permit2),
            weth9: address(_unsupportedProtocol),
            v2Factory: address(_unsupportedProtocol),
            v3Factory: address(_unsupportedProtocol),
            pairInitCodeHash: bytes32(0), // for V2
            poolInitCodeHash: bytes32(0), // for V3
            v4PoolManager: address(_poolManager),
            v3NFTPositionManager: address(_unsupportedProtocol),
            v4PositionManager: address(_positionManager)
        })
    ) {}
}
