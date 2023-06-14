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

import {PoolRegistryMock} from "src/mocks/PoolRegistryMock.sol";
import {BaseRewardPoolMock} from "src/mocks/BaseRewardPoolMock.sol";
import {LiquidityGaugeMock} from "src/mocks/LiquidityGaugeMock.sol";
import {BoosterConvexFraxMock} from "src/mocks/BoosterConvexFraxMock.sol";
import {BoosterConvexCurveMock} from "src/mocks/BoosterConvexCurveMock.sol";

contract CurveStrategyInvariantsTest is Test {
    using stdStorage for StdStorage;

    address public immutable STK_ALUSD_FRAXBP = makeAddr("STK_ALUSD_FRAXBP");

    MockERC20 public immutable CRV = new MockERC20("Curve DAO Token", "CRV", 18);
    MockERC20 public immutable CRV3 = new MockERC20("3 Pool", "CRV3", 18);
    MockERC20 public immutable ALUSD_FRAXBP = new MockERC20("Alchemix USD FraxBasePool", "ALUSD_FRAXBP", 18);
    MockERC20 public immutable STETH_ETH = new MockERC20("STETH ETH Pool", "STETH_ETH", 18);

    PoolRegistryMock public poolRegistryMock = new PoolRegistryMock();
    BoosterConvexFraxMock public boosterConvexFraxMock = new BoosterConvexFraxMock();
    BoosterConvexCurveMock public boosterConvexCurveMock = new BoosterConvexCurveMock();

    Optimizor public optimizor;
    CurveStrategy public curveStrategy;
    RolesAuthority public rolesAuthority;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    function setUp() public {
        vm.mockCall(STK_ALUSD_FRAXBP, abi.encodeWithSignature("curveToken()"), abi.encode(address(ALUSD_FRAXBP)));
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        curveStrategy = new CurveStrategy(address(this), rolesAuthority);
        _deployFallbacksModified();
        optimizor = new Optimizor(
            address(this), 
            rolesAuthority, 
            address(curveStrategy), 
            address(fallbackConvexCurve), 
            address(fallbackConvexFrax)
        );

        _labels();
    }

    function test_Nothing() public {
        assertTrue(true);
        console.log(address(fallbackConvexFrax.BOOSTER()));
        console.log(address(fallbackConvexFrax.POOL_REGISTRY()));
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

        // Deploy new contract using modified bytecode
        fallbackConvexFrax = FallbackConvexFrax(
            _deployBytecode(newBytesCode, abi.encode(address(this), rolesAuthority, address(curveStrategy)))
        );
    }

    function _initializeBoosterConvexCurve() internal {
        boosterConvexCurveMock.addPool(address(CRV3), address(0), address(0), address(new BaseRewardPoolMock()));
        boosterConvexCurveMock.addPool(address(STETH_ETH), address(0), address(0), address(new BaseRewardPoolMock()));

        poolRegistryMock.addPool(address(ALUSD_FRAXBP), STK_ALUSD_FRAXBP);
    }
}
