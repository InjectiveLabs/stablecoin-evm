#!/bin/bash

################################################################################
# Fiat Token Deployment Script
# This script deploys the complete Fiat Token system including:
# - FiatTokenV2_Inj implementation
# - FiatTokenProxy
# - MasterMinter
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
: ${TOKEN_NAME:?Error: TOKEN_NAME not set}
: ${TOKEN_SYMBOL:?Error: TOKEN_SYMBOL not set}
: ${TOKEN_CURRENCY:?Error: TOKEN_CURRENCY not set}
: ${TOKEN_DECIMALS:?Error: TOKEN_DECIMALS not set}
: ${PROXY_ADMIN_ADDRESS:?Error: PROXY_ADMIN_ADDRESS not set}
: ${MASTER_MINTER_OWNER_ADDRESS:?Error: MASTER_MINTER_OWNER_ADDRESS not set}
: ${OWNER_ADDRESS:?Error: OWNER_ADDRESS not set}
: ${DEPLOYER_PRIVATE_KEY:?Error: DEPLOYER_PRIVATE_KEY not set}
: ${TESTNET_RPC_URL:?Error: TESTNET_RPC_URL not set}
: ${INJ_URL:?Error: INJ_URL not set}

# Optional variables (default to OWNER_ADDRESS)
PAUSER_ADDRESS=${PAUSER_ADDRESS:-$OWNER_ADDRESS}
BLACKLISTER_ADDRESS=${BLACKLISTER_ADDRESS:-$OWNER_ADDRESS}
FIAT_TOKEN_IMPLEMENTATION_ADDRESS=${FIAT_TOKEN_IMPLEMENTATION_ADDRESS:-}

# Use TESTNET_RPC_URL as ETH_URL for consistency in the script
ETH_URL=$TESTNET_RPC_URL

# Deployer account name
DEPLOYER_ACCOUNT="deployer_temp"
DEPLOYER_PASSWORD="temp_password_12345"

# Throwaway address for dummy initialization
THROWAWAY_ADDRESS="0x0000000000000000000000000000000000000001"

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
echo "Fiat Token Deployment"
echo "========================================"
echo ""
echo "Configuration:"
echo "  TOKEN_NAME: $TOKEN_NAME"
echo "  TOKEN_SYMBOL: $TOKEN_SYMBOL"
echo "  TOKEN_CURRENCY: $TOKEN_CURRENCY"
echo "  TOKEN_DECIMALS: $TOKEN_DECIMALS"
echo "  PROXY_ADMIN_ADDRESS: $PROXY_ADMIN_ADDRESS"
echo "  MASTER_MINTER_OWNER_ADDRESS: $MASTER_MINTER_OWNER_ADDRESS"
echo "  OWNER_ADDRESS: $OWNER_ADDRESS"
echo "  PAUSER_ADDRESS: $PAUSER_ADDRESS"
echo "  BLACKLISTER_ADDRESS: $BLACKLISTER_ADDRESS"
echo "  FIAT_TOKEN_IMPLEMENTATION_ADDRESS: ${FIAT_TOKEN_IMPLEMENTATION_ADDRESS:-<will deploy>}"
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

# Step 2: Deploy or use existing FiatTokenV2_Inj implementation
if [ -z "$FIAT_TOKEN_IMPLEMENTATION_ADDRESS" ] || [ "$FIAT_TOKEN_IMPLEMENTATION_ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
    # Step 2a: Deploy SignatureChecker library
    echo "2a) Deploying SignatureChecker library..."
    sig_checker_res=$(forge create contracts/util/SignatureChecker.sol:SignatureChecker \
        --rpc-url $ETH_URL \
        --broadcast \
        --account $DEPLOYER_ACCOUNT \
        --password $DEPLOYER_PASSWORD \
        --legacy \
        --gas-limit 10000000 \
        --gas-price ${GAS_PRICE:-10} \
        --json)

    if [ $? -ne 0 ]; then
        echo "Error deploying SignatureChecker library"
        echo "$sig_checker_res"
        exit 1
    fi

    check_foundry_result "$sig_checker_res"

    sig_checker_address=$(echo "$sig_checker_res" | jq -r '.deployedTo')
    echo "SignatureChecker library deployed at: $sig_checker_address"
    echo ""

    # Step 2b: Deploy FiatTokenV2_Inj implementation with library linking
    echo "2b) Deploying FiatTokenV2_Inj implementation..."
    impl_res=$(forge create contracts/v2/FiatTokenV2_Inj.sol:FiatTokenV2_Inj \
        --rpc-url $ETH_URL \
        --broadcast \
        --account $DEPLOYER_ACCOUNT \
        --password $DEPLOYER_PASSWORD \
        --legacy \
        --gas-limit 10000000 \
        --gas-price ${GAS_PRICE:-10} \
        --libraries contracts/util/SignatureChecker.sol:SignatureChecker:$sig_checker_address \
        --json)

    if [ $? -ne 0 ]; then
        echo "Error deploying implementation"
        echo "$impl_res"
        exit 1
    fi

    check_foundry_result "$impl_res"

    impl_address=$(echo "$impl_res" | jq -r '.deployedTo')
    echo "Implementation deployed at: $impl_address"
    echo ""
else
    impl_address=$FIAT_TOKEN_IMPLEMENTATION_ADDRESS
    echo "2) Using existing implementation at: $impl_address"
    echo ""
fi

# Step 3: Deploy FiatTokenProxy
echo "3) Deploying FiatTokenProxy..."
proxy_res=$(forge create contracts/v1/FiatTokenProxy.sol:FiatTokenProxy \
    --rpc-url $ETH_URL \
    --broadcast \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --legacy \
    --gas-limit 10000000 \
    --gas-price ${GAS_PRICE:-10} \
    --json \
    --constructor-args $impl_address)

if [ $? -ne 0 ]; then
    echo "Error deploying proxy"
    exit 1
fi

check_foundry_result "$proxy_res"

proxy_address=$(echo "$proxy_res" | jq -r '.deployedTo')
echo "Proxy deployed at: $proxy_address"
echo ""

# Step 4: Deploy MasterMinter
echo "4) Deploying MasterMinter..."
master_minter_res=$(forge create contracts/minting/MasterMinter.sol:MasterMinter \
    --rpc-url $ETH_URL \
    --broadcast \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --legacy \
    --gas-limit 10000000 \
    --gas-price ${GAS_PRICE:-10} \
    --json \
    --constructor-args $proxy_address)

if [ $? -ne 0 ]; then
    echo "Error deploying MasterMinter"
    exit 1
fi

check_foundry_result "$master_minter_res"

master_minter_address=$(echo "$master_minter_res" | jq -r '.deployedTo')
echo "MasterMinter deployed at: $master_minter_address"
echo ""

# Step 5: Transfer MasterMinter ownership
echo "5) Transferring MasterMinter ownership..."
transfer_res=$(cast send $master_minter_address \
    "transferOwnership(address)" $MASTER_MINTER_OWNER_ADDRESS \
    --rpc-url $ETH_URL \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error transferring MasterMinter ownership"
    exit 1
fi

check_foundry_result "$transfer_res"
echo "MasterMinter ownership transferred to: $MASTER_MINTER_OWNER_ADDRESS"
echo ""

# Step 6: Change proxy admin
echo "6) Changing proxy admin..."
change_admin_res=$(cast send $proxy_address \
    "changeAdmin(address)" $PROXY_ADMIN_ADDRESS \
    --rpc-url $ETH_URL \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error changing proxy admin"
    exit 1
fi

check_foundry_result "$change_admin_res"
echo "Proxy admin changed to: $PROXY_ADMIN_ADDRESS"
echo ""

# Step 7: Initialize proxy (V1)
echo "7) Initializing proxy (V1)..."
proxy_init_res=$(cast send $proxy_address \
    "initialize(string,string,string,uint8,address,address,address,address)" \
    "$TOKEN_NAME" "$TOKEN_SYMBOL" "$TOKEN_CURRENCY" $TOKEN_DECIMALS \
    $master_minter_address $PAUSER_ADDRESS $BLACKLISTER_ADDRESS $OWNER_ADDRESS \
    --rpc-url $ETH_URL \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 2000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error initializing proxy"
    exit 1
fi

check_foundry_result "$proxy_init_res"
echo "Proxy initialized (V1)"
echo ""

# Step 8: Initialize V2
echo "8) Initializing V2..."
proxy_init_v2_res=$(cast send $proxy_address \
    "initializeV2(string)" "$TOKEN_NAME" \
    --rpc-url $ETH_URL \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error initializing V2"
    exit 1
fi

check_foundry_result "$proxy_init_v2_res"
echo "Proxy initialized (V2)"
echo ""

# Step 9: Initialize V2_1
echo "9) Initializing V2_1..."
proxy_init_v2_1_res=$(cast send $proxy_address \
    "initializeV2_1(address)" $OWNER_ADDRESS \
    --rpc-url $ETH_URL \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error initializing V2_1"
    exit 1
fi

check_foundry_result "$proxy_init_v2_1_res"
echo "Proxy initialized (V2_1)"
echo ""

# Step 10: Initialize V2_2
echo "10) Initializing V2_2..."
proxy_init_v2_2_res=$(cast send $proxy_address \
    "initializeV2_2(address[],string)" "[]" "$TOKEN_SYMBOL" \
    --rpc-url $ETH_URL \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error initializing V2_2"
    exit 1
fi

check_foundry_result "$proxy_init_v2_2_res"
echo "Proxy initialized (V2_2)"
echo ""

# Step 11: Initialize V2_Inj
echo "11) Initializing V2_Inj (with 1 INJ MTS mapping fee)..."
proxy_init_v2_inj_res=$(cast send $proxy_address \
    "initializeV2_Inj()" \
    --rpc-url $ETH_URL \
    --account $DEPLOYER_ACCOUNT \
    --password $DEPLOYER_PASSWORD \
    --json \
    --legacy \
    --gas-limit 1000000 \
    --value 1000000000000000000 \
    --gas-price ${GAS_PRICE:-10})

if [ $? -ne 0 ]; then
    echo "Error initializing V2_Inj"
    exit 1
fi

check_foundry_result "$proxy_init_v2_inj_res"
echo "Proxy initialized (V2_Inj)"
echo ""

# Final summary
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Deployed Contracts:"
echo "  SignatureChecker:  ${sig_checker_address:-<not deployed in this run>}"
echo "  Implementation:    $impl_address"
echo "  Proxy:             $proxy_address"
echo "  MasterMinter:      $master_minter_address"
echo ""
echo "Configuration:"
echo "  Token Name:     $TOKEN_NAME"
echo "  Token Symbol:   $TOKEN_SYMBOL"
echo "  Token Currency: $TOKEN_CURRENCY"
echo "  Token Decimals: $TOKEN_DECIMALS"
echo ""
echo "Addresses:"
echo "  Proxy Admin:            $PROXY_ADMIN_ADDRESS"
echo "  Master Minter Owner:    $MASTER_MINTER_OWNER_ADDRESS"
echo "  Owner:                  $OWNER_ADDRESS"
echo "  Pauser:                 $PAUSER_ADDRESS"
echo "  Blacklister:            $BLACKLISTER_ADDRESS"
echo ""
