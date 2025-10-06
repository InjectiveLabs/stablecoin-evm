# Running Stablecoin USDC via EVM on Injective and Blacklisting

This document describes how to deploy USDC FiatToken on locally running
Injective node and evaluate the blacklisting mechanism.

## Running injectived locally

Build from source and run a local `injectived` node. Please use the following
branch:
[release/v1.16.x-usdc](https://github.com/InjectiveLabs/injective-core/tree/release/v1.16.x-usdc)

```bash
git clone -b release/v1.16.x-usdc org-44571224@github.com:InjectiveLabs/injective-core.git
```

Setup the genesis file:

```bash
cd injective-core
./setup.sh
```

Build and run `injectived`:

```bash
make install
INJHOME="$(pwd)/.injectived" ./injectived.sh
```

Node runs a single validator consensus locally. There are many accounts
pre-funded during `setup.sh`, in this demo we'll focus on these three users:

```
Injective addresses:
user1 - inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r
user2 - inj1jcltmuhplrdcwp7stlr4hlhlhgd4htqhe4c0cs
user3 - inj1dzqd00lfd4y4qy2pxa0dsdwzfnmsu27hgttswz

Eth addresses:
user1 - 0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101
user2 - 0x963EBDf2e1f8DB8707D05FC75bfeFFBa1B5BaC17
user3 - 0x6880D7bfE96D49501141375ED835C24cf70E2bD7
```

We deploy FiatToken using `user1` as deployer and owner (also masterMinter),
will send tokens to `user2` and try to send to blacklisted `user3`. User3 is
blacklisted in
[injective-test.blacklist.remote.json](/injective-test.blacklist.remote.json)
and this is applied during FiatToken deployment.

To use `injectived` client in separate terminal, e.g. list all accounts
available:

```bash
yes 12345678 | injectived --home $INJHOME keys list
```

(passphrase for keyring is `12345678` and `$INJHOME` has to be pointing to valid
`.injectived` from which the node runs).

## Deploying full suite of FiatToken (USDC) contracts

The flow is same as in [README.md](/README.md), there is a pre-filled
environment in [.env](/.env) specfic to locally running node.
`http://localhost:8545` is set as EVM JSON-RPC endpoint of the local node. And
private key is already set from the local keyring generated above.

To deploy all:

```bash
./scripts/demo/deploy-fiat-token.sh
```

NOTE: script
[scripts/deploy/deploy-fiat-token.s.sol](scripts/deploy/deploy-fiat-token.s.sol)
is not working for now, as it requires Injective EVM precompiles support in
Foundry, we're working on that. Meanwhile, there is a manual bash script
[deploy-fiat-token.sh](./scripts/demo/deploy-fiat-token.sh).

```
========================================
Deployment Complete!
========================================

Deployed Contracts:
  SignatureChecker:  0x3D641a2791533B4A0000345eA8d509d01E1ec301
  Implementation:    0x07Aa076883658B7ED99D25b1E6685808372C8fE2
  Proxy:             0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d
  MasterMinter:      0x17cf225bEFBdC683A48DB215305552B3897906F6

Configuration:
  Token Name:     USDC
  Token Symbol:   USDC
  Token Currency: USD
  Token Decimals: 6

Addresses:
  Proxy Admin:            0x963EBDf2e1f8DB8707D05FC75bfeFFBa1B5BaC17
  Master Minter Owner:    0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101
  Owner:                  0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101
  Pauser:                 0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101
  Blacklister:            0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101
```

In the first deployment, the proxy address should be
`0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d`, this can be used fiat token USDC
everywhere now.

## Minting USDC tokens

Let's mint some USDC tokens to the master minter owner (`user1`). Also a bash
script for now, until [mint-some-usdc.s.sol](scripts/demo/mint-some-usdc.s.sol)
is supported on Foundry level.

```bash
./scripts/demo/mint-some-usdc.sh
```

It uses some vars from `.env` file starting from `DEMO_*`, the script is
straigforward, see [mint-some-usdc.sh](scripts/demo/mint-some-usdc.sh).

First after running it, check the new USDC balance of user 1 on EVM side:

```bash
cast --to-base $(cast call 0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d "balanceOf(address)" 0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101) 10

## Expected output:
# 100000000
```

Nice! Let's check the same state "injective's side", using injectived query.
(`$INJHOME` has to be pointing to valid `.injectived` from which the node runs)

```bash
# all balances of user 1
injectived q bank balances inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r

# specifically USDC balance
injectived q bank balance inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d

## Expected output:
# balance:
#   amount: "100000000"
#   denom: erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d
```

The denom of ERC20 token mapped to `x/bank` balance is
`erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d` accordingly. See
[MTS](https://docs.injective.network/developers-evm/multivm-token-standard) for
more detail about how this mapping works. MTS mapping automatically created
during initialization (from EVM's side) and a fee of 1 INJ has been collected.

## Sending USDC tokens

Every time tokens are sent between users on Injective, a permissions module
`x/permissions` is invoked, checking for restrictions. Restrictions are defined
dynamically via namespaces and roles, but the most important feature is that we
can define a namespace for a particular denom (i.e.
`erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d` bank token) and assign an EVM
Hook that will be called every time that denom is transferring via `x/bank`.

For now, let's try to transfer USDC from `user1` to `user2` when no restrictions
are set at all.

### Sending USDC via injectived (Cosmos side)

```bash
# sending 0.001 USDC user1 -> user2
yes 12345678 | injectived --home $INJHOME tx bank send --from user1 inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r inj1jcltmuhplrdcwp7stlr4hlhlhgd4htqhe4c0cs 1000erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d --chain-id injective-1 --gas 300000 --gas-prices 160000000inj -y

# checking user2
injectived q bank balance inj1jcltmuhplrdcwp7stlr4hlhlhgd4htqhe4c0cs erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d

# balance:
#   amount: "1000"
#   denom: erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d
```

### Sending USDC via ERC20 call (EVM side)

```bash
# Transfer 1000 tokens (0.001 USDC with 6 decimals) from user1 to user2
cast send 0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d \
    "transfer(address,uint256)" 0x963EBDf2e1f8DB8707D05FC75bfeFFBa1B5BaC17 1000 \
    --rpc-url http://localhost:8545 \
    --private-key 0x88CBEAD91AEE890D27BF06E003ADE3D4E952427E88F88D31D61D3EF5E5D54305 \
    --legacy \
    --gas-limit 300000 \
    --gas-price 160000000

# Check user2's balance on EVM side
cast --to-base $(cast call 0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d "balanceOf(address)" 0x963EBDf2e1f8DB8707D05FC75bfeFFBa1B5BaC17) 10

## Expected output:
# 2000
```

## Creating a namespace and role, deploying PermissionsHook

### PermissionsHook

Let's start by deploying a PermissionsHook contract.

```bash
./scripts/demo/deploy-permissions-hook.sh
```

The hook must spew something clear about its address:

```
========================================
Deployment Complete!
========================================

Deployed Contract:
  PermissionsHook:  0x366C9837f9A32CC11AC5cAc1602e57b73E6BF784

Configuration:
  FiatToken Address: 0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d
```

Remember the deployed address `0x366C9837f9A32CC11AC5cAc1602e57b73E6BF784`

### Creating namespace

See the config [namespace.json](scripts/demo/namespace.json) to validate the
namespace configuration. Basically we want an admin user, who is able to do
everything on denom, and everyone else, who have most basic `RECEIVE + SEND`
permissions only (via bitmask).

On top of `EVERYBODY` role, we define an EVM hook that will be used to check
restrictions imposed by EVM state, i.e. `PermissionsHook` contract will be
called and can restrict any send, receive, or another operations.

During namespace creation, admin address is validated to be `owner()` of ERC20
token at FiatToken proxy address. This is an important security step, to avoid
front running of namespace creation.

Anyway, let's start blasting:

```bash
# issue a tx creating namespace
echo 12345678 | injectived tx permissions create-namespace \
    --home $INJHOME \
    --from user1 \
    --chain-id injective-1 \
    --gas 300000 \
    --gas-prices 160000000inj \
    -y \
    ./scripts/demo/namespace.json

# validate namespace creation:

injectived q permissions namespaces --chain-id injective-1

# namespaces:
# - actor_roles:
#   - actor: inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r
#     roles:
#     - admin
#   contract_hook: ""
#   denom: erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d
#   evm_hook: 0x366C9837f9A32CC11AC5cAc1602e57b73E6BF784
# ... skipped some ...
#   role_managers:
#   - manager: inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r
#     roles:
#     - EVERYONE
#     - admin
#   role_permissions:
#   - name: EVERYONE
#     permissions: 10
#     role_id: 0
#   - name: admin
#     permissions: 2013265920
#     role_id: 1
```

`contract_hook` corresponds to WASM hook (none), `evm_hook` is the address of
the `PermissionsHook` contract deployed earlier.

### Verify that transfers still work

```bash
# sending 0.001 USDC user1 -> user2
yes 12345678 | injectived --home $INJHOME tx bank send --from user1 inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r inj1jcltmuhplrdcwp7stlr4hlhlhgd4htqhe4c0cs 1000erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d --chain-id injective-1 --gas 300000 --gas-prices 160000000inj -y

# checking user2
injectived q bank balance inj1jcltmuhplrdcwp7stlr4hlhlhgd4htqhe4c0cs erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d

# balance:
#   amount: "3000"
#   denom: erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d
```

### Banning user3

Let's blacklist `user3` on EVM side of USDC, using ETH address. `user1` must
have the blacklister role, so we just reuse the same PK again.

```bash
cast send 0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d \
  "blacklist(address)" \
  0x6880D7bfE96D49501141375ED835C24cf70E2bD7 \
  --rpc-url http://localhost:8545 \
  --private-key 0x88CBEAD91AEE890D27BF06E003ADE3D4E952427E88F88D31D61D3EF5E5D54305 \
  --legacy \
  --gas-limit 300000 \
  --gas-price 160000000

## Output:
# ...
# status               1 (success)
# ...
```

Now let's verify we can't send anything to `user3`!

### Trying to send USDC via injectived (Cosmos side) to a blacklisted address

```bash
# sending 0.001 USDC user1 -> user3
txhash=$(yes 12345678 | injectived --home $INJHOME tx bank send --from user1 inj1cml96vmptgw99syqrrz8az79xer2pcgp0a885r inj1dzqd00lfd4y4qy2pxa0dsdwzfnmsu27hgttswz 1000erc20:0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d --chain-id injective-1 --gas 300000 --gas-prices 160000000inj -y --output json | jq -r '.txhash')

# checking tx status
injectived q tx $txhash

# Expected output:
# ...
# code: 9
# codespace: permissions
# raw_log: 'failed to execute message; message index: 0: transfer is restricted by EVM
#   hook: restricted action'
# ...
```

### Trying to send USDC via ERC20 call (EVM side) to a blacklisted address

```bash
# Transfer 1000 tokens (0.001 USDC with 6 decimals) from user1 to user3
cast send 0xe2F81B30E1D47DFFdBb6aB41Ec5f0572705b026d \
    "transfer(address,uint256)" 0x6880D7bfE96D49501141375ED835C24cf70E2bD7 1000 \
    --rpc-url http://localhost:8545 \
    --private-key 0x88CBEAD91AEE890D27BF06E003ADE3D4E952427E88F88D31D61D3EF5E5D54305 \
    --legacy \
    --gas-limit 300000 \
    --gas-price 160000000

## Expected output:
# status               0 (failed)
# revertReason         Blacklistable: account is blacklisted, data: ...
```

Tada! :tada:

## Conclusion

Let's reiterate what has been demonstrated so far:

1. USDC fiat token deployment, full suite
2. Minting of USDC using master minter pattern
3. Usage of USDC from both Cosmos native and EVM sides
4. Permissions system with EVM Hook support
5. Deployed a namespace enforcing a specific blacklist
6. Blacklist is programmatically defined to match USDC configuration on EVM side
7. Every transfer is checked against restrictions, as imposed by Solidity smart
   contract
