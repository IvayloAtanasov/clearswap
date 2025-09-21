// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Deployers} from "lib/v4-core/test/utils/Deployers.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "lib/permit2/test/utils/DeployPermit2.sol";
import {IPoolManager} from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "lib/v4-periphery/lib/v4-core/src/PoolManager.sol";
import {IPositionManager} from "lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionManager} from "lib/v4-periphery/src/PositionManager.sol";
import {IWETH9} from "lib/v4-periphery/src/interfaces/external/IWETH9.sol";
import {IPositionDescriptor} from "lib/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IStateView} from "lib/v4-periphery/src/interfaces/IStateView.sol";
import {StateView} from "lib/v4-periphery/src/lens/StateView.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract SetupTest is Deployers {
    function deployPermit2() public returns (IPermit2) {
        // use precompiled code from deployer script contract
        DeployPermit2 deployer = new DeployPermit2();
        IPermit2 permit2 = IPermit2(deployer.deployPermit2());

        return permit2;
    }

    function deployPoolManager() public returns (IPoolManager) {
        IPoolManager poolManager = new PoolManager(address(this));

        return poolManager;
    }

    function deployPositionManager(IPoolManager _poolManager, IPermit2 _permit2) public returns (IPositionManager) {
        // notifier system, gas limit for unsubscribe operations
        uint256 unsubscribeGasLimit = 300_000;
        // no nft position metadata needed, for simplicity
        IPositionDescriptor positionDescriptor = IPositionDescriptor(address(0));
        // no native eth wrapper needed in v4
        IWETH9 weth9 = IWETH9(address(0));
        IPositionManager positionManager = new PositionManager(
            _poolManager,
            _permit2,
            unsubscribeGasLimit,
            positionDescriptor,
            weth9
        );

        return positionManager;
    }

    function deployStateView(IPoolManager _poolManager) public returns (IStateView) {
        IStateView stateView = new StateView(_poolManager);

        return stateView;
    }

    function deployTestTokens() public returns (MockERC20 testEur, MockERC20 testBgn) {
        testEur = new MockERC20("EURT", "EURT", 18);
        testEur.mint(address(this), 1000000000000000000000); // 1000 EURT

        testBgn = new MockERC20("BGNT", "BGNT", 18);
        testBgn.mint(address(this), 1000000000000000000000); // 1000 BGNT

        return (testEur, testBgn);
    }
}
