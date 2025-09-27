// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SetupTest} from "./SetupTest.t.sol";
import {InvoiceTokenRouter} from "../src/InvoiceTokenRouter.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Constants} from "lib/v4-periphery/lib/v4-core/test/utils/Constants.sol";
import {SortTokens} from "lib/v4-periphery/lib/v4-core/test/utils/SortTokens.sol";
import {PoolKey} from "lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {PoolManager} from "lib/v4-periphery/lib/v4-core/src/PoolManager.sol";
import {IHooks} from "lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {IStateView} from "lib/v4-periphery/src/interfaces/IStateView.sol";
import {InvoiceToken} from "../src/InvoiceToken.sol";

contract TestWrapAndSwap is SetupTest {
    IPermit2 public permit2;
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IStateView public stateView;

    MockERC20 public eurTestToken;
    InvoiceToken public invoiceToken;
    uint256 public slotId;
    uint256 public invoiceTokenId;
    InvoiceTokenRouter public invoiceTokenRouter;

    function setUp() public {
        // make msg sender 0x1
        vm.startPrank(address(0x1));

        // existing protocol contracts
        permit2 = deployPermit2();
        poolManager = deployPoolManager();
        positionManager = deployPositionManager(poolManager, permit2);
        stateView = deployStateView(poolManager);

        // test env
        eurTestToken = deployTestTokens();
        (invoiceToken, slotId, invoiceTokenId) = deployInvoiceSlotAndToken();

        // contracts under test
        invoiceTokenRouter = new InvoiceTokenRouter(
            address(poolManager),
            address(invoiceToken),
            Constants.ADDRESS_ZERO // TODO: use hook
        );
    }

    function testBasic() public {
        PoolKey memory poolKey = invoiceTokenRouter.initializeInvoicePool(
            slotId,
            address(eurTestToken)
        );

        // invoiceTokenRouter.swap(poolKey, true, 1000000000000000000, Constants.ZERO_BYTES);

        // spend invoice tokens, get EURT
        bool zeroForOne = true;
        int256 amountSpecified = 10_000_000; // 10 EURT
        bytes memory hookData = Constants.ZERO_BYTES;
        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            zeroForOne,
            amountSpecified,
            hookData
        );

        // 1.
        // provide ERC-3525 liquidity
        // wrap ERC-3525 into ERC-20
        // add into pool with ERC-20/EURC

        // 2.
        // call router swap
        // wrap ERC-3525 into ERC-20
        // swap ERC-20 into EURC

        // 3.
        // call router swap
        // swap EUR into ERC-20
        // unwrap ERC-20 into ERC-3525

        assertEq(uint256(1 + 1), uint256(2));
    }

    function deployInvoiceSlotAndToken() private returns (InvoiceToken, uint256, uint256) {
        InvoiceToken _invoiceToken = new InvoiceToken();

        uint256 dueDate = 1768867200; // 2026-01-20
        uint8 riskProfile = 2; // moderate risk
        uint256 _slotId = _invoiceToken.createSlot(dueDate, riskProfile);

        string memory invoiceFileCid = "bafkreigq27kupea5z4dleffwb7bw4dddwlrstrbysc7qr3lrpn4c3yjilq";
        uint256 _tokenId = _invoiceToken.mintInvoice(
            address(this),
            _slotId,
            4_380_000_000, // 4380 EUR
            invoiceFileCid
        );

        return (_invoiceToken, _slotId, _tokenId);
    }
}
