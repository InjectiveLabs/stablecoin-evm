pragma solidity 0.8.20;

import { FiatTokenV2_Inj } from "./FiatTokenV2_Inj.sol";

library Cosmos {
    struct Coin {
        uint256 amount;
        string denom;
    }
}

/**
 * @title IPermissionsHook
 * @notice Interface for Injective x/permission module hook caller
 * @dev This interface is expected by Injective's x/permission module to validate token transfers
 *      The module calls isTransferRestricted() before any token transfer to check if it should be allowed
 *      Returns true if transfer should be restricted/blocked, false if transfer is allowed
 */
interface IPermissionsHook {
    function isTransferRestricted(
        address from,
        address to,
        Cosmos.Coin calldata amount
    ) external view returns (bool);
}

contract PermissionsHook_Inj is IPermissionsHook {
    FiatTokenV2_Inj public immutable fiatToken;

    constructor(address _fiatToken) {
        require(_fiatToken != address(0), "PermissionsHook: fiatToken cannot be zero address");
        fiatToken = FiatTokenV2_Inj(_fiatToken);
    }

    function isTransferRestricted(
        address _from,
        address _to,
        Cosmos.Coin calldata /* _amount */
    ) external view returns (bool) {
        if (fiatToken.paused()) {
            return true;
        } else if (fiatToken.isBlacklisted(_from) || fiatToken.isBlacklisted(_to)) {
            return true;
        }

        return false;
    }
}
