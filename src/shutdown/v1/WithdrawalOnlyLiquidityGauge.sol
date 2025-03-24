// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IVault} from "src/interfaces/IVault.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice A contract that allows users to withdraw from a liquidity gauge.
contract WithdrawalOnlyLiquidityGauge {
    using SafeERC20 for IERC20;

    /// @notice Address of the strategy.
    /// @dev It contains most of the storage of the strategy.
    address public constant STRATEGY = 0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54;

    /// @notice Error when the caller is not the vault
    error ONLY_VAULT();

    /// @notice Error when the gauge is not found
    error SHUTDOWN();

    modifier onlyVault() {
        if (!IStrategy(STRATEGY).vaults(msg.sender)) revert ONLY_VAULT();
        _;
    }

    function balanceOf(address _account) external view onlyVault returns (uint256) {
        address token = IVault(msg.sender).token();
        address liquidityGauge = IStrategy(STRATEGY).sdGauges(token);
        return ILiquidityGauge(liquidityGauge).balanceOf(_account);
    }

    /// @dev Withdraws from the liquidity gauge on behalf of the user.
    function withdraw(uint256 amount, address receiver, bool claim) external onlyVault {
        address token = IVault(msg.sender).token();
        address liquidityGauge = IStrategy(STRATEGY).sdGauges(token);
        ILiquidityGauge(liquidityGauge).withdraw(amount, receiver, claim);

        IERC20(msg.sender).safeTransfer(msg.sender, amount);
    }

    function deposit(uint256, address) external pure {
        revert SHUTDOWN();
    }
}
