// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "test/BaseTest.t.sol";

import {Handler} from "test/invariants/Handler.t.sol";

contract CurveStrategyInvariantsForkTest is BaseTest {
    using SafeTransferLib for ERC20;

    Handler public handler;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public {
        // Create a fork of mainnet, fixing block number for faster testing
        vm.createSelectFork(vm.rpcUrl("mainnet"), FORK_BLOCK_NUMBER_1);

        // Deployment contracts
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        curveStrategy = new CurveStrategy(address(this), rolesAuthority);
        fallbackConvexCurve = new FallbackConvexCurve(address(this), rolesAuthority, address(curveStrategy));
        fallbackConvexFrax = new FallbackConvexFrax(address(this), rolesAuthority, address(curveStrategy));
        optimizor =
        new Optimizor(address(this), rolesAuthority, address(curveStrategy), address(fallbackConvexCurve), address(fallbackConvexFrax));
        liquidityGaugeMockCRV3 = new LiquidityGaugeMock(CRV3);
        liquidityGaugeMockCNC_ETH = new LiquidityGaugeMock(CNC_ETH);
        liquidityGaugeMockSTETH_ETH = new LiquidityGaugeMock(STETH_ETH);
        liquidityGaugeMockALUSD_FRAXBP = new LiquidityGaugeMock(ALUSD_FRAXBP);
        accumulatorMock = new AccumulatorMock();
        handler = new Handler(curveStrategy, fallbackConvexCurve, fallbackConvexFrax, optimizor ,CRV3);
        // End deployment contracts

        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.withdraw.selector, true);

        // Setup contract
        _afterDeployment();

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(address(curveStrategy));

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    function invariant_nothing() public {
        console.log("Invariant nothing", handler.numDeposit());
        console.log("Invariant nothing", handler.numWithdraw());
    }
}
