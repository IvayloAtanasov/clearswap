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
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {InvoiceToken} from "../src/InvoiceToken.sol";
import {InvoiceTokenWrapper} from "../src/InvoiceTokenWrapper.sol";
import "forge-std/console.sol";

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

    uint256 public eurAmountOwned = 5_000_000_000; // 5000 EURT

    function setUp() public {
        // make msg sender 0x1
        vm.startPrank(address(0x1));

        // existing protocol contracts
        permit2 = deployPermit2();
        poolManager = deployPoolManager();
        positionManager = deployPositionManager(poolManager, permit2);
        stateView = deployStateView(poolManager);

        // test env
        eurTestToken = deployTestTokens(address(0x1), eurAmountOwned);
        (invoiceToken, slotId, invoiceTokenId) = deployInvoiceSlotAndToken(address(0x1));

        // contracts under test
        invoiceTokenRouter = new InvoiceTokenRouter(
            address(poolManager),
            address(positionManager),
            address(stateView),
            address(permit2),
            address(invoiceToken),
            Constants.ADDRESS_ZERO // TODO: use hook
        );
    }

    function testInitialize() public {
        PoolKey memory poolKey = invoiceTokenRouter.initializeInvoicePool(
            slotId,
            address(eurTestToken)
        );

        uint256 eurBalanceBefore = eurTestToken.balanceOf(address(0x1));
        uint256 invoiceBalanceBefore = invoiceToken.balanceOfSlot(address(0x1), slotId);

        // smoke test with regular swap
        invoiceTokenRouter.swap(poolKey, true, 10_000_000, Constants.ZERO_BYTES);

        uint256 eurBalanceAfterSwap = eurTestToken.balanceOf(address(0x1));
        uint256 invoiceBalanceAfterSwap = invoiceToken.balanceOfSlot(address(0x1), slotId);

        // no liquidity, no swap change, no error either
        assertEq(eurBalanceAfterSwap, eurBalanceBefore);
        assertEq(invoiceBalanceAfterSwap, invoiceBalanceBefore);
    }

    function testSwapNoLiquidity() public {
        invoiceTokenRouter.initializeInvoicePool(
            slotId,
            address(eurTestToken)
        );

        uint256 eurBalanceBefore = eurTestToken.balanceOf(address(0x1));
        uint256 invoiceBalanceBefore = invoiceToken.balanceOfSlot(address(0x1), slotId);

        // try to spend invoice tokens, get EURT
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

        uint256 eurBalanceAfterSwap = eurTestToken.balanceOf(address(0x1));
        uint256 invoiceBalanceAfterSwap = invoiceToken.balanceOfSlot(address(0x1), slotId);

        // no liquidity, no swap change, no error either
        assertEq(eurBalanceAfterSwap, eurBalanceBefore);
        assertEq(invoiceBalanceAfterSwap, invoiceBalanceBefore);
    }

    function testProvideLiquidity() public {
        // Initialize the pool between invoice wrapper and EUR token
        invoiceTokenRouter.initializeInvoicePool(
            slotId,
            address(eurTestToken)
        );

        address invoiceTokenWrapperAddress = invoiceTokenRouter.getWrapperAddress(invoiceTokenId);
        InvoiceTokenWrapper invoiceTokenWrapper = InvoiceTokenWrapper(invoiceTokenWrapperAddress);

        // Approvals
        // - router as spender for tester 3525 invoice tokens
        invoiceToken.setApprovalForAll(address(invoiceTokenRouter), true);
        // - router as spender for ERC20 token through permit2
        eurTestToken.approve(address(permit2), 4_380_000_000);
        permit2.approve(
            address(eurTestToken),
            address(invoiceTokenRouter),
            4_380_000_000,
            type(uint48).max // max deadline
        );

        // Provide liquidity to the pool
        // add all invoice tokens owned for that much eur in 1:1 ratio
        uint256 positionTokenId = invoiceTokenRouter.provideLiquidity(
            invoiceTokenId,
            address(eurTestToken),
            4_380_000_000,
            4_380_000_000,
            Constants.ZERO_BYTES
        );

        // Check pool balances or LP token balances
        // - router pulled all invoice tokens from user (all in slot)
        assertEq(invoiceToken.balanceOfSlot(address(invoiceTokenRouter), slotId), 4_380_000_000);

        // - invoice token wrappers [router -> position manager -> pool manager]
        assertEq(invoiceTokenWrapper.balanceOf(address(0x1)), 0);
        assertEq(invoiceTokenWrapper.balanceOf(address(poolManager)), 4_380_000_000);

        // - EUR tokens [user -> position manager -> pool manager]
        assertEq(eurTestToken.balanceOf(address(0x1)), 620_000_000);
        assertEq(eurTestToken.balanceOf(address(poolManager)), 4_380_000_000);

        // - user has position NFT
        IERC721 positionNFT = IERC721(address(positionManager));
        assertEq(positionNFT.balanceOf(address(0x1)), positionTokenId);
    }

    function testRemoveLiquidity() public {
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

        uint256 positionTokenId = invoiceTokenRouter.provideLiquidity(
            invoiceTokenId,
            address(eurTestToken),
            4_380_000_000,
            4_380_000_000,
            Constants.ZERO_BYTES
        );

        // Approve router to spend position NFT
        IERC721(address(positionManager)).approve(address(invoiceTokenRouter), positionTokenId);
        // Remove liquidity and burn position NFT
        invoiceTokenRouter.removeLiquidity(
            positionTokenId,
            0, // chosing to be lenient with amounts
            0, // chosing to be lenient with amounts
            Constants.ZERO_BYTES
        );

        // TODO: assert
        // - user has invoice tokens, router does not (from this slot)
        // - user has EUR tokens
        // - user does not have position NFT
    }

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

    // function testSellInvoiceForToken() public {
    //     // 1. Initialize the pool between invoice wrapper and EUR token
    //     invoiceTokenRouter.initializeInvoicePool(
    //         slotId,
    //         address(eurTestToken)
    //     );

    //     // TODO: provide liquidity

    //     // 2. Get initial balances
    //     uint256 initialEurBalance = eurTestToken.balanceOf(address(0x1));
    //     uint256 initialInvoiceBalance = invoiceToken.balanceOfSlot(address(0x1), slotId);

    //     console.log("Initial EUR balance:", initialEurBalance);
    //     console.log("Initial invoice balance:", initialInvoiceBalance);

    //     // 3. Approve the router to spend our invoice tokens (if needed)
    //     invoiceToken.setApprovalForAll(address(invoiceTokenRouter), true);

    //     // TODO: approval for the 3525 token to be spend (locked) in the router?
    //     // TODO: router then mints the wrapper token
    //     //      - router spends the wrapper token

    //     // 4. Execute the swap: sell invoice for EUR tokens
    //     bool sellInvoice = true; // We're selling invoice tokens
    //     int256 amountSpecified = 1000e18; // Amount of invoice tokens to sell
    //     bytes memory hookData = Constants.ZERO_BYTES;

    //     // Call the swap function
    //     invoiceTokenRouter.swapInvoice(
    //         slotId,
    //         address(eurTestToken),
    //         sellInvoice,
    //         amountSpecified,
    //         hookData
    //     );

    //     // 5. Check balances after swap
    //     uint256 finalEurBalance = eurTestToken.balanceOf(address(0x1));
    //     uint256 finalInvoiceBalance = invoiceToken.balanceOfSlot(address(0x1), slotId);

    //     console.log("Final EUR balance:", finalEurBalance);
    //     console.log("Final invoice balance:", finalInvoiceBalance);

    //     // 6. Assertions
    //     assertGt(finalEurBalance, initialEurBalance, "Should have received EUR tokens");
    //     assertLt(finalInvoiceBalance, initialInvoiceBalance, "Should have spent invoice tokens");

    //     // 7. Check the difference matches expected amounts (accounting for fees)
    //     uint256 eurReceived = finalEurBalance - initialEurBalance;
    //     uint256 invoiceSpent = initialInvoiceBalance - finalInvoiceBalance;

    //     assertGt(eurReceived, 0, "Should have received some EUR");
    //     assertGt(invoiceSpent, 0, "Should have spent some invoice tokens");

    //     console.log("EUR received:", eurReceived);
    //     console.log("Invoice tokens spent:", invoiceSpent);
    // }

    // function testSellTokenForInvoice() public {
    //     // TODO:
    //     // TODO: approval for the swap token to be spend by the rotuer
    // }

    function deployInvoiceSlotAndToken(address mintAddress) private returns (InvoiceToken, uint256, uint256) {
        InvoiceToken _invoiceToken = new InvoiceToken();

        uint256 dueDate = 1768867200; // 2026-01-20
        uint8 riskProfile = 2; // moderate risk
        uint256 _slotId = _invoiceToken.createSlot(dueDate, riskProfile);

        string memory invoiceFileCid = "bafkreigq27kupea5z4dleffwb7bw4dddwlrstrbysc7qr3lrpn4c3yjilq";
        uint256 _tokenId = _invoiceToken.mintInvoice(
            mintAddress,
            _slotId,
            4_380_000_000, // 4380 EUR
            invoiceFileCid
        );

        return (_invoiceToken, _slotId, _tokenId);
    }
}
