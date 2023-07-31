// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

// --- Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RolesAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

// --- Contracts
import {Optimizor} from "src/Optimizor.sol";
import {CrvDepositor} from "src/CrvDepositor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {CurveStrategy} from "src/CurveStrategy.sol";
import {CurveVaultFactory} from "src/CurveVaultFactory.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

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

contract BaseTest is Test {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////
    /// --- CONTRACTS & MOCKS & INTERFACES
    //////////////////////////////////////////////////////
    // --- Contracts
    Optimizor public optimizor;
    CrvDepositor public crvDepositor;
    CurveStrategy public curveStrategy;
    RolesAuthority public rolesAuthority;
    CurveVaultFactory public curveVaultFactory;
    FallbackConvexCurve public fallbackConvexCurve;

    // --- Mocks
    AccumulatorMock public accumulatorMock;
    LiquidityGaugeMock public liquidityGaugeMockCRV3;
    LiquidityGaugeMock public liquidityGaugeMockCNC_ETH;
    LiquidityGaugeMock public liquidityGaugeMockSTETH_ETH;
    LiquidityGaugeMock public liquidityGaugeMockALUSD_FRAXBP;

    // --- Interfaces
    ILocker public locker;
    IBoosterConvexFrax public BOOSTER_CONVEX_FRAX;
    IBoosterConvexCurve public BOOSTER_CONVEX_CURVE;
    IPoolRegistryConvexFrax public POOL_REGISTRY_CONVEX_FRAX;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUABLES
    //////////////////////////////////////////////////////
    // --- Classic tokens ERC20
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant CNC = ERC20(0x9aE380F0272E2162340a5bB646c354271c0F5cFC);
    ERC20 public constant LDO = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 public constant FXS = ERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);

    // --- Curve LP tokens ERC20
    ERC20 public constant CRV3 = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    ERC20 public constant EUR3 = ERC20(0xb9446c4Ef5EBE66268dA6700D26f96273DE3d571);
    ERC20 public constant CNC_ETH = ERC20(0xF9835375f6b268743Ea0a54d742Aa156947f8C06);
    ERC20 public constant SDT_ETH = ERC20(0x6359B6d3e327c497453d4376561eE276c6933323);
    ERC20 public constant STETH_ETH = ERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    ERC20 public constant SDCRV_CRV = ERC20(0xf7b55C3732aD8b2c2dA7c24f30A69f55c54FB717);
    ERC20 public constant UZD_FRAXBP = ERC20(0x68934F60758243eafAf4D2cFeD27BF8010bede3a);
    ERC20 public constant COIL_FRAXBP = ERC20(0xb85010193FD15aF8390dbD62790Da70F46c1126B);
    ERC20 public constant ALUSD_FRAXBP = ERC20(0xB30dA2376F63De30b42dC055C93fa474F31330A5);

    // --- Curve Gauges address
    address public constant GAUGE_CRV3 = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;
    address public constant GAUGE_EUR3 = 0x1E212e054d74ed136256fc5a5DDdB4867c6E003F;
    address public constant GAUGE_CNC_ETH = 0x5A8fa46ebb404494D718786e55c4E043337B10bF;
    address public constant GAUGE_SDT_ETH = 0x60355587a8D4aa67c2E64060Ab36e566B9bCC000;
    address public constant GAUGE_STETH_ETH = 0x182B723a58739a9c974cFDB385ceaDb237453c28;
    address public constant GAUGE_SDCRV_CRV = 0x663FC22e92f26C377Ddf3C859b560C4732ee639a;
    address public constant GAUGE_UZD_FRAXBP = 0xBdCA4F610e7101Cc172E2135ba025737B99AbD30;
    address public constant GAUGE_COIL_FRAXBP = 0x06B30D5F2341C2FB3F6B48b109685997022Bd272;
    address public constant GAUGE_ALUSD_FRAXBP = 0x740BA8aa0052E07b925908B380248cb03f3DE5cB;
    address public constant GAUGE_SWETH_FXETH = 0xE6A9fd148Ad624a5A8700c6366e23E3cD308DFcB;

    // --- Stake DAO Vault address
    IVault public constant VAULT_3CRV = IVault(0xb9205784b05fbe5b5298792A24C2CB844B7dc467);
    IVault public constant VAULT_SDT_ETH = IVault(0x1513b44A589FFc76d0727968eB55dA4110B39422);
    IVault public constant VAULT_SDCRV_CRV = IVault(0xd6415fF2639835300Ab947Fe67BAd6F0B31400c1);
    IVault public constant VAULT_UZD_FRAXBP = IVault(0xbc61f6973cE564eFFB16Cd79B5BC3916eaD592E2);

    // --- Lockers address
    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80; // Convex CRV Locker
    address public constant LOCKER_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2; // CRV Locker

    // --- Users address
    address public immutable ALICE = makeAddr("Alice");
    address public constant MS_STAKEDAO = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public constant DEPLOYER_007 = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    // --- Fees amounts in basis points
    uint256 public constant FEE_PERF = 100; // 1%
    uint256 public constant FEE_ACCU = 100; // 1%
    uint256 public constant FEE_VESDT = 100; // 1%
    uint256 public constant FEE_CLAIM = 100; // 1%

    // --- Usefull constants
    uint256 public constant REF_AMOUNT = 1_000e18;
    uint256 public constant MAX = type(uint256).max;

    // --- Fork block numbers
    uint256 public constant FORK_BLOCK_NUMBER_1 = 17700000;
    uint256 public constant FORK_BLOCK_NUMBER_2 = 17326000; // DO NOT TOUCH IT !!
    uint256 public constant FORK_BLOCK_NUMBER_3 = 17323000; // DO NOT TOUCH IT !!

    uint256 public forkId1;
    uint256 public forkId2;
    uint256 public forkId3;

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    // --- Mapings for test purpose only
    mapping(address => address) public gauges;
    mapping(address => address) public vaults;
    mapping(address => address) public liquidityGaugeMocks;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor() {
        _labelAddress();
        // Set mapping for gauges
        gauges[address(CRV3)] = GAUGE_CRV3;
        gauges[address(EUR3)] = GAUGE_EUR3;
        gauges[address(CNC_ETH)] = GAUGE_CNC_ETH;
        gauges[address(ALUSD_FRAXBP)] = GAUGE_ALUSD_FRAXBP;
        gauges[address(STETH_ETH)] = GAUGE_STETH_ETH;
        gauges[address(COIL_FRAXBP)] = GAUGE_COIL_FRAXBP;
        gauges[address(SDCRV_CRV)] = GAUGE_SDCRV_CRV;
        gauges[address(SDT_ETH)] = GAUGE_SDT_ETH;
        gauges[address(UZD_FRAXBP)] = GAUGE_UZD_FRAXBP;

        // Set mappings for vaults
        vaults[address(SDCRV_CRV)] = address(VAULT_SDCRV_CRV);
        vaults[address(SDT_ETH)] = address(VAULT_SDT_ETH);
        vaults[address(CRV3)] = address(VAULT_3CRV);
        vaults[address(UZD_FRAXBP)] = address(VAULT_UZD_FRAXBP);
    }

    //////////////////////////////////////////////////////
    /// --- HELPER FUNCTIONS
    //////////////////////////////////////////////////////
    function _afterDeployment() internal {
        curveStrategy.setOptimizor(address(optimizor));
        // Setup contracts
        locker = ILocker(LOCKER);
        BOOSTER_CONVEX_CURVE = IBoosterConvexCurve(fallbackConvexCurve.BOOSTER_CONVEX_CURVE());

        _labelContract();
        // Add all curve gauges
        curveStrategy.setGauge(address(CRV3), GAUGE_CRV3);
        curveStrategy.setGauge(address(CNC_ETH), GAUGE_CNC_ETH);
        curveStrategy.setGauge(address(STETH_ETH), GAUGE_STETH_ETH);
        curveStrategy.setGauge(address(ALUSD_FRAXBP), GAUGE_ALUSD_FRAXBP);
        curveStrategy.setGauge(address(COIL_FRAXBP), GAUGE_COIL_FRAXBP);
        curveStrategy.setGauge(address(SDCRV_CRV), GAUGE_SDCRV_CRV);

        // Add all stake dao gauges
        curveStrategy.setMultiGauge(gauges[address(CRV3)], address(liquidityGaugeMockCRV3));
        curveStrategy.setMultiGauge(gauges[address(CNC_ETH)], address(liquidityGaugeMockCNC_ETH));
        curveStrategy.setMultiGauge(gauges[address(ALUSD_FRAXBP)], address(liquidityGaugeMockALUSD_FRAXBP));
        curveStrategy.setMultiGauge(gauges[address(STETH_ETH)], address(liquidityGaugeMockSTETH_ETH));

        // Set gauge types
        curveStrategy.setLGtype(gauges[address(CRV3)], 1);
        curveStrategy.setLGtype(gauges[address(CNC_ETH)], 0);
        curveStrategy.setLGtype(gauges[address(STETH_ETH)], 0);
        curveStrategy.setLGtype(gauges[address(ALUSD_FRAXBP)], 0);

        // Toggle vault
        curveStrategy.toggleVault(vaults[address(CRV3)]);

        // Set gauge mocks
        liquidityGaugeMocks[address(CRV3)] = address(liquidityGaugeMockCRV3);
        liquidityGaugeMocks[address(CNC_ETH)] = address(liquidityGaugeMockCNC_ETH);
        liquidityGaugeMocks[address(STETH_ETH)] = address(liquidityGaugeMockSTETH_ETH);
        liquidityGaugeMocks[address(ALUSD_FRAXBP)] = address(liquidityGaugeMockALUSD_FRAXBP);

        // Set fees
        address[] memory tokens = new address[](20);
        tokens[0] = address(CRV3);
        tokens[1] = address(ALUSD_FRAXBP);
        tokens[2] = address(CNC_ETH);
        tokens[3] = address(STETH_ETH);
        tokens[4] = address(COIL_FRAXBP);

        uint256 len = tokens.length;
        for (uint8 i; i < len; ++i) {
            address token = tokens[i];
            if (token == address(0)) break;

            curveStrategy.manageFee(CurveStrategy.MANAGEFEE.PERFFEE, gauges[address(token)], FEE_PERF);
            curveStrategy.manageFee(CurveStrategy.MANAGEFEE.VESDTFEE, gauges[address(token)], FEE_VESDT);
            curveStrategy.manageFee(CurveStrategy.MANAGEFEE.ACCUMULATORFEE, gauges[address(token)], FEE_ACCU);
            curveStrategy.manageFee(CurveStrategy.MANAGEFEE.CLAIMERREWARD, gauges[address(token)], FEE_CLAIM);
        }

        // Grant public access to claim function for curve strategy
        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.claim.selector, true);
        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.claim3Crv.selector, true);

        // Grant access to deposit/withdraw function for optimizor to curveStrategy
        rolesAuthority.setRoleCapability(1, address(optimizor), Optimizor.optimizeDeposit.selector, true);
        rolesAuthority.setRoleCapability(2, address(optimizor), Optimizor.optimizeWithdraw.selector, true);
        rolesAuthority.setUserRole(address(curveStrategy), 1, true);
        rolesAuthority.setUserRole(address(curveStrategy), 2, true);

        // Grant access to deposit/withdraw/claim function for fallback convex curve to curveStrategy
        fallbackConvexCurve.setAuthority(rolesAuthority);
        rolesAuthority.setRoleCapability(1, address(fallbackConvexCurve), FallbackConvexCurve.deposit.selector, true);
        rolesAuthority.setRoleCapability(2, address(fallbackConvexCurve), FallbackConvexCurve.withdraw.selector, true);
        rolesAuthority.setRoleCapability(
            3, address(fallbackConvexCurve), FallbackConvexCurve.claimRewards.selector, true
        );
        rolesAuthority.setUserRole(address(curveStrategy), 1, true);
        rolesAuthority.setUserRole(address(curveStrategy), 2, true);
        rolesAuthority.setUserRole(address(curveStrategy), 3, true);
    }

    function _labelAddress() internal {
        // Classic Tokens
        _labelNonZeroAddress(address(CRV), "CRV");
        _labelNonZeroAddress(address(CNC), "CNC");
        _labelNonZeroAddress(address(LDO), "LDO");
        _labelNonZeroAddress(address(CVX), "CVX");
        _labelNonZeroAddress(address(FXS), "FXS");

        // LP Tokens
        _labelNonZeroAddress(address(CRV3), "CRV3");
        _labelNonZeroAddress(address(EUR3), "EUR3");
        _labelNonZeroAddress(address(CNC_ETH), "CNC_ETH");
        _labelNonZeroAddress(address(STETH_ETH), "STETH_ETH");
        _labelNonZeroAddress(address(COIL_FRAXBP), "COIL_FRAXBP");
        _labelNonZeroAddress(address(ALUSD_FRAXBP), "ALUSD_FRAXBP");

        // Gauge addresses
        _labelNonZeroAddress(GAUGE_CRV3, "GAUGE_CRV3");
        _labelNonZeroAddress(GAUGE_EUR3, "GAUGE_EUR3");
        _labelNonZeroAddress(GAUGE_CNC_ETH, "GAUGE_CNC_ETH");
        _labelNonZeroAddress(GAUGE_STETH_ETH, "GAUGE_STETH_ETH");
        _labelNonZeroAddress(GAUGE_COIL_FRAXBP, "GAUGE_COIL_FRAXBP");
        _labelNonZeroAddress(GAUGE_ALUSD_FRAXBP, "GAUGE_ALUSD_FRAXBP");

        // Vaults
        _labelNonZeroAddress(address(VAULT_3CRV), "VAULT_3CRV");

        _labelNonZeroAddress(MS_STAKEDAO, "MS_STAKEDAO");
        _labelNonZeroAddress(DEPLOYER_007, "DEPLOYER_007");
    }

    function _labelContract() internal {
        vm.label(address(rolesAuthority), "RolesAuthority");
        vm.label(address(curveStrategy), "NewCurveStrategy");
        vm.label(address(curveStrategy.optimizor()), "Optimizor");
        vm.label(address(fallbackConvexCurve), "FallbackConvexCurve");
        vm.label(address(locker), "Locker");
        vm.label(address(BOOSTER_CONVEX_CURVE), "BoosterConvexCurve");

        // Mocks
        _labelNonZeroAddress(address(accumulatorMock), "AccumulatorMock");
        _labelNonZeroAddress(address(liquidityGaugeMockCRV3), "LiquidityGaugeMockCRV3");
        _labelNonZeroAddress(address(liquidityGaugeMockCNC_ETH), "LiquidityGaugeMockCNC_ETH");
        _labelNonZeroAddress(address(liquidityGaugeMockSTETH_ETH), "LiquidityGaugeMockSTETH_ETH");
        _labelNonZeroAddress(address(liquidityGaugeMockALUSD_FRAXBP), "LiquidityGaugeMockALUSD_FRAXBP");
    }

    function _labelNonZeroAddress(address _address, string memory _str) internal {
        if (_address != address(0)) vm.label(_address, _str);
    }

    function _addCOIL_FRAXBPOnConvexFrax() internal {
        // This need to be call at block.number 17326000, using following tx
        // https://etherscan.io/tx/0xbcc25272dad48329ed963991f156b929b28ee171e4ad157e2d9b749f3d85eb7b
        // Add all the stuff for ConvexFrax
        vm.prank(0x947B7742C403f20e5FaCcDAc5E092C943E7D0277); // Convex Deployer
        BOOSTER_CONVEX_FRAX.addPool(
            0x7D54C53e6940E88a7ac1970490DAFbBF85D982f4,
            0x39cd4db6460d8B5961F73E997E86DdbB7Ca4D5F6,
            0xa5B6f8Ec4122c5Fe0dBc4Ead8Bfe66A412aE427C
        );
    }

    //////////////////////////////////////////////////////
    /// --- TESTS SECTIONS
    //////////////////////////////////////////////////////
    // --- Mutative functions helper
    function _deposit(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex, uint256 timejump) internal {
        skip(timejump);
        _deposit(token, amountStakeDAO, amountConvex);
    }

    function _deposit(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex) internal {
        uint256 totalAmount = amountStakeDAO + amountConvex;

        // Deal token to this contract
        deal(address(token), address(this), totalAmount);
        // Sometimes deal cheatcode doesn't work, so we check balance
        assert(token.balanceOf(address(this)) == totalAmount);

        // Approve token to strategy
        token.safeApprove(address(curveStrategy), totalAmount);

        // Deposit token
        curveStrategy.deposit(address(token), totalAmount);
    }

    function _withdraw(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex, uint256 timejump) internal {
        skip(timejump);
        // Withdraw token
        curveStrategy.withdraw(address(token), amountStakeDAO + amountConvex);
    }

    function _claimLiquidLocker(ERC20 token, uint256 timejump) internal {
        // Timejump 1 week
        skip(timejump);

        // === CLAIM PROCESS === //
        vm.prank(ALICE);
        curveStrategy.claim(address(token));
    }

    function _optimizedDepositReturnedValueAfter4And7Days(ERC20 token) internal {
        // Toggle using last optimization
        optimizor.toggleUseLastOptimization();

        // Call the optimize deposit
        (, uint256[] memory valuesBefore) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], 10_000_000e18);

        skip(4 days);

        // Call the optimize deposit
        (, uint256[] memory valuesAfter) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], 10_000_000e18);

        assertEq(valuesBefore[0], valuesAfter[0], "0");
        assertEq(valuesBefore[1], valuesAfter[1], "1");

        // Skip 4 extra days, now cachePeriod is over, need to calcul again
        skip(7 days);

        // Call the optimize deposit
        (, valuesAfter) = optimizor.optimizeDeposit(address(token), gauges[address(token)], 10_000_000e18);
        assertTrue(valuesBefore[0] != valuesAfter[0], "3");
        assertTrue(valuesBefore[1] != valuesAfter[1], "4.2");
    }

    function _optimizedDepositReturnedValueAfterCRVLock(ERC20 token) internal {
        // Toggle using last optimization
        optimizor.toggleUseLastOptimization();

        // Call the optimize deposit
        (, uint256[] memory valuesBefore) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], 10_000_000e18);
        uint256 crvLockBefore = optimizor.cacheVeCRVLockerBalance();

        // Liquid Locker lock less CRV than needed to bypass threshold
        uint256 amountToBypassThreshold =
            ERC20(LOCKER_CRV).balanceOf(LOCKER).mulWadDown(optimizor.veCRVDifferenceThreshold());

        deal(address(CRV), address(this), amountToBypassThreshold / 2);
        CRV.safeTransfer(address(LOCKER), amountToBypassThreshold / 2);
        vm.prank(ILocker(LOCKER).governance());
        ILocker(LOCKER).increaseAmount(amountToBypassThreshold / 2);

        // Call the optimize deposit
        (, uint256[] memory valuesAfter) =
            optimizor.optimizeDeposit(address(token), gauges[address(token)], 10_000_000e18);
        uint256 crvLockAfter = optimizor.cacheVeCRVLockerBalance();

        // Because not enough CRV locked, we should have the same values
        assertEq(valuesBefore[0], valuesAfter[0], "0");
        assertEq(valuesBefore[1], valuesAfter[1], "1");
        assertEq(crvLockBefore, crvLockAfter, "3");

        // Actualize CRV to lock to bypass threshold
        amountToBypassThreshold = ERC20(LOCKER_CRV).balanceOf(LOCKER).mulWadDown(optimizor.veCRVDifferenceThreshold());

        // Liquid Locker lock enough CRV to bypass threshold
        deal(address(CRV), address(this), amountToBypassThreshold);
        CRV.safeTransfer(address(LOCKER), amountToBypassThreshold);
        vm.prank(ILocker(LOCKER).governance());
        ILocker(LOCKER).increaseAmount(amountToBypassThreshold);

        // Call the optimize deposit
        (, valuesAfter) = optimizor.optimizeDeposit(address(token), gauges[address(token)], 10_000_000e18);
        crvLockAfter = optimizor.cacheVeCRVLockerBalance();

        assertNotEq(valuesBefore[1], valuesAfter[1], "4.2");
        assertTrue(valuesBefore[0] != valuesAfter[0], "6");
        assertNotEq(crvLockBefore, crvLockAfter, "7");
    }

    // --- Assertions
    modifier _depositTestMod(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex, uint256 timejump) {
        // --- Before Deposit --- //
        uint256 balanceBeforeStakeDAO = ERC20(gauges[address(token)]).balanceOf(address(LOCKER));
        uint256 balanceBeforeConvex = ERC20(gauges[address(token)]).balanceOf(address(LOCKER_CONVEX));
        uint256 timestampBefore = block.timestamp;
        BaseFallback.PidsInfo memory pidsInfoBefore;
        IFraxUnifiedFarm.LockedStake memory infosBefore;
        address crvRewards;
        if (amountConvex != 0) {
            pidsInfoBefore = fallbackConvexCurve.getPid(address(token));
            (,,, crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidsInfoBefore.pid);
        }

        _; // Deposit process happen here

        // --- After Deposit --- //
        BaseFallback.PidsInfo memory pidsInfo;
        IFraxUnifiedFarm.LockedStake memory infos;
        if (amountConvex != 0) {
            pidsInfo = fallbackConvexCurve.getPid(address(token));
            (,,, crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidsInfo.pid);
        }

        // === ASSERTIONS === //
        //Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(ERC20(gauges[address(token)]).balanceOf(address(LOCKER)) - balanceBeforeStakeDAO, amountStakeDAO, "1");

        if (amountConvex != 0) {
            // Assertion 2: Check Gauge balance of Convex Liquid Locker
            assertEq(
                ERC20(gauges[address(token)]).balanceOf(address(LOCKER_CONVEX)) - balanceBeforeConvex, amountConvex, "2"
            );
            // Assertion 3: Check Convex balance of Curve Strategy
            assertEq(ERC20(crvRewards).balanceOf(address(fallbackConvexCurve)), amountConvex, "3");
        }
    }

    modifier _withdrawTestMod(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex) {
        // Check Stake DAO balance before withdraw
        uint256 balanceBeforeStakeDAO = ERC20(gauges[address(token)]).balanceOf(address(LOCKER));
        uint256 balanceBeforeConvex = fallbackConvexCurve.balanceOf(address(token));

        _; // Withdraw process happen here

        // === ASSERTIONS === //
        //Assertion 1: Check test received token
        assertEq(token.balanceOf(address(this)), amountStakeDAO + amountConvex, "1");
        // Assertion 2: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(balanceBeforeStakeDAO - ERC20(gauges[address(token)]).balanceOf(address(LOCKER)), amountStakeDAO, "2");
        // Assertion 3: Check Convex balance of fallbackConvexFrax or fallbackConvexCurve
        assertEq(balanceBeforeConvex - fallbackConvexCurve.balanceOf(address(token)), amountConvex, "3");
    }

    modifier _claimLiquidLockerMod(ERC20 token, address[] memory extraTokens, address claimer) {
        // Cache balance before
        uint256 balanceBeforeLG = CRV.balanceOf(liquidityGaugeMocks[address(token)]);
        uint256 balanceBeforeAC = CRV.balanceOf(address(curveStrategy.accumulator()));
        uint256 balanceBeforeMS = CRV.balanceOf(address(curveStrategy.rewardsReceiver()));
        uint256 balanceBeforeVE = CRV.balanceOf(address(curveStrategy.veSDTFeeProxy()));
        uint256 balanceBeforeCL = CRV.balanceOf(ALICE);
        uint256 extraTokensLength = extraTokens.length;
        uint256[] memory balanceBeforeExtraLG = new uint256[](extraTokensLength);
        uint256[] memory balanceBeforeFeeReceiver = new uint256[](extraTokensLength);

        _; // Claim process happen here

        // === ASSERTIONS === //
        //Assertion 1: Check test gauge received token
        assertGt(CRV.balanceOf(liquidityGaugeMocks[address(token)]), balanceBeforeLG, "1");
        //Assertion 2: Check test accumulator received token
        assertGt(CRV.balanceOf(address(curveStrategy.accumulator())), balanceBeforeAC, "2");
        //Assertion 3: Check test rewards receiver received token
        assertGt(CRV.balanceOf(address(curveStrategy.rewardsReceiver())), balanceBeforeMS, "3");
        //Assertion 4: Check test veSDT fee proxy received token
        assertGt(CRV.balanceOf(address(curveStrategy.veSDTFeeProxy())), balanceBeforeVE, "4");
        //Assertion 5: Check test alice received token
        assertGt(CRV.balanceOf(ALICE), balanceBeforeCL, "5");

        //Assertion 6 & 7: Check extra token received
        if (extraTokensLength == 0) return;
        for (uint256 i = 0; i < extraTokensLength; ++i) {
            _checkBalanceLGMock(address(token), extraTokens[i], balanceBeforeExtraLG[i]);
            if (extraTokens[i] == address(CRV)) {
                _checkFeesOnCRV(address(token), claimer);
            }
        }
    }

    function _checkBalanceLGMock(address lpToken, address rewardToken, uint256 balanceBeforeLG) internal {
        //Assertion 6: Check extra token received
        assertGt(ERC20(rewardToken).balanceOf(liquidityGaugeMocks[lpToken]), balanceBeforeLG, "6");
    }

    function _checkFeesOnCRV(address lpToken, address claimer) internal {
        {
            (CurveStrategy.Fees memory fee, address accumulator, address rewardsReceiver, address veSDTFeeProxy) =
                CurveStrategy(curveStrategy).getFeesAndReceiver(gauges[lpToken]);
            //Assertion 7: Check extra token received by fee receiver
            if (fee.accumulatorFee != 0) {
                assertGt(CRV.balanceOf(accumulator), 0, "7.1");
            }
            if (fee.perfFee != 0) {
                assertGt(CRV.balanceOf(rewardsReceiver), 0, "7.2");
            }
            if (fee.veSDTFee != 0) {
                assertGt(CRV.balanceOf(veSDTFeeProxy), 0, "7.3");
            }
            if (fee.claimerRewardFee != 0) {
                assertGt(CRV.balanceOf(claimer), 0, "7.4");
            }
        }
    }

    // --- Test with Assertions
    function _depositTest(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex, uint256 timejump)
        internal
        _depositTestMod(token, amountStakeDAO, amountConvex, timejump)
    {
        _deposit(token, amountStakeDAO, amountConvex, timejump);
    }

    function _withdrawTest(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex, uint256 timejump)
        internal
        _withdrawTestMod(token, amountStakeDAO, amountConvex)
    {
        _withdraw(token, amountStakeDAO, amountConvex, timejump);
    }

    function _claimLiquidLockerTest(ERC20 token, uint256 timejump, address[] memory extraTokens, address claimer)
        internal
        _claimLiquidLockerMod(token, extraTokens, claimer)
    {
        _claimLiquidLocker(token, timejump);
    }

    //////////////////////////////////////////////////////
    /// --- CALULATIONS
    //////////////////////////////////////////////////////
    function _calculDepositAmount(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex)
        internal
        view
        returns (uint256, uint256)
    {
        // This need to have the same timestamp as the deposit! So need to use `skip` and `rewind`
        // Amount for Stake DAO
        if (amountStakeDAO == 1) {
            amountStakeDAO = REF_AMOUNT;
        } else if (amountStakeDAO == MAX) {
            uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);
            // Calculate optimal amount
            uint256 optimalAmount = optimizor.optimalAmount(gauges[address(token)], veCRVStakeDAO);
            assert(optimalAmount > 0);

            uint256 currentBalance = ERC20(gauges[address(token)]).balanceOf(LOCKER);
            amountStakeDAO = optimalAmount > currentBalance ? optimalAmount - currentBalance : 0;
        }

        // Amount for Convex
        if (amountConvex == 1) amountConvex = REF_AMOUNT;

        return (amountStakeDAO, amountConvex);
    }

    function _totalBalance(address token) internal view returns (uint256) {
        return ERC20(gauges[token]).balanceOf(LOCKER) + fallbackConvexCurve.balanceOf(token);
    }
}
