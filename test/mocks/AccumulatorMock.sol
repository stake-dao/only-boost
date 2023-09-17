// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract AccumulatorMock {
    function depositToken(address token, uint256 amount) external {
        ERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function notifyAll() public {
        // do nothing
    }
}
