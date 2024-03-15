// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";

import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IVault} from "script/utils/IVault.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RewardDistributors} from "script/utils/RewardDistributors.sol";
import {ISDLiquidityGauge} from "src/interfaces/ISDLiquidityGauge.sol";
import {SafeTransferLib as SafeTransfer} from "solady/utils/SafeTransferLib.sol";

import {ICVXLocker, Optimizer} from "src/optimizer/Optimizer.sol";
import {IBaseRewardPool, ConvexImplementation} from "src/fallbacks/ConvexImplementation.sol";
import {IBooster, ConvexMinimalProxyFactory} from "src/fallbacks/ConvexMinimalProxyFactory.sol";

interface IOldStrategy is IStrategy {
    function multiGauges(address) external view returns (address);
}

contract Deployment is Script, Test, RewardDistributors {
    using FixedPointMathLib for uint256;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    //////////////////////////////////////////////////////
    /// --- CONVEX ADDRESSES
    //////////////////////////////////////////////////////

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    //////////////////////////////////////////////////////
    /// --- VOTER PROXY ADDRESSES
    //////////////////////////////////////////////////////

    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address public constant CONVEX_VOTER_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    //////////////////////////////////////////////////////
    /// --- CURVE ADDRESSES
    //////////////////////////////////////////////////////

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    ILocker locker = ILocker(SD_VOTER_PROXY);

    CRVStrategy public strategy;
    CRVStrategy public stratImplementation;

    Optimizer public optimizer;
    ConvexMinimalProxyFactory public factory;

    /// @notice Implementation contract to clone.
    ConvexImplementation public implementation;

    /// @notice Convex Depositor.
    ConvexImplementation public proxy;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        /// Set the strategy as `strategy` in the locker. This mean the depositor would not work anymore.
        /// TODO: This action requires multisig action. The locker governance is the old strategy.
        /// Now we have the old strategy as `governance` and the new strategy as `strategy`
        vm.broadcast(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        /// 6. For each pool:
        /// . Toggle the vault to the new strategy.
        /// . Set the reward distributor to the new strategy.
        require(rewardDistributors.length == gauges.length, "Invalid length");

        for (uint256 i = 0; i < rewardDistributors.length; i++) {
            IOldStrategy oldStrategy = IOldStrategy(locker.governance());
            require(oldStrategy.multiGauges(gauges[i]) == rewardDistributors[i], "Invalid distributor");

            address token = ILiquidityGauge(gauges[i]).lp_token();
            address vault = ILiquidityGauge(rewardDistributors[i]).staking_token();

            /// Toggle the vault to the new strategy.
            strategy.toggleVault(vault);
            strategy.setGauge(token, gauges[i]);
            strategy.setRewardDistributor(gauges[i], rewardDistributors[i]);

            /// STEPS TO MIGRATE FUNDS FROM OLD STRATEGY TO NEW STRATEGY
            /// USING MULTISIG

            /// Last step is to migrate the funds from the old strategy to the new one.
            /// vm.broadcast(GOVERNANCE);
            /// IVault(vault).setCurveStrategy(address(strategy));

            /// vm.broadcast(GOVERNANCE);
            /// ILiquidityGauge(rewardDistributors[i]).set_reward_distributor(REWARD_TOKEN, address(strategy));
        }

        vm.stopBroadcast();

        /// This are the steps to migrate from the strategy to the new.
        /// Next missing steps:
        /// - For each reward distributor, update all distributor for any extra tokens to the strategy.
        /// - Move set the new strategy as governance in the locker.
        /// - Set the new depositor as strategy in the locker.
    }
}
