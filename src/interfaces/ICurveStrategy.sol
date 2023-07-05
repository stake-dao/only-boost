// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface ICurveStrategy {
    struct Fees {
        uint256 perfFee;
        uint256 accumulatorFee;
        uint256 veSDTFee;
        uint256 claimerRewardFee;
    }

    enum MANAGEFEE {
        PERFFEE,
        VESDTFEE,
        ACCUMULATORFEE,
        CLAIMERREWARD
    }

    function gauges(address gauge) external view returns (address);
    function getFeesAndReceiver(address gauge) external view returns (Fees memory, address, address, address);
}
