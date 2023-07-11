// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface ICurveLiquidityGauge {
    function lp_token() external view returns (address);
}
