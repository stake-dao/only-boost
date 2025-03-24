// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

/// @notice A contract that allows users to withdraw from a liquidity gauge.
contract WithdrawalOnlyLiquidityGauge {
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

    /// @dev Withdraws from the liquidity gauge on behalf of the user.
    function withdraw(address _token, uint256 _amount, address _receiver) external onlyVault {
        address liquidityGauge = IStrategy(STRATEGY).multiGauges(_token);
        ILiquidityGauge(liquidityGauge).withdraw(_token, _amount, _receiver);
    }

    function deposit(uint256, address) external pure {
        revert SHUTDOWN();
    }
}
