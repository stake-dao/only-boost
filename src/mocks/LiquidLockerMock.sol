// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

contract LiquidLockerMock {
    address public strategy;

    error ONLY_STRATEGY();

    constructor(address _strategy) {
        strategy = _strategy;
    }

    function setStrategy(address _strategy) external {
        strategy = _strategy;
    }

    function execute(address to, uint256 value, bytes calldata data) external returns (bool, bytes memory) {
        if (msg.sender != strategy) revert ONLY_STRATEGY();
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }
}
