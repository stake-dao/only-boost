// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "test/BaseTest.t.sol";

contract Handler is BaseTest {
    ERC20 public token;

    uint256 public numDeposit;
    uint256 public numWithdraw;

    constructor(
        CurveStrategy _curveStrategy,
        FallbackConvexCurve _fallbackConvexCurve,
        FallbackConvexFrax _fallbackConvexFrax,
        Optimizor _optimizor,
        ERC20 _token
    ) {
        curveStrategy = _curveStrategy;
        fallbackConvexCurve = _fallbackConvexCurve;
        fallbackConvexFrax = _fallbackConvexFrax;
        optimizor = _optimizor;
        token = _token;
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 0, 10_000e18);
        numDeposit += 1;
        console.log("Deposit", amount);
        deal(address(token), address(this), amount);
        token.approve(address(curveStrategy), amount);
        curveStrategy.deposit(address(token), amount);
    }

    function withdraw(uint256 amount) external {
        uint256 balanceOfStakeDAO = ERC20(gauges[address(token)]).balanceOf(LOCKER_STAKEDAO);
        uint256 balanceOfConvexCurve = fallbackConvexCurve.balanceOf(address(token));
        uint256 balanceOfConvexFrax = optimizor.isConvexFraxKilled() ? 0 : fallbackConvexFrax.balanceOf(address(token));
        uint256 maxToWithdraw = balanceOfStakeDAO + balanceOfConvexCurve + balanceOfConvexFrax;
        amount = bound(amount, 0, maxToWithdraw);
        numWithdraw += 1;
        console.log("Withdraw", amount);
        curveStrategy.withdraw(address(token), amount);
        token.transfer(msg.sender, amount);
    }
}
