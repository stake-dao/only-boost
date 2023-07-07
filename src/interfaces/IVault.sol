// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface IVault {
    function setCurveStrategy(address _newStrat) external;
}