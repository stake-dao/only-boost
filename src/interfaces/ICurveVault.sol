// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface ICurveVault {
    function init(
        address _token,
        address _governance,
        string memory name_,
        string memory symbol_,
        address _curveStrategy
    ) external;

    function setLiquidityGauge(address _liquidityGauge) external;

    function setGovernance(address _governance) external;

    function name() external view returns (string memory);
}
