pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title Test Interface vs Low-Level Calls
 * @notice Demonstrates the difference between interface calls (fail) and low-level calls (work)
 * to the Injective bank precompile
 */

interface IBankModule {
    function setMetadata(
        string memory,
        string memory,
        uint8
    ) external payable returns (bool);
}

contract TestInterfaceVsLowLevel is Script {
    address constant BANK_PRECOMPILE = 0x0000000000000000000000000000000000000064;
    
    function run() external {
        console.log("=== Testing Interface vs Low-Level Calls to Bank Precompile ===");
        console.log("");
        
        // Test 1: Low-level call method (WORKS)
        console.log("1. Testing Low-Level Call Method (WORKS):");
        testLowLevelMethod();
        
        console.log("");
        
        // Test 2: Interface method (FAILS)
        console.log("2. Testing Interface Method (FAILS):");
        testInterfaceMethod();
    }
    
    function testInterfaceMethod() internal {
        IBankModule bank = IBankModule(BANK_PRECOMPILE);
        
        try bank.setMetadata("TestToken", "TEST", 18) returns (bool result) {
            console.log("   [SUCCESS] Interface call succeeded, result:", result);
        } catch Error(string memory reason) {
            console.log("   [FAIL] Interface call failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("   [FAIL] Interface call failed with low-level error");
            console.log("   Error data length:", lowLevelData.length);
            if (lowLevelData.length > 0) {
                console.logBytes(lowLevelData);
            }
        }
    }
    
    function testLowLevelMethod() internal {
        (bool success, bytes memory data) = BANK_PRECOMPILE.call(
            abi.encodeWithSignature("setMetadata(string,string,uint8)", "TestToken", "TEST", 18)
        );
        
        console.log("   Call success:", success);
        console.log("   Data length:", uint256(data.length));
        
        if (success && data.length >= 32) {
            bool result = abi.decode(data, (bool));
            console.log("   [SUCCESS] Low-level call succeeded, result:", result);
        } else if (success && data.length > 0) {
            console.log("   [WARN] Low-level call succeeded but returned unexpected data");
            console.logBytes(data);
        } else if (success) {
            console.log("   [WARN] Low-level call succeeded but returned no data");
        } else {
            console.log("   [FAIL] Low-level call failed");
            if (data.length > 0) {
                console.logBytes(data);
            }
        }
    }
}