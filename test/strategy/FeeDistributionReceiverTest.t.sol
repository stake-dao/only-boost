// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {FeeDistributionReceiver} from "src/strategy/FeeDistributionReceiver.sol";
import {MockERC20} from "lib/solady/test/utils/mocks/MockERC20.sol";

contract FeeDistributionReceiverTest is Test {
    //MockERC20 public rewardToken;
    FeeDistributionReceiver public feeReceiver;

    address public veSdtFeeProxy = address(0xBadC0de);
    address public dao = address(0xBA5EBA11);
    address public accumulator = address(0xBEA7ED);

    address public governance = address(0xB055);

    MockERC20 public tokenA = new MockERC20("Token A", "TKA", 18);
    MockERC20 public tokenB = new MockERC20("Token B", "TKB", 16);
    MockERC20 public tokenC = new MockERC20("Token C", "TKC", 8);

    function setUp() public {
        feeReceiver = new FeeDistributionReceiver(governance, veSdtFeeProxy, dao);
        }

    function test_initialSetup() public {

        assertEq(feeReceiver.veSdtFeeProxy(), veSdtFeeProxy);
        assertEq(feeReceiver.dao(), dao);
        assertEq(feeReceiver.governance(), governance);
        assertEq(feeReceiver.futureGovernance(), address(0));
    }

    ////////////////////////////////////////////////////////////
    /// --- GOVERNANCE ---
    ////////////////////////////////////////////////////////////

    function test_transferGovernance() public {
        vm.prank(governance);
        feeReceiver.transferGovernance(address(0x4));
        assertEq(feeReceiver.futureGovernance(), address(0x4));
    }

    function test_acceptGovernance() public {
        vm.prank(governance);
        feeReceiver.transferGovernance(address(0x4));

        vm.prank(address(0x4));
        feeReceiver.acceptGovernance();
        assertEq(feeReceiver.governance(), address(0x4));
        assertEq(feeReceiver.futureGovernance(), address(0));
    }

    function test_setDao() public {
        vm.prank(governance);
        feeReceiver.setDao(address(0x5));
        assertEq(feeReceiver.dao(), address(0x5));
    }

    function test_setVeSdtFeeProxy() public {
        vm.prank(governance);
        feeReceiver.setVeSdtFeeProxy(address(0x6));
        assertEq(feeReceiver.veSdtFeeProxy(), address(0x6));
    }

    function test_setRewardTokenAndDistribution() public {
        vm.prank(governance);
        feeReceiver.setRewardTokenAndDistribution(address(tokenA), accumulator, 2_500, 5_000, 2_500);
        assertEq(feeReceiver.rewardTokenAccumulator(address(tokenA)), accumulator);

        (uint256 daoPart, uint256 accumulatorPart, uint256 veSdtFeeProxyPart) =
            feeReceiver.rewardTokenFeeDistribution(address(tokenA));
        assertEq(daoPart, 2_500);
        assertEq(accumulatorPart, 5_000);
        assertEq(veSdtFeeProxyPart, 2_500);

        // Changing using setRepartition
        vm.prank(governance);
        feeReceiver.setDistribution(address(tokenA), 1_000, 8_000, 1_000);

        (daoPart, accumulatorPart, veSdtFeeProxyPart) = feeReceiver.rewardTokenFeeDistribution(address(tokenA));

        assertEq(daoPart, 1_000);
        assertEq(accumulatorPart, 8_000);
        assertEq(veSdtFeeProxyPart, 1_000);
    }

    ////////////////////////////////////////////////////////////
    /// --- SPLIT FEE ---
    ////////////////////////////////////////////////////////////

    function test_distributeFee(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 10_000);
        tokenA.mint(address(feeReceiver), amount);

        vm.startPrank(governance);
        feeReceiver.setRewardTokenAndDistribution(address(tokenA), accumulator, 2_500, 5_000, 2_500);
        vm.stopPrank();

        feeReceiver.distribute(address(tokenA));

        assertEq(tokenA.balanceOf(dao), amount * 25 / 100);
        assertEq(tokenA.balanceOf(accumulator), amount * 50 / 100);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amount * 25 / 100);
    }


    function test_distributeFeeWithOneZero(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 10_000);
        tokenA.mint(address(feeReceiver), amount);

        vm.startPrank(governance);
        feeReceiver.setRewardTokenAndDistribution(address(tokenA), accumulator, 0, 5_000, 5_000);
        vm.stopPrank();

        vm.prank(accumulator);
        feeReceiver.distribute(address(tokenA));

        assertEq(tokenA.balanceOf(dao), 0);
        assertEq(tokenA.balanceOf(accumulator), amount * 50 / 100);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amount * 50 / 100);
    }

    function test_distributeFeeMultipleRewardTokens(uint256 amountA, uint256 amountB, uint256 amountC) public {
        vm.assume(amountA < type(uint256).max / 10_000);
        vm.assume(amountB < type(uint256).max / 10_000);
        vm.assume(amountC < type(uint256).max / 10_000);

        vm.assume(amountA > 0);
        vm.assume(amountB > 0);
        vm.assume(amountC > 0);

        tokenA.mint(address(feeReceiver), amountA);
        tokenB.mint(address(feeReceiver), amountB);
        tokenC.mint(address(feeReceiver), amountC);

        uint256 distributionDaoA = 7273; // 72.73%
        uint256 distributionAccumulatorA = 2087; // 20.87%
        uint256 distributionVeSdtFeeProxyA = 640; // 6.4%

        uint256 distributionDaoB = 6000; // 60%
        uint256 distributionAccumulatorB = 3000; // 30%
        uint256 distributionVeSdtFeeProxyB = 1000; // 10%

        uint256 distributionDaoC = 100; // 1%
        uint256 distributionAccumulatorC = 500; // 5%
        uint256 distributionVeSdtFeeProxyC = 9400; // 94%

        // One accumulator for each token
        vm.startPrank(governance);
        feeReceiver.setRewardTokenAndDistribution(
            address(tokenA), accumulator, distributionDaoA, distributionAccumulatorA, distributionVeSdtFeeProxyA
        );
        feeReceiver.setRewardTokenAndDistribution(
            address(tokenB), address(0x1), distributionDaoB, distributionAccumulatorB, distributionVeSdtFeeProxyB
        );
        feeReceiver.setRewardTokenAndDistribution(
            address(tokenC), address(0x2), distributionDaoC, distributionAccumulatorC, distributionVeSdtFeeProxyC
        );
        vm.stopPrank();

        // Token A
        vm.prank(accumulator);
        feeReceiver.distribute(address(tokenA));

        assertEq(tokenA.balanceOf(dao), amountA * distributionDaoA / 10_000);
        assertEq(tokenA.balanceOf(accumulator), amountA * distributionAccumulatorA / 10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amountA * distributionVeSdtFeeProxyA / 10_000);

        // Assert does not touched other tokens
        assertEq(tokenB.balanceOf(address(feeReceiver)), amountB);
        assertEq(tokenC.balanceOf(address(feeReceiver)), amountC);

        // Token B
        vm.prank(address(0x1));
        feeReceiver.distribute(address(tokenB));

        assertEq(tokenA.balanceOf(dao), amountA * distributionDaoA / 10_000);
        assertEq(tokenA.balanceOf(accumulator), amountA * distributionAccumulatorA / 10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amountA * distributionVeSdtFeeProxyA / 10_000);

        assertEq(tokenB.balanceOf(dao), amountB * distributionDaoB / 10_000);
        assertEq(tokenB.balanceOf(address(0x1)), amountB * distributionAccumulatorB / 10_000);
        assertEq(tokenB.balanceOf(veSdtFeeProxy), amountB * distributionVeSdtFeeProxyB / 10_000);

        // Assert does not touched other tokens
        assertEq(tokenC.balanceOf(address(feeReceiver)), amountC);

        // Token C
        vm.prank(address(0x2));
        feeReceiver.distribute(address(tokenC));

        assertEq(tokenA.balanceOf(dao), amountA * distributionDaoA / 10_000);
        assertEq(tokenA.balanceOf(accumulator), amountA * distributionAccumulatorA / 10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amountA * distributionVeSdtFeeProxyA / 10_000);

        assertEq(tokenB.balanceOf(dao), amountB * distributionDaoB / 10_000);
        assertEq(tokenB.balanceOf(address(0x1)), amountB * distributionAccumulatorB / 10_000);
        assertEq(tokenB.balanceOf(veSdtFeeProxy), amountB * distributionVeSdtFeeProxyB / 10_000);

        assertEq(tokenC.balanceOf(dao), amountC * distributionDaoC / 10_000);
        assertEq(tokenC.balanceOf(address(0x2)), amountC * distributionAccumulatorC / 10_000);
        assertEq(tokenC.balanceOf(veSdtFeeProxy), amountC * distributionVeSdtFeeProxyC / 10_000);
    }

    ////////////////////////////////////////////////////////////
    /// --- REVERTS ---
    ////////////////////////////////////////////////////////////

    function test_unauthorizedTransferGovernance() public {
        vm.expectRevert(FeeDistributionReceiver.GOVERNANCE.selector);
        feeReceiver.transferGovernance(address(0x4));

        vm.prank(address(0x4));
        vm.expectRevert(FeeDistributionReceiver.FUTURE_GOVERNANCE.selector);
        feeReceiver.acceptGovernance();
    }

    function test_governanceAddressZero() public {
        vm.expectRevert(FeeDistributionReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.transferGovernance(address(0));
    }

    function test_unauthorizedSetRewardTokenAndRepartition() public {
        vm.expectRevert(FeeDistributionReceiver.GOVERNANCE.selector);
        feeReceiver.setRewardTokenAndDistribution(address(tokenA), accumulator, 2_500, 5_000, 2_500);

        vm.expectRevert(FeeDistributionReceiver.GOVERNANCE.selector);
        feeReceiver.setDistribution(accumulator, 1_000, 8_000, 1_000);
    }

    function test_unknownAccumulatorForSplit() public {
        vm.expectRevert(FeeDistributionReceiver.ACCUMULATOR_NOT_SET.selector);
        feeReceiver.distribute(address(tokenA));
    }

    function test_invalidFeeOnSetRewardTokenAndRepartition() public {
        vm.expectRevert(FeeDistributionReceiver.INVALID_FEE.selector);
        vm.prank(governance);
        feeReceiver.setRewardTokenAndDistribution(address(tokenA), accumulator, 2_500, 5_000, 2_501);
    }

    function test_invalidFeeOnSetRepartition() public {
        vm.prank(governance);
        feeReceiver.setRewardTokenAndDistribution(address(tokenA), accumulator, 2_500, 5_000, 2_500);

        vm.expectRevert(FeeDistributionReceiver.INVALID_FEE.selector);
        vm.prank(governance);
        feeReceiver.setDistribution(address(tokenA), 0, 40, 100);
    }

    function test_zeroAddresses() public {
        vm.expectRevert(FeeDistributionReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.setRewardTokenAndDistribution(address(0), accumulator, 2_500, 5_000, 2_500);

        vm.expectRevert(FeeDistributionReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.setDao(address(0));

        vm.expectRevert(FeeDistributionReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.setVeSdtFeeProxy(address(0));
    }
}
