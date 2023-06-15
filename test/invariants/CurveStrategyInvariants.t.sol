// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {RolesAuthority} from "solmate/auth/authorities/RolesAuthority.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {LibString} from "solady/src/utils/LibString.sol";

import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {CurveStrategy} from "src/CurveStrategy.sol";
import {EventsAndErrors} from "src/EventsAndErrors.sol";
import {FallbackConvexFrax} from "src/FallbackConvexFrax.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

import {OptimizorMock} from "src/mocks/OptimizorMock.sol";
import {LiquidLockerMock} from "src/mocks/LiquidLockerMock.sol";
import {PoolRegistryMock} from "src/mocks/PoolRegistryMock.sol";
import {BaseRewardPoolMock} from "src/mocks/BaseRewardPoolMock.sol";
import {LiquidityGaugeMock} from "src/mocks/LiquidityGaugeMock.sol";
import {BoosterConvexFraxMock} from "src/mocks/BoosterConvexFraxMock.sol";
import {BoosterConvexCurveMock} from "src/mocks/BoosterConvexCurveMock.sol";

import {Handler} from "test/invariants/Handler.t.sol";

contract CurveStrategyInvariantsTest is Test {
    using stdStorage for StdStorage;

    address public immutable STK_ALUSD_FRAXBP = makeAddr("STK_ALUSD_FRAXBP");

    MockERC20 public CRV;
    MockERC20 public CRV3;
    MockERC20 public ALUSD_FRAXBP;
    MockERC20 public STETH_ETH;

    PoolRegistryMock public poolRegistryMock;
    LiquidLockerMock public liquidLockerMock;
    LiquidityGaugeMock public liquidityGaugeCRV3Mock;
    BoosterConvexFraxMock public boosterConvexFraxMock;
    BoosterConvexCurveMock public boosterConvexCurveMock;

    OptimizorMock public optimizor;
    CurveStrategy public curveStrategy;
    RolesAuthority public rolesAuthority;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    Handler public handler;

    function setUp() public {
        CRV = new MockERC20("Curve DAO Token", "CRV", 18);
        CRV3 = new MockERC20("3 Pool", "CRV3", 18);
        ALUSD_FRAXBP = new MockERC20("Alchemix USD FraxBasePool", "ALUSD_FRAXBP", 18);
        STETH_ETH = new MockERC20("STETH ETH Pool", "STETH_ETH", 18);

        poolRegistryMock = new PoolRegistryMock();
        liquidLockerMock = new LiquidLockerMock(address(curveStrategy));
        boosterConvexFraxMock = new BoosterConvexFraxMock();
        boosterConvexCurveMock = new BoosterConvexCurveMock();
        liquidityGaugeCRV3Mock = new LiquidityGaugeMock(MockERC20(address(CRV3)));

        ////
        vm.mockCall(STK_ALUSD_FRAXBP, abi.encodeWithSignature("curveToken()"), abi.encode(address(ALUSD_FRAXBP)));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        _deployCurveStrategyModified();
        _deployFallbacksModified();
        _deployOptimizorModified();
        curveStrategy.setOptimizor(address(optimizor));
        liquidLockerMock.setStrategy(address(curveStrategy));
        handler = new Handler(curveStrategy, CRV3);
        _labels();

        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(optimizor), OptimizorMock.optimizeDeposit.selector, true);
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
        curveStrategy.setGauge(address(CRV3), address(liquidityGaugeCRV3Mock));

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.deposit.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /*
    function test_Nothing() public {
        assertTrue(true);
        console.log(address(fallbackConvexFrax.BOOSTER()));
        console.log(address(fallbackConvexFrax.POOL_REGISTRY()));
    }*/

    function invariant_deposit() public {
        assertGe(handler.numCalls(), 0);
        console.log("handler num calls: %d", handler.numCalls());
    }

    function _labels() internal {
        // Label tokens
        vm.label(address(CRV), "CRV");
        vm.label(address(CRV3), "CRV3");
        vm.label(address(ALUSD_FRAXBP), "ALUSD_FRAXBP");
        vm.label(address(STETH_ETH), "STETH_ETH");

        // Label mocks contracts
        vm.label(address(poolRegistryMock), "poolRegistryMock");
        vm.label(address(boosterConvexFraxMock), "boosterConvexFraxMock");
        vm.label(address(boosterConvexCurveMock), "boosterConvexCurveMock");

        // Label contracts
        vm.label(address(optimizor), "optimizor");
        vm.label(address(curveStrategy), "curveStrategy");
        vm.label(address(rolesAuthority), "rolesAuthority");
        vm.label(address(fallbackConvexFrax), "fallbackConvexFrax");
        vm.label(address(fallbackConvexCurve), "fallbackConvexCurve");
    }

    function _deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }

    function _deployFallbacksModified() internal {
        // --- Convex Curve --- //
        // Initialize booster
        _initializeBoosterConvexCurve();

        // Change address of booster
        bytes memory newBytesCode = bytes(
            LibString.replace(
                string(abi.encodePacked(type(FallbackConvexCurve).creationCode)),
                string(abi.encodePacked(0xF403C135812408BFbE8713b5A23a04b3D48AAE31)),
                string(abi.encodePacked(address(boosterConvexCurveMock)))
            )
        );

        // Change CRV address
        newBytesCode = bytes(
            LibString.replace(
                string(newBytesCode),
                string(abi.encodePacked(0xD533a949740bb3306d119CC777fa900bA034cd52)),
                string(abi.encodePacked(address(CRV)))
            )
        );

        // Deploy new contract using modified bytecode
        fallbackConvexCurve = FallbackConvexCurve(
            _deployBytecode(newBytesCode, abi.encode(address(this), rolesAuthority, address(curveStrategy)))
        );

        // --- Convex Frax --- //
        // Change address of booster
        newBytesCode = bytes(
            LibString.replace(
                string(abi.encodePacked(type(FallbackConvexFrax).creationCode)),
                string(abi.encodePacked(0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa)),
                string(abi.encodePacked(address(boosterConvexFraxMock)))
            )
        );

        // Change address of pool registry
        newBytesCode = bytes(
            LibString.replace(
                string(newBytesCode),
                string(abi.encodePacked(0x41a5881c17185383e19Df6FA4EC158a6F4851A69)),
                string(abi.encodePacked(address(poolRegistryMock)))
            )
        );

        // Change CRV address
        newBytesCode = bytes(
            LibString.replace(
                string(newBytesCode),
                string(abi.encodePacked(0xD533a949740bb3306d119CC777fa900bA034cd52)),
                string(abi.encodePacked(address(CRV)))
            )
        );

        // Deploy new contract using modified bytecode
        fallbackConvexFrax = FallbackConvexFrax(
            _deployBytecode(newBytesCode, abi.encode(address(this), rolesAuthority, address(curveStrategy)))
        );
    }

    function _deployOptimizorModified() internal {
        // Change address of CRV
        bytes memory newBytesCode = bytes(
            LibString.replace(
                string(abi.encodePacked(type(OptimizorMock).creationCode)),
                string(abi.encodePacked(0xD533a949740bb3306d119CC777fa900bA034cd52)),
                string(abi.encodePacked(address(CRV)))
            )
        );
        // Change address of Liquid Locker
        newBytesCode = bytes(
            LibString.replace(
                string(newBytesCode),
                string(abi.encodePacked(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6)),
                string(abi.encodePacked(address(liquidLockerMock)))
            )
        );

        optimizor = OptimizorMock(
            _deployBytecode(
                newBytesCode,
                abi.encode(
                    address(this),
                    rolesAuthority,
                    address(curveStrategy),
                    address(fallbackConvexCurve),
                    address(fallbackConvexFrax)
                )
            )
        );
    }

    function _deployCurveStrategyModified() internal {
        // Change address of CRV
        bytes memory newBytesCode = bytes(
            LibString.replace(
                string(abi.encodePacked(type(CurveStrategy).creationCode)),
                string(abi.encodePacked(0xD533a949740bb3306d119CC777fa900bA034cd52)),
                string(abi.encodePacked(address(CRV)))
            )
        );

        // Change address of Liquid Locker
        newBytesCode = bytes(
            LibString.replace(
                string(newBytesCode),
                string(abi.encodePacked(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6)),
                string(abi.encodePacked(address(liquidLockerMock)))
            )
        );

        curveStrategy = CurveStrategy(_deployBytecode(newBytesCode, abi.encode(address(this), rolesAuthority)));
    }

    function _initializeBoosterConvexCurve() internal {
        boosterConvexCurveMock.addPool(address(CRV3), address(0), address(0), address(new BaseRewardPoolMock()));
        boosterConvexCurveMock.addPool(address(STETH_ETH), address(0), address(0), address(new BaseRewardPoolMock()));
        boosterConvexCurveMock.addPool(address(ALUSD_FRAXBP), address(0), address(0), address(new BaseRewardPoolMock()));

        poolRegistryMock.addPool(address(ALUSD_FRAXBP), STK_ALUSD_FRAXBP);
    }
}
