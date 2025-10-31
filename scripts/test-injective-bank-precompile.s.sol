pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title Test Bank Precompile
 * @notice Simple test for the Injective bank precompile setMetadata function
 */

interface IBankModule {
    function setMetadata(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external payable returns (bool);
}

contract TestBankPrecompile is Script {
    address constant BANK_PRECOMPILE = 0x0000000000000000000000000000000000000064;
    
    function run() external {
        console.log("Testing Injective Bank Precompile...");
        
        IBankModule bank = IBankModule(BANK_PRECOMPILE);
        bool success = bank.setMetadata("TestToken", "TEST", 18);
        
        console.log("setMetadata call successful:", success);
        
        if (success) {
            console.log("Bank precompile is working correctly!");
        } else {
            console.log("Bank precompile returned false");
        }
    }
}