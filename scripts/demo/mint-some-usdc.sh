#!/bin/bash

################################################################################
# Mint USDC Script
# This script mints USDC tokens by:
# - Configuring a controller in the MasterMinter
# - Configuring a minter with the specified allowance
# - Minting tokens to a recipient address
################################################################################

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

################################################################################
# Configuration from environment variables
################################################################################

# Required variables
: ${DEMO_TOKEN_ADDRESS:?Error: DEMO_TOKEN_ADDRESS not set}
: ${DEMO_RECIPIENT_ADDRESS:?Error: DEMO_RECIPIENT_ADDRESS not set}
: ${DEMO_MINT_AMOUNT:?Error: DEMO_MINT_AMOUNT not set}
: ${DEMO_MASTER_MINTER_OWNER_PRIVATE_KEY:?Error: DEMO_MASTER_MINTER_OWNER_PRIVATE_KEY not set}
: ${TESTNET_RPC_URL:?Error: TESTNET_RPC_URL not set}
: ${INJ_URL:?Error: INJ_URL not set}

# Use TESTNET_RPC_URL as ETH_URL for consistency
ETH_URL=$TESTNET_RPC_URL

# Minter account name
MINTER_ACCOUNT="minter_temp"
MINTER_PASSWORD="temp_password_12345"

################################################################################
# Helper functions
################################################################################

check_foundry_result() {
    res=$1

    eth_tx_hash=$(echo $res | jq -r '.transactionHash')
    sdk_tx_hash=$(cast rpc inj_getTxHashByEthHash $eth_tx_hash | sed -r 's/0x//' | tr -d '"')

    tx_receipt=$(injectived q tx $sdk_tx_hash --node $INJ_URL --output json)
    code=$(echo $tx_receipt | jq -r '.code')
    raw_log=$(echo $tx_receipt | jq -r '.raw_log')

    if [ $code -ne 0 ]; then
        echo "Error: Tx Failed. Code: $code, Log: $raw_log"

        # Get detailed transaction trace for debugging
        echo "Getting transaction trace..."
        cast rpc -r testnet debug_traceTransaction "[\"$eth_tx_hash\",{\"tracer\":\"callTracer\"}]" --raw | jq
        exit 1
    fi
}

################################################################################
# Main minting flow
################################################################################

echo "========================================"
echo "Mint USDC Tokens"
echo "========================================"
echo ""
echo "Configuration:"
echo "  DEMO_TOKEN_ADDRESS: $DEMO_TOKEN_ADDRESS"
echo "  DEMO_RECIPIENT_ADDRESS: $DEMO_RECIPIENT_ADDRESS"
echo "  DEMO_MINT_AMOUNT: $DEMO_MINT_AMOUNT"
echo ""

# Step 1: Import minter wallet
echo "1) Importing minter wallet..."
if cast wallet list | grep -q "$MINTER_ACCOUNT"; then
    echo "Wallet $MINTER_ACCOUNT already exists. Skipping import."
else
    cast wallet import $MINTER_ACCOUNT \
        --unsafe-password "$MINTER_PASSWORD" \
        --private-key "$DEMO_MASTER_MINTER_OWNER_PRIVATE_KEY"
    echo "Wallet imported successfully."
fi
echo ""

# Step 2: Get the MasterMinter address from the FiatToken
echo "2) Getting MasterMinter address from FiatToken..."
master_minter_address=$(cast call $DEMO_TOKEN_ADDRESS \
    "masterMinter()" \
    --rpc-url $ETH_URL | sed 's/0x000000000000000000000000/0x/')
echo "MasterMinter address: $master_minter_address"
echo ""

# Step 3: Get the controller/minter address (the account we're using)
controller_address=$(cast wallet address --account $MINTER_ACCOUNT --password $MINTER_PASSWORD)
minter_address=$controller_address
echo "Controller/Minter address: $controller_address"
echo ""

# Step 4: Configure controller to manage the minter
echo "4) Configuring controller in MasterMinter..."
configure_controller_res=$(cast send $master_minter_address \
    "configureController(address,address)" $controller_address $minter_address \
    --rpc-url $ETH_URL \
    --account $MINTER_ACCOUNT \
    --password $MINTER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error configuring controller"
    exit 1
fi

check_foundry_result "$configure_controller_res"
echo "Controller configured successfully"
echo ""

# Step 5: Configure minter with the allowance amount
echo "5) Configuring minter with allowance..."
configure_minter_res=$(cast send $master_minter_address \
    "configureMinter(uint256)" $DEMO_MINT_AMOUNT \
    --rpc-url $ETH_URL \
    --account $MINTER_ACCOUNT \
    --password $MINTER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error configuring minter"
    exit 1
fi

check_foundry_result "$configure_minter_res"
echo "Minter configured with allowance: $DEMO_MINT_AMOUNT"
echo ""

# Step 6: Mint tokens to the recipient
echo "6) Minting tokens to recipient..."
mint_res=$(cast send $DEMO_TOKEN_ADDRESS \
    "mint(address,uint256)" $DEMO_RECIPIENT_ADDRESS $DEMO_MINT_AMOUNT \
    --rpc-url $ETH_URL \
    --account $MINTER_ACCOUNT \
    --password $MINTER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error minting tokens"
    exit 1
fi

check_foundry_result "$mint_res"
echo "Tokens minted successfully"
echo ""

# Final summary
echo "========================================"
echo "Minting Complete!"
echo "========================================"
echo ""
echo "Successfully minted $DEMO_MINT_AMOUNT tokens to $DEMO_RECIPIENT_ADDRESS"
echo ""
