// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Vault} from "src/staking/Vault.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {RewardReceiver} from "src/strategy/RewardReceiver.sol";
import {ISDLiquidityGauge, IGaugeController, PoolFactory, CRVPoolFactory} from "src/factory/curve/CRVPoolFactory.sol";

interface IClaimer {
    function claim_rewards(address[] memory _gauge) external;
}

abstract contract Staking_Test is Test {
    using FixedPointMathLib for uint256;

    ILocker public locker;

    Vault vault;
    ISDLiquidityGauge rewardDistributor;

    Vault vaultImplementation;
    RewardReceiver rewardReceiverImplementation;

    CRVPoolFactory poolFactory;

    CRVStrategy strategy;
    CRVStrategy implementation;

    ERC20 public token;
    address public gauge;

    address[] public extraRewardTokens;

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant gaugeImplementation = address(0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9);

    constructor(uint256 _pid) {
        /// Check if the LP token is valid
        (address lpToken,, address _gauge,,,) = IBooster(BOOSTER).poolInfo(_pid);

        gauge = _gauge;
        token = ERC20(lpToken);
    }

    function setUp() public {
        vm.rollFork({blockNumber: 18_383_019});

        /// Deploy Strategy
        implementation = new CRVStrategy(address(this), SD_VOTER_PROXY, VE_CRV, REWARD_TOKEN, MINTER);

        address _proxy = address(new ERC1967Proxy(address(implementation), ""));
        strategy = CRVStrategy(payable(_proxy));

        strategy.initialize(address(this));

        /// Initialize Locker
        locker = ILocker(SD_VOTER_PROXY);

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        vaultImplementation = new Vault();
        rewardReceiverImplementation = new RewardReceiver();

        poolFactory = new CRVPoolFactory(
            address(strategy),
            REWARD_TOKEN,
            address(vaultImplementation),
            gaugeImplementation,
            address(rewardReceiverImplementation)
        );

        strategy.setFactory(address(poolFactory));

        address _vault;
        address _rewardDistributor;

        bool isKilled;
        uint256 weight = IGaugeController(GAUGE_CONTROLLER).get_gauge_weight(gauge);

        try ILiquidityGauge(gauge).is_killed() returns (bool _isKilled) {
            isKilled = _isKilled;
        } catch {}

        if (weight == 0 || isKilled) {
            return;
        } else {
            (_vault, _rewardDistributor) = poolFactory.create(gauge);

            vault = Vault(_vault);
            rewardDistributor = ISDLiquidityGauge(_rewardDistributor);

            /// Approve vault to spend LP tokens
            token.approve(address(vault), type(uint256).max);
        }
    }

    function test_deposit_and_withdraw(bool _doEarn) public {
        if (address(vault) == address(0)) {
            return;
        }

        uint256 amount = 10_000e18;
        vm.assume(amount != 0);

        deal(address(token), address(this), amount);
        /// Approve vault to spend LP tokens
        vault.deposit(address(this), amount, _doEarn);

        assertEq(vault.balanceOf(address(this)), 0);

        if (_doEarn) {
            assertEq(vault.incentiveTokenAmount(), 0);
            assertEq(token.balanceOf(address(vault)), 0);
            assertEq(rewardDistributor.balanceOf(address(this)), amount);
        } else {
            uint256 _incentiveTokenAmount = amount.mulDiv(1, 1000);
            assertEq(token.balanceOf(address(vault)), amount);

            amount -= _incentiveTokenAmount;

            assertEq(vault.incentiveTokenAmount(), _incentiveTokenAmount);
            assertEq(rewardDistributor.balanceOf(address(this)), amount);
        }

        if (_doEarn) {
            /// Need to first skip weeks to harvest Convex.
            skip(1 days);

            strategy.harvest(address(token), false, true);

            skip(1 days);
            rewardDistributor.claim_rewards(address(this));

            try ILiquidityGauge(gauge).is_killed() returns (bool isKilled) {
                if (!isKilled) {
                    /// Simple check to see if we have received rewards.
                    assertGt(ERC20(REWARD_TOKEN).balanceOf(address(rewardDistributor)), 0);
                    assertGt(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
                }
            } catch {
                /// Simple check to see if we have received rewards.
                assertGt(ERC20(REWARD_TOKEN).balanceOf(address(rewardDistributor)), 0);
                assertGt(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
            }
        }

        vault.withdraw(amount);

        assertEq(vault.totalSupply(), 0);
        assertEq(rewardDistributor.totalSupply(), 0);
        assertEq(token.balanceOf(address(this)), amount);
    }
}
