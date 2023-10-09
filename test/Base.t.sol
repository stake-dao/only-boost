// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "forge-std/Test.sol";

// --- Libraries
import {MockERC20, ERC20} from "solady/test/utils/mocks/MockERC20.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RolesAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

// --- Contracts
import {Optimizor} from "src/Optimizor.sol";
import {CrvDepositor} from "src/CrvDepositor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {Strategy} from "src/Strategy.sol";
import {ConvexFallback} from "src/ConvexFallback.sol";
import {CurveVaultFactory} from "src/CurveVaultFactory.sol";

// --- Mocks
import {AccumulatorMock} from "test/mocks/AccumulatorMock.sol";
import {LiquidityGaugeMock} from "test/mocks/LiquidityGaugeMock.sol";

// --- Interfaces
import {IVault} from "src/interfaces/IVault.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {ISdToken} from "src/interfaces/ISdToken.sol";
import {ICurveVault} from "src/interfaces/ICurveVault.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {ILiquidityGaugeStrat} from "src/interfaces/ILiquidityGaugeStrat.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

abstract contract Base_Test is Test {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 public immutable asset;
    ILiquidityGauge public immutable gauge;

    constructor(address _asset, address _gauge) {
        asset = ERC20(_asset);
        gauge = ILiquidityGauge(_gauge);
    }

    //////////////////////////////////////////////////////
    /// --- TEST VARIABLES
    //////////////////////////////////////////////////////

    MockERC20 public mockToken;
    AccumulatorMock public mockAccumulator;
    LiquidityGaugeMock public mockLiquidityGauge;

    //////////////////////////////////////////////////////
    /// --- CONTRACTS & MOCKS & INTERFACES
    //////////////////////////////////////////////////////

    // --- Roles & Authority
    RolesAuthority public rolesAuthority;

    // --- OnlyBoost
    Optimizor public optimizor;
    CrvDepositor public crvDepositor;
    Strategy public curveStrategy;
    ConvexFallback public convexFallback;
    CurveVaultFactory public curveVaultFactory;

    ILocker public locker;
    IPoolRegistryConvexFrax public POOL_REGISTRY_CONVEX_FRAX;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    IBoosterConvexCurve public constant BOOSTER_CONVEX_CURVE =
        IBoosterConvexCurve(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    address public constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker
    address public constant CONVEX_VOTER_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2; // veCRV

    function setUp() public virtual {
        /// Initialize Locker
        locker = ILocker(LOCKER);

        /// Roles & Authority
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        /// OnlyBoost
        curveStrategy = new Strategy(address(this), rolesAuthority);
        convexFallback = new ConvexFallback(address(this), rolesAuthority, payable(address(curveStrategy)));
        optimizor =
            new Optimizor(address(this), rolesAuthority, payable(address(curveStrategy)), address(convexFallback));

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(curveStrategy)));

        /// Set up
        curveStrategy.setOptimizor(address(optimizor));

        /// Initialize Mocks
        mockToken = new MockERC20("Token", "TKN", 18);
        mockAccumulator = new AccumulatorMock(curveStrategy.curveRewardToken());
        mockLiquidityGauge = new LiquidityGaugeMock(address(mockToken));

        /// Label addresses
        vm.label(address(locker), "Locker");
        vm.label(address(optimizor), "Optimizor");
        vm.label(address(rolesAuthority), "RolesAuthority");
        vm.label(address(convexFallback), "ConvexFallback");
        vm.label(address(curveStrategy), "NewCurveStrategy");
        vm.label(address(BOOSTER_CONVEX_CURVE), "BoosterConvexCurve");
    }

    function _getDepositAmount(address liquidityGauge) internal view returns (uint256 _optimalDeposit) {
        // Cache Stake DAO Liquid Locker veCRV balance
        uint256 veCRVLocker = ERC20(VE_CRV).balanceOf(LOCKER);
        _optimalDeposit = optimizor.optimalAmount(liquidityGauge, veCRVLocker);

        return _optimalDeposit;
    }

    function _checkForConvexMaxBoost(address liquidityGauge) internal view returns (bool) {
        return ILiquidityGauge(liquidityGauge).working_balances(CONVEX_VOTER_PROXY)
            == ILiquidityGauge(liquidityGauge).balanceOf(CONVEX_VOTER_PROXY);
    }

    /// @dev _resetSD is set to true to reset the Stake DAO balance in case of already imbalance.
    function _createDeposit(uint256 _amount, bool _split, bool _resetSD) internal {
        deal(address(asset), address(this), _amount);
        if (_resetSD) deal(address(gauge), address(locker), 0);
        if (_split && _checkForConvexMaxBoost(address(gauge))) {
            /// Mock Calls to `cancel` max boost.
            /// This call is made only to check if the user has max boost.
            vm.mockCall(
                address(gauge), abi.encodeWithSignature("working_balances(address)", CONVEX_VOTER_PROXY), abi.encode(0)
            );
        }

        curveStrategy.deposit({token: address(asset), amount: _amount});
    }
}
