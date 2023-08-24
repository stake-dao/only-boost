// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface ISdToken {
    function setOperator(address _operator) external;
    function operator() external returns (address);
}
