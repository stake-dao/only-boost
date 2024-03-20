// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "solady/utils/LibClone.sol";

import {Vault} from "src/staking/Vault.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {RewardReceiver} from "src/strategy/RewardReceiver.sol";

import {ConvexMinimalProxyFactory} from "src/fallbacks/ConvexMinimalProxyFactory.sol";

import {ISDLiquidityGauge, IGaugeController, PoolFactory, CRVPoolFactory} from "src/factory/curve/CRVPoolFactory.sol";

contract Deployment is Script, Test {
    Vault vaultImplementation;
    CRVPoolFactory poolFactory;
    RewardReceiver rewardReceiverImplementation;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    address public constant gaugeImplementation = address(0x08d36c723b8213122f678025C2D9eb1Ec7Ab8F9D);

    //////////////////////////////////////////////////////
    /// --- VOTER PROXY ADDRESSES
    //////////////////////////////////////////////////////

    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    address public constant strategy = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        vaultImplementation = new Vault();
        rewardReceiverImplementation = new RewardReceiver();

        poolFactory = new CRVPoolFactory(
            address(strategy),
            REWARD_TOKEN,
            address(vaultImplementation),
            gaugeImplementation,
            address(rewardReceiverImplementation)
        );

        vm.stopBroadcast();

        /// This are the steps to migrate from the strategy to the new.
        /// Next missing steps:
        /// - For each reward distributor, update all distributor for any extra tokens to the strategy.
        /// - Move set the new strategy as governance in the locker.
        /// - Set the new depositor as strategy in the locker.
    }
}
