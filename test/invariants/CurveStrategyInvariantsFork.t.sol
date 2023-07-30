// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

import {Handler} from "test/invariants/Handler.t.sol";

contract CurveStrategyInvariantsForkTest is BaseTest {
    using SafeTransferLib for ERC20;

    Handler public handler;

    uint256 public amountBefore;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public {
        // Create a fork of mainnet, fixing block number for faster testing
        vm.rollFork(FORK_BLOCK_NUMBER_1);

        // Deployment contracts
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        curveStrategy = new CurveStrategy(address(this), rolesAuthority);
        fallbackConvexCurve = new FallbackConvexCurve(address(this), rolesAuthority, address(curveStrategy));
        optimizor = new Optimizor(address(this), rolesAuthority, address(curveStrategy), address(fallbackConvexCurve));
        liquidityGaugeMockCRV3 = new LiquidityGaugeMock(CRV3);
        liquidityGaugeMockCNC_ETH = new LiquidityGaugeMock(CNC_ETH);
        liquidityGaugeMockSTETH_ETH = new LiquidityGaugeMock(STETH_ETH);
        liquidityGaugeMockALUSD_FRAXBP = new LiquidityGaugeMock(ALUSD_FRAXBP);
        accumulatorMock = new AccumulatorMock();
        handler = new Handler(curveStrategy, fallbackConvexCurve, optimizor ,CRV3);
        // End deployment contracts

        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(curveStrategy), CurveStrategy.withdraw.selector, true);
        amountBefore = handler.balanceBeforeStakeDAO();

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
        // Assertion n°1: CRV3 balance of strategy should be 0
        assertEq(CRV3.balanceOf(address(curveStrategy)), 0, "Strategy should have no CRV3");
        // Assertion n°2: CRV3 balance of fallbackConvexCurve should be 0

        // Assertion n°3:
        assertEq(
            handler.amountDeposited(),
            handler.balanceFallbackConvexCurve() + handler.balanceStakeDAO() - amountBefore,
            "Wrong balance of CRV3 in Strategy"
        );
    }
}
