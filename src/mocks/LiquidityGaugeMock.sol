// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract LiquidityGaugeMock {
    event LiquidityGaugeDeposit(address token, uint256 amount);

    function deposit_reward_token(address token, uint256 amount) external {
        ERC20(token).transferFrom(msg.sender, address(this), amount);

        emit LiquidityGaugeDeposit(token, amount);
    }
}
