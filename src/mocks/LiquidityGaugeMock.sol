// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract LiquidityGaugeMock is ERC20 {
    event LiquidityGaugeDeposit(address token, uint256 amount);

    ERC20 public immutable token;

    constructor(ERC20 _token)
        ERC20(
            string(abi.encodePacked("Liquidity Gauge Mock ", _token.name())),
            string(abi.encodePacked("LGM-", _token.symbol())),
            _token.decimals()
        )
    {
        token = _token;
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);

        _mint(msg.sender, amount);

        emit LiquidityGaugeDeposit(address(token), amount);
    }

    function deposit_reward_token(address _token, uint256 amount) external {
        ERC20(_token).transferFrom(msg.sender, address(this), amount);

        emit LiquidityGaugeDeposit(_token, amount);
    }
}
