// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "src/curve/CRVStrategy.sol";

import "solady/utils/LibClone.sol";

import {Vault} from "src/base/staking/Vault.sol";
import {IBooster} from "src/base/interfaces/IBooster.sol";
import {RewardReceiver} from "src/base/strategy/RewardReceiver.sol";

import {ConvexMinimalProxyFactory} from "src/curve/fallbacks/ConvexMinimalProxyFactory.sol";
import {ISDLiquidityGauge, IGaugeController, PoolFactory, CRVPoolFactory} from "src/curve/factory/CRVPoolFactory.sol";

contract Deployment is Script, Test {
    CRVPoolFactory poolFactory;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);

    address public constant strategy = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;

    address public constant vaultImplementation = 0x5940611B5d6f16eA670F032f13e8A09567A8dFF5;
    address public constant rewardReceiverImplementation = 0xd24d1Fa18605006D222FBFe8476858b2DFc9A04E;
    address public constant gaugeImplementation = address(0xc1e4775B3A589784aAcD15265AC39D3B3c13Ca3c);

    function run() public {
        vm.broadcast(DEPLOYER);
        poolFactory = new CRVPoolFactory(
            address(strategy),
            REWARD_TOKEN,
            address(vaultImplementation),
            gaugeImplementation,
            address(rewardReceiverImplementation)
        );

        // vm.broadcast(GOVERNANCE);
        // CRVStrategy(payable(strategy)).setFactory(address(poolFactory));

        // vm.broadcast(DEPLOYER);
        // poolFactory.create(326, false, false);

        // vm.broadcast(DEPLOYER);
        // CRVStrategy(payable(strategy)).harvest(0x5AE28c9197a4a6570216fC7e53E7e0221D7A0FEF, false, false, true);

        /// This are the steps to migrate from the strategy to the new.
        /// Next missing steps:
        /// - For each reward distributor, update all distributor for any extra tokens to the strategy.
        /// - Move set the new strategy as governance in the locker.
        /// - Set the new depositor as strategy in the locker.
    }
}
