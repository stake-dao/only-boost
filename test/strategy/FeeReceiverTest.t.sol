// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {FeeReceiver} from "src/strategy/FeeReceiver.sol";
import {MockERC20} from "lib/solady/test/utils/mocks/MockERC20.sol";

contract FeeReceiverTest is Test {
    //MockERC20 public rewardToken;
    FeeReceiver public feeReceiver;

    address public veSdtFeeProxy = address(0xBadC0de);
    address public dao = address(0xBA5EBA11);
    address public accumulator = address(0xBEA7ED);

    address public governance = address(0xB055);

    MockERC20 public tokenA = new MockERC20("Token A", "TKA", 18);
    MockERC20 public tokenB = new MockERC20("Token B", "TKB", 16);
    MockERC20 public tokenC = new MockERC20("Token C", "TKC", 8);

    function setUp() public {
        feeReceiver = new FeeReceiver(governance, veSdtFeeProxy, dao);
        }

    function test_getBytecode() public {
        address owner = address(0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063);
        bytes memory bytecode = abi.encodePacked(type(FeeReceiver).creationCode, abi.encode(0x90569D8A1cF801709577B24dA526118f0C83Fc75, owner, owner));
        console.logBytes32(keccak256(bytecode));
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

    function test_setRewardTokenAndRepartition() public {
        vm.prank(governance);
        feeReceiver.setRewardTokenAndRepartition(accumulator, address(tokenA), 2_500, 5_000, 2_500);
        assertEq(feeReceiver.accumulatorRewardToken(accumulator), address(tokenA));

        (uint256 daoPart, uint256 accumulatorPart, uint256 veSdtFeeProxyPart) =
            feeReceiver.accumulatorRepartition(accumulator);
        assertEq(daoPart, 2_500);
        assertEq(accumulatorPart, 5_000);
        assertEq(veSdtFeeProxyPart, 2_500);

        // Changing using setRepartition
        vm.prank(governance);
        feeReceiver.setRepartition(accumulator, 1_000, 8_000, 1_000);

        (daoPart, accumulatorPart, veSdtFeeProxyPart) = feeReceiver.accumulatorRepartition(accumulator);

        assertEq(daoPart, 1_000);
        assertEq(accumulatorPart, 8_000);
        assertEq(veSdtFeeProxyPart, 1_000);
    }

    ////////////////////////////////////////////////////////////
    /// --- SPLIT FEE ---
    ////////////////////////////////////////////////////////////

    function test_splitFee(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 10_000);
        tokenA.mint(address(feeReceiver), amount);

        vm.startPrank(governance);
        feeReceiver.setRewardTokenAndRepartition(accumulator, address(tokenA), 2_500, 5_000, 2_500);
        vm.stopPrank();

        vm.prank(accumulator);
        feeReceiver.split();

        assertEq(tokenA.balanceOf(dao), amount * 25 / 100);
        assertEq(tokenA.balanceOf(accumulator), amount * 50 / 100);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amount * 25 / 100);
    }

    function test_splitFeeMultipleRewardTokens(uint256 amountA, uint256 amountB, uint256 amountC) public {
        vm.assume(amountA < type(uint256).max / 10_000);
        vm.assume(amountB < type(uint256).max / 10_000);
        vm.assume(amountC < type(uint256).max / 10_000);

        vm.assume(amountA > 0);
        vm.assume(amountB > 0);
        vm.assume(amountC > 0);

        tokenA.mint(address(feeReceiver), amountA);
        tokenB.mint(address(feeReceiver), amountB);
        tokenC.mint(address(feeReceiver), amountC);

        uint256 repartitionDaoA = 7273; // 72.73%
        uint256 repartitionAccumulatorA = 2087; // 20.87%
        uint256 repartitionVeSdtFeeProxyA = 640; // 6.4%

        uint256 repartitionDaoB = 6000; // 60%
        uint256 repartitionAccumulatorB = 3000; // 30%
        uint256 repartitionVeSdtFeeProxyB = 1000; // 10%

        uint256 repartitionDaoC = 100; // 1%
        uint256 repartitionAccumulatorC = 500; // 5%
        uint256 repartitionVeSdtFeeProxyC = 9400; // 94%

        // One accumulator for each token
        vm.startPrank(governance);
        feeReceiver.setRewardTokenAndRepartition(
            accumulator, address(tokenA), repartitionDaoA, repartitionAccumulatorA, repartitionVeSdtFeeProxyA
        );
        feeReceiver.setRewardTokenAndRepartition(
            address(0x1), address(tokenB), repartitionDaoB, repartitionAccumulatorB, repartitionVeSdtFeeProxyB
        );
        feeReceiver.setRewardTokenAndRepartition(
            address(0x2), address(tokenC), repartitionDaoC, repartitionAccumulatorC, repartitionVeSdtFeeProxyC
        );
        vm.stopPrank();

        // Token A
        vm.prank(accumulator);
        feeReceiver.split();

        assertEq(tokenA.balanceOf(dao), amountA * repartitionDaoA / 10_000);
        assertEq(tokenA.balanceOf(accumulator), amountA * repartitionAccumulatorA / 10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amountA * repartitionVeSdtFeeProxyA / 10_000);

        // Assert does not touched other tokens
        assertEq(tokenB.balanceOf(address(feeReceiver)), amountB);
        assertEq(tokenC.balanceOf(address(feeReceiver)), amountC);

        // Token B
        vm.prank(address(0x1));
        feeReceiver.split();

        assertEq(tokenA.balanceOf(dao), amountA * repartitionDaoA / 10_000);
        assertEq(tokenA.balanceOf(accumulator), amountA * repartitionAccumulatorA / 10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amountA * repartitionVeSdtFeeProxyA / 10_000);

        assertEq(tokenB.balanceOf(dao), amountB * repartitionDaoB / 10_000);
        assertEq(tokenB.balanceOf(address(0x1)), amountB * repartitionAccumulatorB / 10_000);
        assertEq(tokenB.balanceOf(veSdtFeeProxy), amountB * repartitionVeSdtFeeProxyB / 10_000);

        // Assert does not touched other tokens
        assertEq(tokenC.balanceOf(address(feeReceiver)), amountC);

        // Token C
        vm.prank(address(0x2));
        feeReceiver.split();

        assertEq(tokenA.balanceOf(dao), amountA * repartitionDaoA / 10_000);
        assertEq(tokenA.balanceOf(accumulator), amountA * repartitionAccumulatorA / 10_000);
        assertEq(tokenA.balanceOf(veSdtFeeProxy), amountA * repartitionVeSdtFeeProxyA / 10_000);

        assertEq(tokenB.balanceOf(dao), amountB * repartitionDaoB / 10_000);
        assertEq(tokenB.balanceOf(address(0x1)), amountB * repartitionAccumulatorB / 10_000);
        assertEq(tokenB.balanceOf(veSdtFeeProxy), amountB * repartitionVeSdtFeeProxyB / 10_000);

        assertEq(tokenC.balanceOf(dao), amountC * repartitionDaoC / 10_000);
        assertEq(tokenC.balanceOf(address(0x2)), amountC * repartitionAccumulatorC / 10_000);
        assertEq(tokenC.balanceOf(veSdtFeeProxy), amountC * repartitionVeSdtFeeProxyC / 10_000);
    }

    ////////////////////////////////////////////////////////////
    /// --- REVERTS ---
    ////////////////////////////////////////////////////////////

    function test_unauthorizedTransferGovernance() public {
        vm.expectRevert(FeeReceiver.GOVERNANCE.selector);
        feeReceiver.transferGovernance(address(0x4));

        vm.prank(address(0x4));
        vm.expectRevert(FeeReceiver.FUTURE_GOVERNANCE.selector);
        feeReceiver.acceptGovernance();
    }

    function test_governanceAddressZero() public {
        vm.expectRevert(FeeReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.transferGovernance(address(0));
    }

    function test_unauthorizedSetRewardTokenAndRepartition() public {
        vm.expectRevert(FeeReceiver.GOVERNANCE.selector);
        feeReceiver.setRewardTokenAndRepartition(accumulator, address(tokenA), 2_500, 5_000, 2_500);

        vm.expectRevert(FeeReceiver.GOVERNANCE.selector);
        feeReceiver.setRepartition(accumulator, 1_000, 8_000, 1_000);
    }

    function test_unknownAccumulatorForSplit() public {
        vm.expectRevert(FeeReceiver.UNKNOWN_ACCUMULATOR.selector);
        feeReceiver.split();
    }

    function test_invalidFeeOnSetRewardTokenAndRepartition() public {
        vm.expectRevert(FeeReceiver.INVALID_FEE.selector);
        vm.prank(governance);
        feeReceiver.setRewardTokenAndRepartition(accumulator, address(tokenA), 2_500, 5_000, 2_501);
    }

    function test_invalidFeeOnSetRepartition() public {
        vm.prank(governance);
        feeReceiver.setRewardTokenAndRepartition(accumulator, address(tokenA), 2_500, 5_000, 2_500);

        vm.expectRevert(FeeReceiver.INVALID_FEE.selector);
        vm.prank(governance);
        feeReceiver.setRepartition(accumulator, 0, 40, 100);
    }

    function test_zeroAddresses() public {
        vm.expectRevert(FeeReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.setRewardTokenAndRepartition(address(0), address(tokenA), 2_500, 5_000, 2_500);

        vm.expectRevert(FeeReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.setRewardTokenAndRepartition(accumulator, address(0), 2_500, 5_000, 2_500);

        vm.expectRevert(FeeReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.setDao(address(0));

        vm.expectRevert(FeeReceiver.ZERO_ADDRESS.selector);
        vm.prank(governance);
        feeReceiver.setVeSdtFeeProxy(address(0));
    }
}
