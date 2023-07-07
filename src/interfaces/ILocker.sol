// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface ILocker {
    function strategy() external view returns (address);

    function governance() external view returns (address);

    function setStrategy(address) external;

    function execute(address, uint256, bytes calldata) external returns (bool, bytes memory);

    function increaseAmount(uint256 _value) external;
}
