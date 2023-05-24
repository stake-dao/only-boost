// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Test.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Contracts
import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {CurveStrategy} from "src/CurveStrategy.sol";
import {EventsAndErrors} from "src/EventsAndErrors.sol";
import {FallbackConvexFrax} from "src/FallbackConvexFrax.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

// Mocks
import {LiquidityGaugeMock} from "src/mocks/LiquidityGaugeMock.sol";

// Interfaces
import {ILocker} from "src/interfaces/ILocker.sol";
import {IFraxUnifiedFarm} from "src/interfaces/IFraxUnifiedFarm.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract BaseTest is Test {
    // Classic Tokens
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant CNC = ERC20(0x9aE380F0272E2162340a5bB646c354271c0F5cFC);
    ERC20 public constant LDO = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);

    // LP Tokens
    ERC20 public constant CRV3 = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    ERC20 public constant EUR3 = ERC20(0xb9446c4Ef5EBE66268dA6700D26f96273DE3d571);
    ERC20 public constant CNC_ETH = ERC20(0xF9835375f6b268743Ea0a54d742Aa156947f8C06);
    ERC20 public constant STETH_ETH = ERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    ERC20 public constant ALUSD_FRAXBP = ERC20(0xB30dA2376F63De30b42dC055C93fa474F31330A5);

    // Gauge address
    address public constant GAUGE_CRV3 = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;
    address public constant GAUGE_EUR3 = 0x1E212e054d74ed136256fc5a5DDdB4867c6E003F;
    address public constant GAUGE_CNC_ETH = 0x5A8fa46ebb404494D718786e55c4E043337B10bF;
    address public constant GAUGE_STETH_ETH = 0x182B723a58739a9c974cFDB385ceaDb237453c28;
    address public constant GAUGE_ALUSD_FRAXBP = 0x740BA8aa0052E07b925908B380248cb03f3DE5cB;

    // Locker address
    address public constant LOCKER_STAKEDAO = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80; // Convex CRV Locker

    // User address
    address public immutable ALICE;

    uint256 public constant MAX = type(uint256).max;
    uint256 public constant REF_AMOUNT = 1_000e18;
    uint256 public constant FEE_PERF = 100; // 1%
    uint256 public constant FEE_ACCU = 100; // 1%
    uint256 public constant FEE_VESDT = 100; // 1%
    uint256 public constant FEE_CLAIM = 100; // 1%

    mapping(address => bool) public isMetapool;
    mapping(address => address) public gauges;
    mapping(address => address) public liquidityGaugeMocks;

    constructor() {
        labelAddress();
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

        // Set user address
        ALICE = makeAddr("Alice");
    }

    function labelAddress() internal {
        // Classic Tokens
        vm.label(address(CRV), "CRV");
        vm.label(address(CNC), "CNC");
        vm.label(address(LDO), "LDO");

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
}
