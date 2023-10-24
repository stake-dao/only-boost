// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

/// @notice Vault implementation for Stake DAO.
/// @dev Deposit LP tokens to Stake DAO and receive sdGauge tokens as a receipt.
contract Vault is ERC20 {
    uint256 public constant DENOMINATOR = 10_000;

    ERC20 public immutable token;

    address public immutable factory;
    address public immutable strategy;
    address public immutable liquidityGauge;

    uint256 public incentiveTokenAmount;

    constructor(address _token, address _liquidityGauge, address _strategy, address _factory)
        ERC20("Stake DAO Vault", "sdVault", ERC20(_token).decimals())
    {
        token = ERC20(_token);

        factory = _factory;
        strategy = _strategy;
        liquidityGauge = _liquidityGauge;
    }

    /// @notice function to deposit a new amount
    /// @param _staker address to stake for
    /// @param _amount amount to deposit
    /// @param _earn earn or not
    function deposit(address _staker, uint256 _amount, bool _earn) public {}

    /// @notice function to withdraw
    /// @param _shares amount to withdraw
    function withdraw(uint256 _shares) public {}

    /// @notice function to withdraw all curve LPs deposited
    function withdrawAll() external {
        withdraw(balanceOf[msg.sender]);
    }

    /// TODO: Do we want this ?
    function shutdown() external {}

    function available() public view returns (uint256) {
        return (token.balanceOf(address(this)) - incentiveTokenAmount);
    }

    function _earn() internal {}
}
