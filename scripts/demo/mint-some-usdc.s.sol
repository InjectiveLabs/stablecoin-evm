pragma solidity 0.8.20;

import "forge-std/console.sol"; // solhint-disable no-global-import, no-console
import { Script } from "forge-std/Script.sol";
import { FiatTokenV2_Inj } from "../../contracts/v2/FiatTokenV2_Inj.sol";
import { MintController } from "../../contracts/minting/MintController.sol";
import { MasterMinter } from "../../contracts/minting/MasterMinter.sol";
import {
    MinterManagementInterface
} from "../../contracts/minting/MinterManagementInterface.sol";

contract MintSomeUSDC is Script {
    address private tokenAddress;
    address private recipient;
    uint256 private amount;
    uint256 private masterMinterOwnerPrivateKey;

    function setUp() public {
        tokenAddress = vm.envAddress("DEMO_TOKEN_ADDRESS");
        recipient = vm.envAddress("DEMO_RECIPIENT_ADDRESS");
        amount = vm.envUint("DEMO_MINT_AMOUNT");
        masterMinterOwnerPrivateKey = vm.envUint(
            "DEMO_MASTER_MINTER_OWNER_PRIVATE_KEY"
        );

        console.log("DEMO_TOKEN_ADDRESS: '%s'", tokenAddress);
        console.log("DEMO_RECIPIENT_ADDRESS: '%s'", recipient);
        console.log("DEMO_MINT_AMOUNT: '%s'", amount);
    }

    function run() external {
        vm.startBroadcast(masterMinterOwnerPrivateKey);

        // Get the FiatToken proxy contract
        FiatTokenV2_Inj fiatToken = FiatTokenV2_Inj(payable(tokenAddress));

        // Get the master minter contract address from the fiat token
        address masterMinterAddress = fiatToken.masterMinter();
        MasterMinter masterMinter = MasterMinter(masterMinterAddress);

        // Configure a controller and minter (using the broadcaster as both controller and minter)
        address controller = vm.addr(masterMinterOwnerPrivateKey);
        address minter = vm.addr(masterMinterOwnerPrivateKey);

        // First configure the controller to manage the minter
        masterMinter.configureController(controller, minter);

        // Then configure the minter with the allowance amount
        masterMinter.configureMinter(amount);

        // Mint tokens to the recipient
        fiatToken.mint(recipient, amount);

        vm.stopBroadcast();

        console.log("Successfully minted %s tokens to %s", amount, recipient);
    }
}
