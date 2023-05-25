// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

contract EventsAndErrors {
    // --- Enums
    enum MANAGEFEE {
        PERFFEE,
        VESDTFEE,
        ACCUMULATORFEE,
        CLAIMERREWARD
    }

    // --- Structs
    struct Fees {
        uint256 perfFee;
        uint256 accumulatorFee;
        uint256 veSDTFee;
        uint256 claimerRewardFee;
    }

    // --- Events
    event OptimizorSet(address _optimizor);
    event VeSDTProxySet(address _veSDTProxy);
    event AccumulatorSet(address _accumulator);
    event GaugeSet(address _gauge, address _token);
    event Crv3Claimed(uint256 amount, bool notified);
    event VaultToggled(address _vault, bool _newState);
    event RewardsReceiverSet(address _rewardsReceiver);
    event GaugeTypeSet(address _gauge, uint256 _gaugeType);
    event MultiGaugeSet(address _gauge, address _multiGauge);
    event FeeManaged(MANAGEFEE _manageFee, address _gauge, uint256 _fee);
    event Claimed(address _gauge, address _token, uint256 _amount);
    event Deposited(address _gauge, address _token, uint256 _amount);
    event Withdrawn(address _gauge, address _token, uint256 _amount);

    // --- Errors
    error AMOUNT_NULL();
    error ADDRESS_NULL();
    error CLAIM_FAILED();
    error MINT_FAILED();
    error CALL_FAILED();
    error WITHDRAW_FAILED();
    error FEE_TOO_HIGH();
}
