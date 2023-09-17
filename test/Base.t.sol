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
import {CurveStrategy} from "src/CurveStrategy.sol";
import {ConvexFallback} from "src/ConvexFallback.sol";
import {CurveVaultFactory} from "src/CurveVaultFactory.sol";

// --- Mocks
import {AccumulatorMock} from "src/mocks/AccumulatorMock.sol";
import {LiquidityGaugeMock} from "src/mocks/LiquidityGaugeMock.sol";

// --- Interfaces
import {IVault} from "src/interfaces/IVault.sol";
import {IVeCRV} from "src/interfaces/IVeCRV.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {ISdToken} from "src/interfaces/ISdToken.sol";
import {ICurveVault} from "src/interfaces/ICurveVault.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {IFraxUnifiedFarm} from "src/interfaces/IFraxUnifiedFarm.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {ILiquidityGaugeStrat} from "src/interfaces/ILiquidityGaugeStrat.sol";
import {ICurveLiquidityGauge} from "src/interfaces/ICurveLiquidityGauge.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

abstract contract Base_Test is Test {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////
    /// --- TEST VARIABLES
    //////////////////////////////////////////////////////

    MockERC20 public mockToken;
    LiquidityGaugeMock public mockLiquidityGauge;

    //////////////////////////////////////////////////////
    /// --- CONTRACTS & MOCKS & INTERFACES
    //////////////////////////////////////////////////////

    // --- Roles & Authority
    RolesAuthority public rolesAuthority;

    // --- OnlyBoost
    Optimizor public optimizor;
    CrvDepositor public crvDepositor;
    CurveStrategy public curveStrategy;
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
        curveStrategy = new CurveStrategy(address(this), rolesAuthority);
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
        mockLiquidityGauge = new LiquidityGaugeMock(address(mockToken));

        /// Label addresses
        vm.label(address(locker), "Locker");
        vm.label(address(optimizor), "Optimizor");
        vm.label(address(rolesAuthority), "RolesAuthority");
        vm.label(address(convexFallback), "ConvexFallback");
        vm.label(address(curveStrategy), "NewCurveStrategy");
        vm.label(address(BOOSTER_CONVEX_CURVE), "BoosterConvexCurve");
    }
}
