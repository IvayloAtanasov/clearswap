# Clearswap

Smart contracts for tokenizing invoices for Uniswap V4 pools.

*This project development was started during [Uniswap Hook Incubator](https://atrium.academy/uniswap) - Cohort 6.*

## Motivation

Tokenizing Real-World Assets requires having a suitable token standard. But putting assets onchain is often not enough, as they also need to offer at least a similar level of liquidity to their real counterparts. RWA liquidity is often a problem, both regulatory and technically, as many existing liquidity protocols are not suited for the specifics of ownership change that those assets require.

This project showcases one way of tokenizing invoice documents according to [ERC-3525](https://eips.ethereum.org/EIPS/eip-3525) specification and making them compatible for Uniswap V4 pools.

Why invoices?

Invoices have several important qualities that makes them a compelling fit for tokenization:

- They can be fully digitalized, as invoices are documents
- They represent debt, which gives them intrinsic trading value
- They have clear parameters - debtor, debt value, due date
- They can be grouped in tranches (slots) according to a risk classification, using the above parameters and some metadata
- They represent unique asset, but are also divisible by value
- They are suitable for both low and high volume trades

## Components

- 🔄 `InvoiceTokenRouter` - Custom V4 router that needs to be used as interface contract for every pool related action - initialize, add/remove liquidity, swap. Works with PoolManager, PositionManager, uses Permit2 for dynamic ERC-20 permissions.

- 📄 `InvoiceToken` - ERC-3525 semi-fungible tokens. Each tokenId represents a given document and it is placed in a given slot upon minting. Each slot represents a certain risk level, as all tokens under the slot have the same metadata (such as expiration date).
ERC-3525 tokens are fungible, only within the same slot. Token ids can change upon transfer as they are also uniqie per user. The current implementation also further limits transfers, so the tokenId is always linked to the IPFS CID of the original document it was created for.

- 💱 `InvoiceTokenWrapper` - ERC-20 counterpart of InvoiceToken. This token mint/burn is controlled by the router and is used internally in the Uniswap PoolManager as it can only work with ERC-20 tokens. Invoice tokens from the same slot have the same wrapper token. Every wrapper token minted is covered by invoice token locked in the router.

- 🛡️ `InvoicePoolHook` - Validates swaps during execution, according to slot metadata (expiration date). Disables trading after invoice payment due date. Designed to work only with pools from the custom InvoiceTokenRouter.

## Future improvements

- One regulatory requirement is that every time invoice changes its owner, the debtor needs to somehow be notified for the update. This can be done with onchain-offchain notification system. Every time a given tokenId changes it's owner, or a new tokenId is created from shares of a given tokenId an email can be send with all current owners of a given document and their share. As offchain notifiaction goes beyond the scope of the current showcase, it was left out.

- Invoices can be repaid before the due date. In this case we should also disable trading via the hook.

## Installation & Setup

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Git

### Clone and Install Dependencies
```bash
# Clone the repository
git clone <your-repo-url>
cd clearswap

# Install dependencies
forge install

# Build the project
forge build
```

### Configuration
The project uses Foundry with specific settings for Uniswap V4 compatibility:
- Solidity version: 0.8.26
- EVM version: Cancun
- Via IR compilation enabled for complex contracts
- Optimizer enabled to handle contract size limits (EIP-170)

## Running tests

```bash
# all
forge test

# with verbose output
forge test -vvvv

# run single test
forge test -vv --match-test testSell
```

Tests showcase several usage scenarios:

- Initializing a pool for invoice ERC-3525 token of some slot and arbitrary ERC-20 token
- Adding liquidity to pool
- Removing liquidity from pool
- Swapping ERC-3525 tokens for ERC-20 tokens
- Swapping ERC-20 for ERC-3525 tokens
