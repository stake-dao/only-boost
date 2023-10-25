// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";
import {Vault} from "src/staking/Vault.sol";
import {CRVPoolFactory} from "src/factory/curve/CRVPoolFactory.sol";

contract PoolFactoryTest is Test {
    Vault vaultImplementation;
    CRVPoolFactory poolFactory;

    CRVStrategy proxy;
    CRVStrategy implementation;

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant gaugeImplementation = address(0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9);

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
        proxy = CRVStrategy(payable(_proxy));

        proxy.initialize(address(this));

        vaultImplementation = new Vault();

        poolFactory = new CRVPoolFactory(
            address(proxy),
            REWARD_TOKEN,
            address(vaultImplementation),
            gaugeImplementation
        );

        proxy.setFactory(address(poolFactory));
    }
}
