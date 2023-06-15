// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {CurveStrategy} from "src/CurveStrategy.sol";

contract Handler is Test {
    ERC20 public token;
    CurveStrategy public strategy;

    uint256 public numCalls;

    constructor(CurveStrategy _strategy, ERC20 _token) {
        strategy = _strategy;
        token = _token;
    }

    function deposit(uint256 amount) external {
        ++numCalls;
        deal(address(token), address(this), amount);
        token.approve(address(strategy), amount);
        strategy.deposit(address(token), amount);
    }
}
