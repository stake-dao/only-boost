// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

contract Handler is BaseTest {
    ERC20 public token;

    uint256 public numDeposit;
    uint256 public numWithdraw;

    uint256 public amountDeposited;

    uint256 public balanceBeforeStakeDAO;

    constructor(
        CurveStrategy _curveStrategy,
        FallbackConvexCurve _fallbackConvexCurve,
        Optimizor _optimizor,
        ERC20 _token
    ) {
        curveStrategy = _curveStrategy;
        fallbackConvexCurve = _fallbackConvexCurve;
        optimizor = _optimizor;
        token = _token;
        balanceBeforeStakeDAO = balanceStakeDAO();
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 0, 100_000e18);
        deal(address(token), address(this), amount);

        token.approve(address(curveStrategy), amount);

        numDeposit += 1;
        amountDeposited += amount;

        curveStrategy.deposit(address(token), amount);
    }

    function withdraw(uint256 amount) external {
        uint256 balanceOfStakeDAO = balanceStakeDAO() - balanceBeforeStakeDAO;
        uint256 balanceOfConvexCurve = fallbackConvexCurve.balanceOf(address(token));
        uint256 maxToWithdraw = balanceOfStakeDAO + balanceOfConvexCurve;
        amount = bound(amount, 0, maxToWithdraw);

        numWithdraw += 1;
        amountDeposited -= amount;

        curveStrategy.withdraw(address(token), amount);
        token.transfer(msg.sender, amount);
    }

    function balanceStakeDAO() public view returns (uint256) {
        return ERC20(gauges[address(CRV3)]).balanceOf(LOCKER);
    }

    function balanceFallbackConvexCurve() public view returns (uint256) {
        return fallbackConvexCurve.balanceOf(address(CRV3));
    }
}
