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
import {Constants} from "lib/v4-periphery/lib/v4-core/test/utils/Constants.sol";
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

    function testTokenExpirationValidation() public {
        MockERC20 eurTestToken = deployTestTokens(address(0x1), 10_000_000_000); // 10k EURT

        InvoiceToken invoiceToken = new InvoiceToken();
        uint256 dueDate = block.timestamp + 1 days; // now + 1 day
        uint8 riskProfile = 2; // moderate risk
        uint256 slotId = invoiceToken.createSlot(dueDate, riskProfile);
        string memory invoiceFileCid = "bafkreigq27kupea5z4dleffwb7bw4dddwlrstrbysc7qr3lrpn4c3yjilq";
        uint256 tokenId = invoiceToken.mintInvoice(
            address(0x1),
            slotId,
            4_380_000_000, // 4380 EUR
            invoiceFileCid
        );

        invoiceTokenRouter = new InvoiceTokenRouter(
            address(poolManager),
            address(positionManager),
            address(stateView),
            address(permit2),
            address(invoiceToken),
            address(invoicePoolHook)
        );

        vm.startPrank(address(0x1));
        invoiceTokenRouter.initializeInvoicePool(
            slotId,
            address(eurTestToken)
        );
        invoiceToken.setApprovalForAll(address(invoiceTokenRouter), true);
        eurTestToken.approve(address(permit2), 4_380_000_000);
        permit2.approve(
            address(eurTestToken),
            address(invoiceTokenRouter),
            4_380_000_000,
            type(uint48).max // max deadline
        );
        invoiceTokenRouter.provideLiquidity(
            tokenId,
            address(eurTestToken),
            4_380_000_000,
            4_380_000_000,
            Constants.ZERO_BYTES
        );

        // approvals
        eurTestToken.approve(address(permit2), 500_000_000);
        permit2.approve(
            address(eurTestToken),
            address(invoiceTokenRouter),
            500_000_000,
            type(uint48).max // max deadline
        );

        // success
        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            false,
            100_000_000, // buy 100 invoice tokens
            Constants.ZERO_BYTES
        );
        assertEq(invoiceToken.balanceOfSlot(address(0x1), slotId), 100_000_000);

        // fail
        vm.warp(dueDate + 1 days);
        // expecting any revert, without specific selector as uniswap will wrap TokenExpired error into WrappedError
        vm.expectRevert();
        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            false,
            100_000_000, // buy 100 invoice tokens
            Constants.ZERO_BYTES
        );
    }

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
