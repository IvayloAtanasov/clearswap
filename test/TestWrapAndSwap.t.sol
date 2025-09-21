// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SetupTest} from "./SetupTest.t.sol";
import {InvoiceTokenRouter} from "../src/InvoiceTokenRouter.sol";
import {UnsupportedProtocol} from "lib/universal-router/contracts/deploy/UnsupportedProtocol.sol";

contract TestWrapAndSwap is SetupTest {
    InvoiceTokenRouter public invoiceTokenRouter;

    function setUp() public {
        // make msg sender 0x1
        vm.startPrank(address(0x1));

        // existing protocol contracts
        permit2 = deployPermit2();
        poolManager = deployPoolManager();
        positionManager = deployPositionManager(poolManager, permit2);
        stateView = deployStateView(poolManager);

        // test helper contracts
        deployTestTokens();

        // contracts under test
        UnsupportedProtocol unsupportedProtocol = new UnsupportedProtocol();
        invoiceTokenRouter = new InvoiceTokenRouter(
            permit2,
            poolManager,
            positionManager,
            unsupportedProtocol
        );
    }

    function testBasic() public pure {

        assertEq(uint256(1 + 1), uint256(2));

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
    }
}
