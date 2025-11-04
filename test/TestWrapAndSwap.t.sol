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
            Constants.ADDRESS_ZERO
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

        // assert user does not have position NFT
        IERC721 positionNFT = IERC721(address(positionManager));
        assertEq(positionNFT.balanceOf(address(0x1)), 0);

        // assert wrapper tokens burned
        address invoiceTokenWrapperAddress = invoiceTokenRouter.getWrapperAddress(invoiceTokenId);
        InvoiceTokenWrapper invoiceTokenWrapper = InvoiceTokenWrapper(invoiceTokenWrapperAddress);
        assertEq(invoiceTokenWrapper.balanceOf(address(0x1)), 0);
        assertEq(invoiceTokenWrapper.balanceOf(address(positionManager)), 0);
        // Note: 1 dust token left in pool manager due to rounding
        assertEq(invoiceTokenWrapper.balanceOf(address(poolManager)), 1);
        assertEq(invoiceTokenWrapper.balanceOf(address(invoiceTokenRouter)), 0);

        // assert user has invoice tokens, router does not (from this slot)
        assertEq(invoiceToken.balanceOfSlot(address(0x1), slotId), 4_379_999_999);
        assertEq(invoiceToken.balanceOfSlot(address(invoiceTokenRouter), slotId), 1);

        // assert user has EUR tokens
        assertEq(eurTestToken.balanceOf(address(0x1)), 4_999_999_999);
        assertEq(eurTestToken.balanceOf(address(positionManager)), 0);
        assertEq(eurTestToken.balanceOf(address(poolManager)), 1);
        assertEq(eurTestToken.balanceOf(address(invoiceTokenRouter)), 0);
    }

    function testBuy() public {
        // default tester user provides max liquidity
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
            invoiceTokenId,
            address(eurTestToken),
            4_380_000_000,
            4_380_000_000,
            Constants.ZERO_BYTES
        );

        address tester2Address = address(0x2);
        // default user transfers some EURT to tester2
        eurTestToken.transfer(tester2Address, 500_000_000); // 500 EURT

        vm.startPrank(tester2Address);
        eurTestToken.approve(address(permit2), 500_000_000);
        permit2.approve(
            address(eurTestToken),
            address(invoiceTokenRouter),
            500_000_000,
            type(uint48).max // max deadline
        );

        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            false,
            200_000_000, // 200 invoice tokens to buy
            Constants.ZERO_BYTES
        );
        vm.stopPrank();

        // assert invoice tokens were unlocked from router and send to swapper
        assertEq(invoiceToken.balanceOfSlot(address(invoiceTokenRouter), slotId), 4_180_000_000);
        assertEq(invoiceToken.balanceOfSlot(tester2Address, slotId), 200_000_000);

        // assert user spent swap tokens (EURT) 210_199_978 with slippage are needed
        // to cover the asked invoice tokens
        assertEq(eurTestToken.balanceOf(tester2Address), 289_800_022);

        // assert pool manager balance changed
        // - for invoice wrapper tokens
        //   same as router balance of invoice tokens
        address invoiceTokenWrapperAddress = invoiceTokenRouter.getWrapperAddress(invoiceTokenId);
        InvoiceTokenWrapper invoiceTokenWrapper = InvoiceTokenWrapper(invoiceTokenWrapperAddress);
        assertEq(invoiceTokenWrapper.balanceOf(address(poolManager)), 4_180_000_000);
        // - for eur tokens
        //   increased with amount sent from swapper
        assertEq(eurTestToken.balanceOf(address(poolManager)), 4_590_199_978);
    }

    function testSell() public {
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

        address tester2Address = address(0x2);
        address tester3Address = address(0x3);

        // default user transfers some EURT to testers
        eurTestToken.transfer(tester2Address, 370_000_000); // 370 EURT
        eurTestToken.transfer(tester3Address, 250_000_000); // 250 EURT

        // both testers buy invoice tokens with EURT
        vm.startPrank(tester2Address);
        invoiceToken.setApprovalForAll(address(invoiceTokenRouter), true);
        eurTestToken.approve(address(permit2), 370_000_000);
        permit2.approve(
            address(eurTestToken),
            address(invoiceTokenRouter),
            370_000_000,
            type(uint48).max
        );
        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            false,
            300_000_000, // 300 invoice tokens to buy
            Constants.ZERO_BYTES
        );
        vm.stopPrank();
        vm.startPrank(tester3Address);
        invoiceToken.setApprovalForAll(address(invoiceTokenRouter), true);
        eurTestToken.approve(address(permit2), 250_000_000);
        permit2.approve(
            address(eurTestToken),
            address(invoiceTokenRouter),
            250_000_000,
            type(uint48).max
        );
        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            false,
            200_000_000, // 200 invoice tokens to buy
            Constants.ZERO_BYTES
        );
        vm.stopPrank();

        // assert
        // - invoice token balances
        assertEq(invoiceToken.balanceOfSlot(address(invoiceTokenRouter), slotId), 3_880_000_000);
        assertEq(invoiceToken.balanceOfSlot(tester2Address, slotId), 300_000_000);
        assertEq(invoiceToken.balanceOfSlot(tester3Address, slotId), 200_000_000);
        // - EURT balances
        assertEq(eurTestToken.balanceOf(tester2Address), 46_972_092); // ~23 EURT lost to slippage + fees + price impact from its own trade
        assertEq(eurTestToken.balanceOf(tester3Address), 6_896_522); // ~43 EURT lost to slippage + fees + price impact from both trades

        // first buyer sells 200 EURT worth of invoice tokens
        vm.startPrank(tester2Address);
        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            true,
            200_000_000, // 200 EURT to buy
            Constants.ZERO_BYTES
        );
        vm.stopPrank();
        // second buyer sells all his invoice tokens
        vm.startPrank(tester3Address);
        invoiceTokenRouter.swapInvoice(
            slotId,
            address(eurTestToken),
            true,
            222_966_964, // ~223 EURT to buy
            Constants.ZERO_BYTES
        );
        vm.stopPrank();

        // assert
        // - invoice token balances
        assertEq(invoiceToken.balanceOfSlot(address(invoiceTokenRouter), slotId), 4_244_052_271);
        assertEq(invoiceToken.balanceOfSlot(tester2Address, slotId), 135_947_729);
        assertEq(invoiceToken.balanceOfSlot(tester3Address, slotId), 0);
        // - EURT balances
        assertEq(eurTestToken.balanceOf(tester2Address), 246_972_092);
        assertEq(eurTestToken.balanceOf(tester3Address), 229_863_486);

        // assert pool manager balance changed
        // - for invoice wrapper tokens
        //   same as router balance of invoice tokens
        address invoiceTokenWrapperAddress = invoiceTokenRouter.getWrapperAddress(invoiceTokenId);
        InvoiceTokenWrapper invoiceTokenWrapper = InvoiceTokenWrapper(invoiceTokenWrapperAddress);
        assertEq(invoiceTokenWrapper.balanceOf(address(poolManager)), 4_244_052_271);
        // - for eur tokens
        //   amount to cover liquidity left in pool + invoice tokens still held by tester2
        assertEq(eurTestToken.balanceOf(address(poolManager)), 4_523_164_422);

        // remove liquidity to wrap up with smoke test
        vm.startPrank(address(0x1));
        IERC721(address(positionManager)).approve(address(invoiceTokenRouter), positionTokenId);
        invoiceTokenRouter.removeLiquidity(
            positionTokenId,
            0,
            0,
            Constants.ZERO_BYTES
        );
        vm.stopPrank();
    }

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
