// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract AccumulatorMock {
    address public immutable owner;
    address public immutable _rewardToken;

    constructor(address rewardToken) {
        owner = msg.sender;
        _rewardToken = rewardToken;
    }

    function depositToken(address token, uint256 amount) external {
        ERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    event Notify(address indexed user, uint256 reward);

    function notifyAll() public {
        uint256 _balance = ERC20(_rewardToken).balanceOf(address(this));
        ERC20(_rewardToken).transfer(owner, _balance);
        emit Notify(msg.sender, _balance);
    }
}
