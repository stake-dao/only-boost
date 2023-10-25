// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";
import {Vault} from "src/staking/Vault.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {CRVPoolFactory} from "src/factory/curve/CRVPoolFactory.sol";

abstract contract PoolFactory_Test is Test {
    ILocker public locker;

    Vault vaultImplementation;
    CRVPoolFactory poolFactory;

    CRVStrategy strategy;
    CRVStrategy implementation;


    ERC20 public token;
    address public gauge;

    address[] public extraRewardTokens;


    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

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
        vm.rollFork({blockNumber: 18_341_841});

        /// Deploy Strategy
        implementation = new CRVStrategy(
            address(this),
            SD_VOTER_PROXY,
            VE_CRV,
            REWARD_TOKEN,
            MINTER
        );

        address _proxy = LibClone.deployERC1967(address(implementation));
        strategy = CRVStrategy(payable(_proxy));

        strategy.initialize(address(this));

        /// Initialize Locker
        locker = ILocker(SD_VOTER_PROXY);

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        vaultImplementation = new Vault();

        poolFactory = new CRVPoolFactory(
            address(strategy),
            REWARD_TOKEN,
            address(vaultImplementation),
            gaugeImplementation
        );

        strategy.setFactory(address(poolFactory));
    }


    function test_deploy_pool() public {
        (address vault, address rewardDistributor) = poolFactory.create(gauge);
    }
}
