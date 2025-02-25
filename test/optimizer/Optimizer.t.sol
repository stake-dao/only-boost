// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "solady/src/utils/LibClone.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import "src/CRVStrategy.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {Optimizer} from "src/optimizer/Optimizer.sol";
import {IConvexToken} from "old_test/interfaces/IConvexToken.sol";

import {SafeTransferLib as SafeTransfer} from "solady/src/utils/SafeTransferLib.sol";
import {IBaseRewardPool, ConvexImplementation} from "src/fallbacks/ConvexImplementation.sol";
import {IBooster, ConvexMinimalProxyFactory} from "src/fallbacks/ConvexMinimalProxyFactory.sol";

contract OptimizerTest is Test {
    using SafeTransfer for ERC20;
    using FixedPointMathLib for uint256;

    ILocker public locker;
    Optimizer public optimizer;

    CRVStrategy public strategy;

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

    function setUp() public virtual {
        vm.rollFork({blockNumber: 21_071_980});
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return ERC20(_token).balanceOf(account);
    }
}
