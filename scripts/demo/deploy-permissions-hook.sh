#!/bin/bash

################################################################################
# PermissionsHook Deployment Script
# This script deploys the PermissionsHook_Inj contract
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
: ${DEPLOYER_PRIVATE_KEY:?Error: DEPLOYER_PRIVATE_KEY not set}
: ${TESTNET_RPC_URL:?Error: TESTNET_RPC_URL not set}
: ${INJ_URL:?Error: INJ_URL not set}

# Use TESTNET_RPC_URL as ETH_URL for consistency in the script
ETH_URL=$TESTNET_RPC_URL

# Deployer account name
DEPLOYER_ACCOUNT="deployer_temp"
DEPLOYER_PASSWORD="temp_password_12345"

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
# Main deployment flow
################################################################################

echo "========================================"
echo "PermissionsHook Deployment"
echo "========================================"
echo ""
echo "Configuration:"
echo "  DEMO_TOKEN_ADDRESS: $DEMO_TOKEN_ADDRESS"
echo ""

# Step 1: Import deployer wallet
echo "1) Importing deployer wallet..."
if cast wallet list | grep -q "$DEPLOYER_ACCOUNT"; then
    echo "Wallet $DEPLOYER_ACCOUNT already exists. Skipping import."
else
    cast wallet import $DEPLOYER_ACCOUNT \
        --unsafe-password "$DEPLOYER_PASSWORD" \
        --private-key "$DEPLOYER_PRIVATE_KEY"
    echo "Wallet imported successfully."
fi
echo ""

# Step 2: Deploy PermissionsHook_Inj
echo "2) Deploying PermissionsHook_Inj..."
hook_res=$(forge create contracts/v2/PermissionsHook_Inj.sol:PermissionsHook_Inj \
    --rpc-url $ETH_URL \
    --broadcast \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --legacy \
    --gas-limit 5000000 \
    --gas-price ${GAS_PRICE:-10} \
    --json \
    --constructor-args $DEMO_TOKEN_ADDRESS)

if [ $? -ne 0 ]; then
    echo "Error deploying PermissionsHook_Inj"
    echo "$hook_res"
    exit 1
fi

check_foundry_result "$hook_res"

hook_address=$(echo "$hook_res" | jq -r '.deployedTo')
echo "PermissionsHook_Inj deployed at: $hook_address"
echo ""

# Final summary
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Deployed Contract:"
echo "  PermissionsHook:  $hook_address"
echo ""
echo "Configuration:"
echo "  FiatToken Address: $DEMO_TOKEN_ADDRESS"
echo ""
echo "Next Steps:"
echo "  1. Register this hook with Injective's x/permissions module"
echo "  2. Configure the namespace for your token denom"
echo "  3. Test transfer restrictions (pause/blacklist)"
echo ""
