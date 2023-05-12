// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "test/BaseTest.t.sol";

contract CurveStrategyTest is BaseTest {
    using SafeTransferLib for ERC20;

    // Contracts
    Optimizor public optimizor;
    ConvexMapper public convexMapper;
    CurveStrategy public curveStrategy;

    // Interfaces
    ILocker public locker;
    IBoosterConvexFrax public boosterConvexFrax;
    IBoosterConvexCurve public boosterConvexCurve;
    IPoolRegistryConvexFrax public poolRegistryConvexFrax;

    // Variables

    //////////////////////////////////////////////////////
    /// --- SETUP --- ///
    //////////////////////////////////////////////////////
    function setUp() public {
        // Create Fork
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet"), 17242848));

        // Label addresses
        labelAddress();

        // Deploy Contracts
        curveStrategy = new CurveStrategy(Authority(address(0)));
        // End of deployment section
        optimizor = Optimizor(curveStrategy.optimizor());
        convexMapper = ConvexMapper(curveStrategy.convexMapper());
        boosterConvexFrax = IBoosterConvexFrax(curveStrategy.boosterConvexFrax());
        boosterConvexCurve = IBoosterConvexCurve(convexMapper.boosterConvexCurve());
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(convexMapper.poolRegistryConvexFrax());

        locker = ILocker(curveStrategy.LOCKER_STAKEDAO());

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));

        // Add all gauges
        addAllGauge();

        // Label contracts
        labelContract();
    }

    // All the following test are  using a fork of mainnet
    /////////////////////////////////////////////////
    /// --- TESTS --- ///
    //////////////////////////////////////////////////////
    function test_Deployment() public {
        assertTrue(address(curveStrategy) != address(0));
        assertTrue(address(curveStrategy.optimizor()) != address(0));
        assertTrue(address(curveStrategy.convexMapper()) != address(0));

        assertEq(convexMapper.lastPidsCountConvexFrax(), poolRegistryConvexFrax.poolLength(), "1");
        assertEq(convexMapper.lastPidsCountConvexCurve(), boosterConvexCurve.poolLength(), "2");
    }

    function test_Deposit_3CRV() public {
        // Deal 3CRV to this contract
        deal(address(CRV3), address(this), 10e18);
        // Approve 3CRV to strategy
        CRV3.safeApprove(address(curveStrategy), 10e18);
        // Deposit 3CRV
        curveStrategy.deposit(address(CRV3), 10e18);
    }

    //////////////////////////////////////////////////////
    /// --- HELPER FUNCTIONS --- ///
    //////////////////////////////////////////////////////
    function addAllGauge() internal {
        curveStrategy.setGauge(address(CRV3), GAUGE_CRV3);
        curveStrategy.setGauge(address(ALUSD_FRAXBP), GAUGE_ALUSD_FRAXBP);
    }

    function labelContract() internal {
        vm.label(address(curveStrategy), "CurveStrategy");
        vm.label(address(curveStrategy.optimizor()), "Optimizor");
        vm.label(address(curveStrategy.convexMapper()), "ConvexMapper");
    }
}
