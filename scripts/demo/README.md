# Fiat Token Deployment Demo Scripts

This directory contains scripts for deploying the Fiat Token system and related
contracts to Injective testnet.

## deploy-fiat-token.sh

A bash script for deploying the Fiat Token system using Forge and Cast (direct
deployment without proxy pattern).

### Prerequisites

- Foundry (forge, cast) installed
- `.env` file with required configuration

### Required Environment Variables

Create a `.env` file in the project root with the following variables:

```bash
# Network Configuration
TESTNET_RPC_URL=http://localhost:8545
INJ_URL=http://localhost:26657

# Token Configuration
TOKEN_NAME=USDC
TOKEN_SYMBOL=USDC
TOKEN_CURRENCY=USD
TOKEN_DECIMALS=6

# Deployment Configuration
DEPLOYER_PRIVATE_KEY=0x1234567890123456789012345678901234567890123456789012345678901234

# Contract Addresses
MASTER_MINTER_OWNER_ADDRESS=0x0000000000000000000000000000000000000002
OWNER_ADDRESS=0x0000000000000000000000000000000000000003

# Optional: Will default to OWNER_ADDRESS if not set
# PAUSER_ADDRESS=0x0000000000000000000000000000000000000004
# BLACKLISTER_ADDRESS=0x0000000000000000000000000000000000000005

# Optional: Gas configuration
GAS_PRICE=10
```

### Usage

```bash
# From the project root
./scripts/demo/deploy-fiat-token.sh
```

### What the Script Does

1. **Imports Deployer Wallet**: Imports the private key from
   `DEPLOYER_PRIVATE_KEY` into Cast
2. **Deploys SignatureChecker Library**: Deploys the `SignatureChecker` library
   required by FiatToken
3. **Deploys FiatToken**: Deploys `FiatTokenV2_Inj` contract with library
   linking
4. **Deploys MasterMinter**: Deploys `MasterMinter` contract pointing to the
   FiatToken
5. **Initializes Token**: Calls all initialization functions on the token
   contract:
   - `initialize()` (V1)
   - `initializeV2()`
   - `initializeV2_1()`
   - `initializeV2_2()`
   - `initializeV2_Inj()` (includes 1 INJ for MTS binding fee)
6. **Transfers Ownership**: Transfers MasterMinter ownership to
   `MASTER_MINTER_OWNER_ADDRESS`

### Output

The script will output the addresses of all deployed contracts:

- SignatureChecker library address
- FiatToken contract address
- MasterMinter address

### Error Handling

The script will:

- Exit immediately on any error (`set -e`)
- Check transaction status and fail if transactions revert
- Validate that all required environment variables are set

### Notes

- The script uses `--legacy` flag for EIP-155 compatible transactions
- Transaction receipts are checked using `injectived` for detailed error
  information
- A temporary wallet is created and can be reused across deployments
- The contract is deployed directly without a proxy pattern for simplified
  architecture

## deploy-permissions-hook.sh

A bash script for deploying the PermissionsHook contract that integrates with
Injective's x/permissions module.

### Prerequisites

- Foundry (forge, cast) installed
- `.env` file with required configuration
- A deployed FiatToken contract (use `deploy-fiat-token.sh` first)

### Required Environment Variables

Create a `.env` file in the project root with the following variables:

```bash
# Network Configuration
TESTNET_RPC_URL=http://localhost:8545
INJ_URL=http://localhost:26657

# Deployment Configuration
DEPLOYER_PRIVATE_KEY=0x1234567890123456789012345678901234567890123456789012345678901234

# Contract Addresses
DEMO_TOKEN_ADDRESS=0x... # Address of the deployed FiatToken contract

# Optional: Gas configuration
GAS_PRICE=10
```

### Usage

```bash
# From the project root
./scripts/demo/deploy-permissions-hook.sh
```

### What the Script Does

1. **Imports Deployer Wallet**: Imports the private key from
   `DEPLOYER_PRIVATE_KEY` into Cast
2. **Deploys PermissionsHook**: Deploys `PermissionsHook_Inj` contract with the
   FiatToken address as constructor argument

### Output

The script will output the address of the deployed PermissionsHook contract.

### How It Works

The PermissionsHook contract provides the
`isTransferRestricted(address from, address to, Coin amount)` function that:

- Returns `true` if the FiatToken is paused
- Returns `true` if either the sender or receiver is blacklisted
- Returns `false` otherwise (transfer is allowed)

This hook is designed to be registered with Injective's x/permissions module for
the token's denom.

### Next Steps After Deployment

1. Register the hook with Injective's x/permissions module
2. Configure the namespace for your token denom (e.g., `erc20:0x...`)
3. Test transfer restrictions by pausing the token or blacklisting addresses

### Error Handling

The script will:

- Exit immediately on any error (`set -e`)
- Check transaction status and fail if transactions revert
- Validate that all required environment variables are set

### Notes

- The script uses `--legacy` flag for EIP-155 compatible transactions
- Transaction receipts are checked using `injectived` for detailed error
  information
- No proxy is used - this is a simple contract deployment
