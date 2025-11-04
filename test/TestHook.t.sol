// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {BaseTestHooks} from "lib/v4-core/src/test/BaseTestHooks.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {Hooks} from "lib/v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {IStateView} from "lib/v4-periphery/src/interfaces/IStateView.sol";
import {HookMiner} from "lib/v4-periphery/src/utils/HookMiner.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {InvoiceTokenRouter} from "../src/InvoiceTokenRouter.sol";
import {InvoiceToken} from "../src/InvoiceToken.sol";
import {InvoiceTokenWrapper} from "../src/InvoiceTokenWrapper.sol";
import {SetupTest} from "./SetupTest.t.sol";
import {InvoicePoolHook} from "../src/InvoicePoolHook.sol";

contract TestHook is SetupTest {
    IPermit2 public permit2;
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IStateView public stateView;

    MockERC20 public eurTestToken;
    InvoiceToken public invoiceToken;
    uint256 public slotId;
    uint256 public invoiceTokenId;
    InvoiceTokenRouter public invoiceTokenRouter;
    InvoicePoolHook public invoicePoolHook;

    function setUp() public {
        // make msg sender 0x1
        vm.startPrank(address(0x1));

        // existing protocol contracts
        permit2 = deployPermit2();
        poolManager = deployPoolManager();
        positionManager = deployPositionManager(poolManager, permit2);
        stateView = deployStateView(poolManager);
        vm.stopPrank();

        // deploy hook
        invoicePoolHook = deployInvoicePoolHook(address(poolManager));
    }

    function testTokenExpirationSuccess() public {
        eurTestToken = deployTestTokens(address(0x1), 1_000_000_000);
        // (invoiceToken, slotId, invoiceTokenId) = deployInvoiceSlotAndToken(address(0x1));

        // // contracts under test
        // invoiceTokenRouter = new InvoiceTokenRouter(
        //     address(poolManager),
        //     address(positionManager),
        //     address(stateView),
        //     address(permit2),
        //     address(invoiceToken),
        //     address(invoicePoolHook)
        // );

        // TODO
    }

    function testTokenExpirationFail() public {}

    function deployInvoicePoolHook(address _poolManagerAddress) public returns (InvoicePoolHook) {
        // forge CREATE2 deployer proxy
        address CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

        // hook contracts must have specific flags encoded in the address
        uint160 permissions = uint160(
            Hooks.BEFORE_SWAP_FLAG
        );

        // Mine a salt that will produce a hook address with the correct permissions
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, permissions, type(InvoicePoolHook).creationCode, abi.encode(_poolManagerAddress));

        // ----------------------------- //
        // Deploy the hook using CREATE2 //
        // ----------------------------- //
        vm.broadcast();
        InvoicePoolHook hook = new InvoicePoolHook{salt: salt}(IPoolManager(_poolManagerAddress));
        require(address(hook) == hookAddress, "InvoicePoolHook: hook address mismatch");

        return hook;
    }
}
