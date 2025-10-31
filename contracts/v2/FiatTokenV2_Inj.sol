pragma solidity 0.8.20;

import { FiatTokenV2_2 } from "./FiatTokenV2_2.sol";
import { FiatTokenV1 } from "../v1/FiatTokenV1.sol";
import { AbstractFiatTokenV1 } from "../v1/AbstractFiatTokenV1.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBankModule
 * @notice Interface for Injective's x/bank precompile
 */
interface IBankModule {
    function mint(address, uint256) external payable returns (bool);

    function balanceOf(address, address) external view returns (uint256);

    function burn(address, uint256) external payable returns (bool);

    function transfer(
        address,
        address,
        uint256
    ) external payable returns (bool);

    function totalSupply(address) external view returns (uint256);

    function setMetadata(
        string memory,
        string memory,
        uint8
    ) external payable returns (bool);
}

/**
 * @title FiatToken V2.Inj
 * @notice ERC20 Token backed by Injective bank precompile, based on version 2.2
 */
contract FiatTokenV2_Inj is FiatTokenV2_2 {
    address constant bankPrecompileAddress = 0x0000000000000000000000000000000000000064;
    IBankModule _bank;

    /**
     * @notice Initialize v2.Inj
     */
    function initializeV2_Inj() external payable {
        // solhint-disable-next-line reason-string
        require(_initializedVersion == 3);

        _bank = IBankModule(bankPrecompileAddress);
        bool success = _bank.setMetadata(name, symbol, decimals);
        require(success, "Bank precompile setMetadata failed");

        _initializedVersion = 4;
    }

    function mint(address _to, uint256 _amount)
        external
        whenNotPaused
        onlyMinters
        notBlacklisted(msg.sender)
        notBlacklisted(_to)
        returns (bool)
    {
        require(_to != address(0));
        require(_amount > 0);
        uint256 mintingAllowedAmount = minterAllowed[msg.sender];
        require(_amount <= mintingAllowedAmount);

        uint256 currentReceiverBalance = _balanceOf(_to);
        require(_amount <= type(uint256).max - currentReceiverBalance);
        uint256 _newBalance = currentReceiverBalance + _amount;
        require(_newBalance <= ((1 << 255) - 1));

        _bank.mint(_to, _amount);

        minterAllowed[msg.sender] = mintingAllowedAmount - _amount;
        emit Mint(msg.sender, _to, _amount);
        emit Transfer(address(0), _to, _amount);
        return true;
    }

    function burn(uint256 _amount)
        external
        whenNotPaused
        onlyMinters
        notBlacklisted(msg.sender)
    {
        uint256 balance = _balanceOf(msg.sender);
        require(_amount > 0);
        require(balance >= _amount);

        _bank.burn(msg.sender, _amount);

        emit Burn(msg.sender, _amount);
        emit Transfer(msg.sender, address(0), _amount);
    }

    /**
     * @notice overrides FiatTokenV1
     */
    function balanceOf(address account)
        external
        override(FiatTokenV1, IERC20)
        view
        returns (uint256)
    {
        return _balanceOf(account);
    }

    /**
     * @notice overrides FiatTokenV1
     */
    function totalSupply()
        external
        override(FiatTokenV1, IERC20)
        view
        returns (uint256)
    {
        return _bank.totalSupply(address(this));
    }

    /**
     * @notice overrides FiatTokenV1
     */
    function _balanceOf(address account)
        internal
        override
        view
        returns (uint256)
    {
        return _bank.balanceOf(address(this), account);
    }

    /**
     * @notice overrides FiatTokenV1
     */
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal override(AbstractFiatTokenV1, FiatTokenV1) {
        require(from != address(0));
        require(to != address(0));
        require(value <= _balanceOf(from));

        uint256 currentReceiverBalance = _balanceOf(to);
        require(value <= type(uint256).max - currentReceiverBalance);
        uint256 _newBalance = currentReceiverBalance + value;
        require(_newBalance <= ((1 << 255) - 1));

        _bank.transfer(from, to, value);
        emit Transfer(from, to, value);
    }
}
