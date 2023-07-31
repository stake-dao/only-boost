// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface ITokenMinter {
    function mint(address, uint256) external;

    function burn(address, uint256) external;
}
