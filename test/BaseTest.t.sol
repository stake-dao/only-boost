// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Test.sol";

// --- Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {RolesAuthority} from "solmate/auth/authorities/RolesAuthority.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// --- Contracts
import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {CurveStrategy} from "src/CurveStrategy.sol";
import {EventsAndErrors} from "src/EventsAndErrors.sol";
import {FallbackConvexFrax} from "src/FallbackConvexFrax.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

// --- Mocks
import {LiquidityGaugeMock} from "src/mocks/LiquidityGaugeMock.sol";
import {FallbackConvexCurveMock} from "src/mocks/FallbackConvexCurveMock.sol";

// --- Interfaces
import {ILocker} from "src/interfaces/ILocker.sol";
import {IFraxUnifiedFarm} from "src/interfaces/IFraxUnifiedFarm.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract BaseTest is Test {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- CONTRACTS & MOCKS & INTERFACES
    //////////////////////////////////////////////////////
    // --- Contracts
    Optimizor public optimizor;
    CurveStrategy public curveStrategy;
    RolesAuthority public rolesAuthority;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    // --- Mocks
    LiquidityGaugeMock public liquidityGaugeMockCRV3;
    LiquidityGaugeMock public liquidityGaugeMockCNC_ETH;
    LiquidityGaugeMock public liquidityGaugeMockSTETH_ETH;
    LiquidityGaugeMock public liquidityGaugeMockALUSD_FRAXBP;

    // --- Interfaces
    ILocker public locker;
    IBoosterConvexFrax public boosterConvexFrax;
    IBoosterConvexCurve public boosterConvexCurve;
    IPoolRegistryConvexFrax public poolRegistryConvexFrax;

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
    ERC20 public constant STETH_ETH = ERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    ERC20 public constant COIL_FRAXBP = ERC20(0xb85010193FD15aF8390dbD62790Da70F46c1126B);
    ERC20 public constant ALUSD_FRAXBP = ERC20(0xB30dA2376F63De30b42dC055C93fa474F31330A5);

    // --- Curve Gauges address
    address public constant GAUGE_CRV3 = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;
    address public constant GAUGE_EUR3 = 0x1E212e054d74ed136256fc5a5DDdB4867c6E003F;
    address public constant GAUGE_CNC_ETH = 0x5A8fa46ebb404494D718786e55c4E043337B10bF;
    address public constant GAUGE_STETH_ETH = 0x182B723a58739a9c974cFDB385ceaDb237453c28;
    address public constant GAUGE_ALUSD_FRAXBP = 0x740BA8aa0052E07b925908B380248cb03f3DE5cB;

    // --- Lockers address
    address public constant LOCKER_STAKEDAO = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80; // Convex CRV Locker

    // --- Users address
    address public immutable ALICE = makeAddr("Alice");

    // --- Fees amounts in basis points
    uint256 public constant FEE_PERF = 100; // 1%
    uint256 public constant FEE_ACCU = 100; // 1%
    uint256 public constant FEE_VESDT = 100; // 1%
    uint256 public constant FEE_CLAIM = 100; // 1%

    // --- Usefull constants
    uint256 public constant REF_AMOUNT = 1_000e18;
    uint256 public constant MAX = type(uint256).max;

    // --- Fork block numbers
    uint256 public constant FORK_BLOCK_NUMBER_1 = 17330000;
    uint256 public constant FORK_BLOCK_NUMBER_2 = 17326000; // DO NOT TOUCH IT !!

    uint256 public forkId1;
    uint256 public forkId2;

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    // --- Mapings for test purpose only
    mapping(address => bool) public isMetapool;
    mapping(address => address) public gauges;
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

        // Set mapping for metapools
        isMetapool[address(CRV3)] = false;
        isMetapool[address(EUR3)] = false;
        isMetapool[address(CNC_ETH)] = false;
        isMetapool[address(ALUSD_FRAXBP)] = true;
        isMetapool[address(STETH_ETH)] = false;
    }

    //////////////////////////////////////////////////////
    /// --- HELPER FUNCTIONS
    //////////////////////////////////////////////////////
    function _afterDeployment() internal {
        // Setup contracts
        optimizor = curveStrategy.optimizor();
        fallbackConvexFrax = optimizor.fallbackConvexFrax();
        fallbackConvexCurve = optimizor.fallbackConvexCurve();
        locker = ILocker(LOCKER_STAKEDAO);
        boosterConvexFrax = IBoosterConvexFrax(fallbackConvexFrax.boosterConvexFrax());
        boosterConvexCurve = IBoosterConvexCurve(fallbackConvexCurve.boosterConvexCurve());
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(fallbackConvexFrax.poolRegistryConvexFrax());

        _labelContract();
        // Add all curve gauges
        curveStrategy.setGauge(address(CRV3), GAUGE_CRV3);
        curveStrategy.setGauge(address(CNC_ETH), GAUGE_CNC_ETH);
        curveStrategy.setGauge(address(STETH_ETH), GAUGE_STETH_ETH);
        curveStrategy.setGauge(address(ALUSD_FRAXBP), GAUGE_ALUSD_FRAXBP);

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

        uint256 len = tokens.length;
        for (uint8 i; i < len; ++i) {
            address token = tokens[i];
            if (token == address(0)) break;

            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.PERFFEE, gauges[address(token)], FEE_PERF);
            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.VESDTFEE, gauges[address(token)], FEE_VESDT);
            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.ACCUMULATORFEE, gauges[address(token)], FEE_ACCU);
            curveStrategy.manageFee(EventsAndErrors.MANAGEFEE.CLAIMERREWARD, gauges[address(token)], FEE_CLAIM);
        }

        // Grant public access to claim function for curve strategy
        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.claim.selector, true);
        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.claim3Crv.selector, true);

        // Grant access to deposit/withdraw function for optimizor to curveStrategy
        rolesAuthority.setRoleCapability(1, address(optimizor), Optimizor.optimizeDeposit.selector, true);
        rolesAuthority.setRoleCapability(2, address(optimizor), Optimizor.optimizeWithdraw.selector, true);
        rolesAuthority.setUserRole(address(curveStrategy), 1, true);
        rolesAuthority.setUserRole(address(curveStrategy), 2, true);

        // Grant access to deposit/withdraw/claim function for fallback convex frax to curveStrategy
        rolesAuthority.setRoleCapability(1, address(fallbackConvexFrax), FallbackConvexFrax.deposit.selector, true);
        rolesAuthority.setRoleCapability(2, address(fallbackConvexFrax), FallbackConvexFrax.withdraw.selector, true);
        rolesAuthority.setRoleCapability(3, address(fallbackConvexFrax), FallbackConvexFrax.claimRewards.selector, true);
        rolesAuthority.setUserRole(address(curveStrategy), 1, true);
        rolesAuthority.setUserRole(address(curveStrategy), 2, true);
        rolesAuthority.setUserRole(address(curveStrategy), 3, true);

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
        vm.label(address(CRV), "CRV");
        vm.label(address(CNC), "CNC");
        vm.label(address(LDO), "LDO");
        vm.label(address(CVX), "CVX");
        vm.label(address(FXS), "FXS");

        // LP Tokens
        vm.label(address(CRV3), "CRV3");
        vm.label(address(EUR3), "EUR3");
        vm.label(address(CNC_ETH), "CNC_ETH");
        vm.label(address(STETH_ETH), "STETH_ETH");
        vm.label(address(ALUSD_FRAXBP), "ALUSD_FRAXBP");

        // Gauge addresses
        vm.label(GAUGE_CRV3, "GAUGE_CRV3");
        vm.label(GAUGE_EUR3, "GAUGE_EUR3");
        vm.label(GAUGE_CNC_ETH, "GAUGE_CNC_ETH");
        vm.label(GAUGE_STETH_ETH, "GAUGE_STETH_ETH");
        vm.label(GAUGE_ALUSD_FRAXBP, "GAUGE_ALUSD_FRAXBP");
    }

    function _labelContract() internal {
        vm.label(address(rolesAuthority), "RolesAuthority");
        vm.label(address(curveStrategy), "CurveStrategy");
        vm.label(address(curveStrategy.optimizor()), "Optimizor");
        vm.label(address(fallbackConvexFrax), "FallbackConvexFrax");
        vm.label(address(fallbackConvexCurve), "FallbackConvexCurve");
        vm.label(address(locker), "Locker");
        vm.label(address(boosterConvexFrax), "BoosterConvexFrax");
        vm.label(address(boosterConvexCurve), "BoosterConvexCurve");
        vm.label(address(poolRegistryConvexFrax), "PoolRegistryConvexFrax");

        // Mocks
        vm.label(address(liquidityGaugeMockCRV3), "LiquidityGaugeMockCRV3");
        vm.label(address(liquidityGaugeMockCNC_ETH), "LiquidityGaugeMockCNC_ETH");
        vm.label(address(liquidityGaugeMockSTETH_ETH), "LiquidityGaugeMockSTETH_ETH");
        vm.label(address(liquidityGaugeMockALUSD_FRAXBP), "LiquidityGaugeMockALUSD_FRAXBP");
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

    function _killConvexFraxAuth() internal {
        // Allow optimizor to withdraw from ConvexFrax
        rolesAuthority.setRoleCapability(1, address(fallbackConvexFrax), FallbackConvexFrax.withdraw.selector, true);
        rolesAuthority.setUserRole(address(optimizor), 1, true);

        // Allow optimizor to call depositForOptimizor on CurveStrategy
        rolesAuthority.setRoleCapability(1, address(curveStrategy), CurveStrategy.depositForOptimizor.selector, true);
        rolesAuthority.setUserRole(address(optimizor), 1, true);
    }

    // --- Assertions
    modifier _depositTestMod(ERC20 token, uint256 amountStakeDAO, uint256 amountConvex, uint256 timejump) {
        // --- Before Deposit --- //
        uint256 balanceBeforeStakeDAO = ERC20(gauges[address(token)]).balanceOf(address(LOCKER_STAKEDAO));
        uint256 balanceBeforeConvex = ERC20(gauges[address(token)]).balanceOf(address(LOCKER_CONVEX));
        uint256 timestampBefore = block.timestamp;
        BaseFallback.PidsInfo memory pidsInfoBefore;
        IFraxUnifiedFarm.LockedStake memory infosBefore;
        address crvRewards;
        if (amountConvex != 0) {
            if (isMetapool[address(token)] && !optimizor.convexFraxPaused()) {
                pidsInfoBefore = fallbackConvexFrax.getPid(address(token));
                address personalVault = poolRegistryConvexFrax.vaultMap(pidsInfoBefore.pid, address(fallbackConvexFrax));
                (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pidsInfoBefore.pid);

                // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
                // and the last one is emptyed. So we need to get the last one.
                uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
                if (lockCount > 0) infosBefore = IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCount - 1];
            } else {
                pidsInfoBefore = fallbackConvexCurve.getPid(address(token));
                (,,, crvRewards,,) = boosterConvexCurve.poolInfo(pidsInfoBefore.pid);
            }
        }

        _; // Deposit process happen here

        // --- After Deposit --- //
        BaseFallback.PidsInfo memory pidsInfo;
        IFraxUnifiedFarm.LockedStake memory infos;
        if (amountConvex != 0) {
            if (isMetapool[address(token)] && !optimizor.convexFraxPaused()) {
                pidsInfo = fallbackConvexFrax.getPid(address(token));
                address personalVault = poolRegistryConvexFrax.vaultMap(pidsInfo.pid, address(fallbackConvexFrax));
                (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pidsInfo.pid);

                // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
                // and the last one is emptyed. So we need to get the last one.
                uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
                if (lockCount > 0) infos = IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCount - 1];
            } else {
                pidsInfo = fallbackConvexCurve.getPid(address(token));
                (,,, crvRewards,,) = boosterConvexCurve.poolInfo(pidsInfo.pid);
            }
        }

        // === ASSERTIONS === //
        //Assertion 1: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(
            ERC20(gauges[address(token)]).balanceOf(address(LOCKER_STAKEDAO)) - balanceBeforeStakeDAO,
            amountStakeDAO,
            "1"
        );

        if (isMetapool[address(token)] && amountConvex != 0 && !optimizor.convexFraxPaused()) {
            // Assertion 2: Check personal vault created
            assertTrue(poolRegistryConvexFrax.vaultMap(pidsInfo.pid, address(fallbackConvexFrax)) != address(0), "2");
            // Assertion 3: Check value for personal vault, such as liquidity, kek_id, timestamps, lock_multiplier
            assertEq(infos.liquidity, amountConvex + infosBefore.liquidity, "3");
            assertEq(infos.kek_id, fallbackConvexFrax.kekIds(fallbackConvexFrax.vaults(pidsInfo.pid)), "4"); // kek_id is the same as vault
            assertEq(infos.start_timestamp, timestampBefore, "5");
            assertEq(infos.ending_timestamp, timestampBefore + fallbackConvexFrax.lockingIntervalSec(), "6");
            assertGt(infos.lock_multiplier, 0, "7");
        } else if (amountConvex != 0) {
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
        uint256 balanceBeforeStakeDAO = ERC20(gauges[address(token)]).balanceOf(address(LOCKER_STAKEDAO));
        uint256 balanceBeforeConvex;
        BaseFallback.PidsInfo memory pidsInfo;
        IFraxUnifiedFarm.LockedStake memory infosBefore;
        address personalVault;
        address staking;
        uint256 lockCountBefore;
        if (isMetapool[address(token)]) {
            // Get all needed infos for following assertions
            pidsInfo = fallbackConvexFrax.getPid(address(ALUSD_FRAXBP));
            personalVault = poolRegistryConvexFrax.vaultMap(pidsInfo.pid, address(fallbackConvexFrax));
            (, staking,,,) = poolRegistryConvexFrax.poolInfo(pidsInfo.pid);
            lockCountBefore = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
            if (lockCountBefore > 0) {
                infosBefore = IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCountBefore - 1];
            }
        } else {
            balanceBeforeConvex = fallbackConvexCurve.balanceOf(address(token));
        }

        _; // Withdraw process happen here

        uint256 lockCountAfter;
        IFraxUnifiedFarm.LockedStake memory infosAfter;
        if (isMetapool[address(token)]) {
            lockCountAfter = IFraxUnifiedFarm(staking).lockedStakesOfLength(personalVault);
            if (lockCountAfter > 0) {
                infosAfter = IFraxUnifiedFarm(staking).lockedStakesOf(personalVault)[lockCountAfter - 1];
            }
        }

        // === ASSERTIONS === //
        //Assertion 1: Check test received token
        assertEq(token.balanceOf(address(this)), amountStakeDAO + amountConvex, "1");
        // Assertion 2: Check Gauge balance of Stake DAO Liquid Locker
        assertEq(
            balanceBeforeStakeDAO - ERC20(gauges[address(token)]).balanceOf(address(LOCKER_STAKEDAO)),
            amountStakeDAO,
            "2"
        );
        // Assertion 3: Check Convex balance of fallbackConvexFrax or fallbackConvexCurve
        if (!isMetapool[address(token)]) {
            assertEq(balanceBeforeConvex - fallbackConvexCurve.balanceOf(address(token)), amountConvex, "3");
        } else {
            // If withdrawn amount is not total balance, remaining amount is redeposited
            if (amountConvex != infosBefore.liquidity) {
                //Assertion 3: Check length of lockedStakesOf, should be 2 due to withdraw and redeposit
                assertEq(lockCountAfter, lockCountBefore + 1, "3");
                //Assertion 4: Check kek_id is different due to new lockStake
                assertTrue(infosAfter.kek_id != infosBefore.kek_id, "4");
            } else {
                //Assertion 3: Check length of lockedStakesOf, should be 1 due to full withdraw
                assertEq(lockCountAfter, lockCountBefore, "3");
                //Assertion 4: Check kek_id is the same due to no new lockStake
                assertTrue(infosAfter.kek_id == bytes32(0), "4");
            }
        }
    }

    modifier _claimLiquidLockerMod(ERC20 token, address[] memory extraTokens) {
        // Cache balance before
        uint256 balanceBeforeLG = CRV.balanceOf(liquidityGaugeMocks[address(token)]);
        uint256 balanceBeforeAC = CRV.balanceOf(address(curveStrategy.accumulator()));
        uint256 balanceBeforeMS = CRV.balanceOf(address(curveStrategy.rewardsReceiver()));
        uint256 balanceBeforeVE = CRV.balanceOf(address(curveStrategy.veSDTFeeProxy()));
        uint256 balanceBeforeCL = CRV.balanceOf(ALICE);
        uint256 extraTokensLength = extraTokens.length;
        uint256[] memory balanceBeforeExtraLG = new uint256[](extraTokensLength);
        uint256[] memory balanceBeforeFeeReceiver = new uint256[](extraTokensLength);

        if (extraTokensLength > 0) {
            for (uint256 i = 0; i < extraTokensLength; ++i) {
                balanceBeforeExtraLG[i] = ERC20(extraTokens[i]).balanceOf(liquidityGaugeMocks[address(token)]);
                if (isMetapool[address(token)]) {
                    balanceBeforeFeeReceiver[i] =
                        ERC20(extraTokens[i]).balanceOf(address(fallbackConvexFrax.feesReceiver()));
                } else {
                    balanceBeforeFeeReceiver[i] =
                        ERC20(extraTokens[i]).balanceOf(address(fallbackConvexCurve.feesReceiver()));
                }
            }
        }

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
            //Assertion 6: Check extra token received
            assertGt(ERC20(extraTokens[i]).balanceOf(liquidityGaugeMocks[address(token)]), balanceBeforeExtraLG[i], "6");

            //Assertion 7: Check extra token received by fee receiver
            if (isMetapool[address(token)]) {
                if (fallbackConvexFrax.feesOnRewards() == 0) continue;
                assertGt(
                    ERC20(extraTokens[i]).balanceOf(address(fallbackConvexFrax.feesReceiver())),
                    balanceBeforeFeeReceiver[i],
                    "7"
                );
            } else {
                if (fallbackConvexCurve.feesOnRewards() == 0) continue;
                assertGt(
                    ERC20(extraTokens[i]).balanceOf(address(fallbackConvexCurve.feesReceiver())),
                    balanceBeforeFeeReceiver[i],
                    "7"
                );
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

    function _claimLiquidLockerTest(ERC20 token, uint256 timejump, address[] memory extraTokens)
        internal
        _claimLiquidLockerMod(token, extraTokens)
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
            // Calculate optimal amount
            uint256 optimalAmount = optimizor.optimization1(
                gauges[address(token)], isMetapool[address(token)] && !optimizor.convexFraxPaused()
            );
            assert(optimalAmount > 0);

            amountStakeDAO = optimalAmount - ERC20(gauges[address(token)]).balanceOf(LOCKER_STAKEDAO);
        }

        // Amount for Convex
        if (amountConvex == 1) amountConvex = REF_AMOUNT;

        return (amountStakeDAO, amountConvex);
    }
}
