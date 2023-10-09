// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract LiquidityGaugeMock is ERC20 {
    event LiquidityGaugeDeposit(address token, uint256 amount);

    address public immutable token;

    constructor(address _token)
        ERC20(string(abi.encodePacked("Liquidity Gauge Mock ")), string(abi.encodePacked("LGM-")), 18)
    {
        token = _token;
    }

    function reward_tokens(uint256) external pure returns (address) {
        return address(0);
    }

    function deposit(uint256 amount) external {
        ERC20(token).transferFrom(msg.sender, address(this), amount);

        _mint(msg.sender, amount);

        emit LiquidityGaugeDeposit(address(token), amount);
    }

    function deposit_reward_token(address _token, uint256 amount) external {
        ERC20(_token).transferFrom(msg.sender, address(this), amount);

        emit LiquidityGaugeDeposit(_token, amount);
    }
}
