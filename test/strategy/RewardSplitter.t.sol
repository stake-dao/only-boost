// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {RewardSplitter} from "src/strategy/RewardSplitter.sol";
import {MockERC20} from "lib/solady/test/utils/mocks/MockERC20.sol";

contract RewardSplitterTest is Test {
    //MockERC20 public rewardToken;
    RewardSplitter public rewardSplitter;

    address public veSdtFeeProxy = address(0xBadC0de);
    address public dao = address(0xBA5EBA11);
    address public accumulator = address(0xBEA7ED);

    address public governance = address(0xB055);

    MockERC20 public tokenA = new MockERC20("Token A", "TKA", 18);
    MockERC20 public tokenB = new MockERC20("Token B", "TKB", 16);
    MockERC20 public tokenC = new MockERC20("Token C", "TKC", 8);

    function setUp() public {
        rewardSplitter = new RewardSplitter(governance);
    }

    function test_initialSetup() public view {
        assertEq(rewardSplitter.governance(), governance);
        assertEq(rewardSplitter.futureGovernance(), address(0));
    }

    ////////////////////////////////////////////////////////////
    /// --- GOVERNANCE ---
    ////////////////////////////////////////////////////////////

    function test_transferGovernance() public {
        vm.prank(governance);
        rewardSplitter.transferGovernance(address(0x4));
        assertEq(rewardSplitter.futureGovernance(), address(0x4));
    }

    function test_acceptGovernance() public {
        vm.prank(governance);
        rewardSplitter.transferGovernance(address(0x4));

        vm.prank(address(0x4));
        rewardSplitter.acceptGovernance();
        assertEq(rewardSplitter.governance(), address(0x4));
        assertEq(rewardSplitter.futureGovernance(), address(0));
    }

    function test_setRepartition() public {
        vm.prank(governance);
                
        address[] memory receivers = new address[](3);
        uint256[] memory fees = new uint256[](3);

        receivers[0] = dao;
        fees[0] = 2_500;

        receivers[1] = accumulator;
        fees[1] = 5_000;

        receivers[2] = veSdtFeeProxy;
        fees[2] = 2_500;

        rewardSplitter.setRepartition(address(tokenA), receivers, fees);

        (address[] memory resultReceivers, uint256[] memory resultFees) = rewardSplitter.getRepartition(address(tokenA));

        assertEq(resultReceivers[0], dao);
        assertEq(resultFees[0], 2_500);

        assertEq(resultReceivers[1], accumulator);
        assertEq(resultFees[1], 5_000);

        assertEq(resultReceivers[2], veSdtFeeProxy);
        assertEq(resultFees[2], 2_500);
    }

    ////////////////////////////////////////////////////////////
    /// --- SPLIT FEE ---
    ////////////////////////////////////////////////////////////


    function test_distributeFee(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 10_000);
        tokenA.mint(address(rewardSplitter), amount);

        address[] memory receivers = new address[](3);
        uint256[] memory fees = new uint256[](3);

        receivers[0] = dao;
        fees[0] = 2_500;

        receivers[1] = accumulator;
        fees[1] = 5_000;

        receivers[2] = veSdtFeeProxy;
        fees[2] = 2_500;



        vm.startPrank(governance);
        rewardSplitter.setRepartition(address(tokenA), receivers, fees);
        vm.stopPrank();

        rewardSplitter.split(address(tokenA));

        assertEq(tokenA.balanceOf(dao), amount * 25 / 100);
        assertEq(tokenA.balanceOf(accumulator), amount * 50 / 100);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amount * 25 / 100);
    }


    function test_distributeFeeWithOneZero(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 10_000);
        tokenA.mint(address(rewardSplitter), amount);

        address[] memory receivers = new address[](3);
        uint256[] memory fees = new uint256[](3);

        receivers[0] = dao;
        fees[0] = 0;

        receivers[1] = accumulator;
        fees[1] = 5_000;

        receivers[2] = veSdtFeeProxy;
        fees[2] = 5_000;



        vm.startPrank(governance);
        rewardSplitter.setRepartition(address(tokenA), receivers, fees);
        vm.stopPrank();

        vm.prank(accumulator);
        rewardSplitter.split(address(tokenA));

        assertEq(tokenA.balanceOf(dao), 0);
        assertEq(tokenA.balanceOf(accumulator), amount * 50 / 100);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amount * 50 / 100);
    }


    function test_distributeLotOfSplits(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 10_000);
        tokenA.mint(address(rewardSplitter), amount);

        address[] memory receivers = new address[](10);
        uint256[] memory fees = new uint256[](10);

        receivers[0] = dao;
        fees[0] = 1000;

        receivers[1] = accumulator;
        fees[1] = 1000;

        receivers[2] = veSdtFeeProxy;
        fees[2] = 1000;

        receivers[3] = address(0x1);
        fees[3] = 1000;

        receivers[4] = address(0x2);
        fees[4] = 1000;

        receivers[5] = address(0x3);
        fees[5] = 1000;

        receivers[6] = address(0x4);
        fees[6] = 1000;

        receivers[7] = address(0x5);
        fees[7] = 1000;

        receivers[8] = address(0x6);
        fees[8] = 1000;

        receivers[9] = address(0x7);
        fees[9] = 1000;



        vm.startPrank(governance);
        rewardSplitter.setRepartition(address(tokenA), receivers, fees);
        vm.stopPrank();

        rewardSplitter.split(address(tokenA));

        assertEq(tokenA.balanceOf(dao), amount*1000/10_000);
        assertEq(tokenA.balanceOf(accumulator), amount*1000/10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amount*1000/10_000);
        assertEq(tokenA.balanceOf(address(0x1)), amount*1000/10_000);
        assertEq(tokenA.balanceOf(address(0x2)), amount*1000/10_000);
        assertEq(tokenA.balanceOf(address(0x3)), amount*1000/10_000);
        assertEq(tokenA.balanceOf(address(0x4)), amount*1000/10_000);
        assertEq(tokenA.balanceOf(address(0x5)), amount*1000/10_000);
        assertEq(tokenA.balanceOf(address(0x6)), amount*1000/10_000);
        assertEq(tokenA.balanceOf(address(0x7)), amount*1000/10_000);
    }

    function test_distributeFeeMultipleRewardTokens(uint256 amountA, uint256 amountB, uint256 amountC) public {
        vm.assume(amountA < type(uint256).max / 10_000);
        vm.assume(amountB < type(uint256).max / 10_000);
        vm.assume(amountC < type(uint256).max / 10_000);

        vm.assume(amountA > 0);
        vm.assume(amountB > 0);
        vm.assume(amountC > 0);

        tokenA.mint(address(rewardSplitter), amountA);
        tokenB.mint(address(rewardSplitter), amountB);
        tokenC.mint(address(rewardSplitter), amountC);

        address[] memory receivers = new address[](3);
        uint256[] memory feesA = new uint256[](3);
        uint256[] memory feesB = new uint256[](3);
        uint256[] memory feesC = new uint256[](3);

        receivers[0] = dao;
        receivers[1] = accumulator;
        receivers[2] = veSdtFeeProxy;

        // Token A fees
        feesA[0] = 7273; // 72.73%
        feesA[1] = 2087; // 20.87%
        feesA[2] = 640;  // 6.4%

        // Token B fees
        feesB[0] = 6000; // 60%
        feesB[1] = 3000; // 30%
        feesB[2] = 1000; // 10%

        // Token C fees
        feesC[0] = 100;  // 1%
        feesC[1] = 500;  // 5%
        feesC[2] = 9400; // 94%

        vm.startPrank(governance);
        rewardSplitter.setRepartition(address(tokenA), receivers, feesA);
        rewardSplitter.setRepartition(address(tokenB), receivers, feesB);
        rewardSplitter.setRepartition(address(tokenC), receivers, feesC);
        vm.stopPrank();

        // Token A
        rewardSplitter.split(address(tokenA));
        assertEq(tokenA.balanceOf(dao), amountA * 7273 / 10_000);
        assertEq(tokenA.balanceOf(accumulator), amountA * 2087 / 10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amountA * 640 / 10_000);

        // Token B
        rewardSplitter.split(address(tokenB));
        assertEq(tokenB.balanceOf(dao), amountB * 6000 / 10_000);
        assertEq(tokenB.balanceOf(accumulator), amountB * 3000 / 10_000);
        assertEq(tokenB.balanceOf(veSdtFeeProxy), amountB * 1000 / 10_000);

        // Token C
        rewardSplitter.split(address(tokenC));
        assertEq(tokenC.balanceOf(dao), amountC * 100 / 10_000);
        assertEq(tokenC.balanceOf(accumulator), amountC * 500 / 10_000);
        assertEq(tokenC.balanceOf(veSdtFeeProxy), amountC * 9400 / 10_000);
    
    }

    ////////////////////////////////////////////////////////////
    /// --- REVERTS ---
    ////////////////////////////////////////////////////////////

    function test_unauthorizedTransferGovernance() public {
        vm.expectRevert(RewardSplitter.GOVERNANCE.selector);
        rewardSplitter.transferGovernance(address(0x4));

        vm.prank(address(0x4));
        vm.expectRevert(RewardSplitter.FUTURE_GOVERNANCE.selector);
        rewardSplitter.acceptGovernance();
    }

    function test_governanceAddressZero() public {
        vm.expectRevert(RewardSplitter.ZERO_ADDRESS.selector);
        vm.prank(governance);
        rewardSplitter.transferGovernance(address(0));
    }

    function test_unauthorizedSetRepartition() public {
        vm.expectRevert(RewardSplitter.GOVERNANCE.selector);
        rewardSplitter.setRepartition(address(tokenA), new address[](3), new uint256[](3));
    }
    function test_invalidFeeOnSetRepartition() public {
        address[] memory receivers = new address[](3);
        uint256[] memory fees = new uint256[](3);

        receivers[0] = dao;
        fees[0] = 2_500;

        receivers[1] = accumulator;
        fees[1] = 5_000;

        receivers[2] = veSdtFeeProxy;
        fees[2] = 500;

        vm.expectRevert(RewardSplitter.INVALID_FEE.selector);
        vm.prank(governance);
        rewardSplitter.setRepartition(address(tokenA), receivers, fees);
    }

    function test_invalidRepartitionOnSetRepartition() public {
        vm.expectRevert(RewardSplitter.INVALID_REPARTITION.selector);
        vm.prank(governance);
        rewardSplitter.setRepartition(address(tokenA), new address[](0), new uint256[](0));

        vm.expectRevert(RewardSplitter.INVALID_REPARTITION.selector);
        vm.prank(governance);
        rewardSplitter.setRepartition(address(tokenA), new address[](3), new uint256[](2));
    }

    function test_zeroAddresses() public {
        vm.expectRevert(RewardSplitter.ZERO_ADDRESS.selector);
        vm.prank(governance);
        rewardSplitter.setRepartition(address(0), new address[](3), new uint256[](3));
    }

}
