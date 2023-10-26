<table>
    <tr><th></th><th></th></tr>
    <tr>
        <td><img src="https://styles.redditmedia.com/t5_45q11m/styles/communityIcon_iqrykrjom8p61.png" width="250" height="250" /></td>
        <td>
            <h1>StakeDAO Audit Report</h1>
            <h2>Strategy Optimizor</h2>
            <p>Prepared by: Zach Obront, Independent Security Researcher</p>
            <p>Date: June 10 to 21, 2023</p>
        </td>
    </tr>
</table>

# About **StakeDAO's Strategy Optimizor**

Stake DAO is a non-custodial platform providing the best yield on governance and LP tokens. Strategy Optimizor is a new product that automatically optimizes distribution of funds between Stake DAO and Convex in order to maximize boost.

# About **zachobront**

Zach Obront is an independent smart contract security researcher. He serves as a Lead Senior Watson at Sherlock, a Security Researcher at Spearbit, and has identified multiple critical severity bugs in the wild, including in a Top 5 Protocol on Immunefi. You can say hi on Twitter at [@zachobront](http://twitter.com/zachobront).

# Summary & Scope

The [stake-dao/strategy-optimizor](https://github.com/stake-dao/strategy-optimizor) repository was audited at commit [3ecabb5e4dd7ae24c7a1652fee63df38ed6cf6b4](https://github.com/stake-dao/strategy-optimizor/tree/3ecabb5e4dd7ae24c7a1652fee63df38ed6cf6b4).

The following contracts were in scope:
- src/CurveStrategy.sol
- src/Optimizor.sol
- src/BaseFallback.sol
- src/FallbackConvexCurve.sol
- src/FallbackConvexFrax.sol

After completion of the fixes, the [6d2929fa8a68b02bec39025986159f1186576229](https://github.com/stake-dao/strategy-optimizor/tree/6d2929fa8a68b02bec39025986159f1186576229) commit was reviewed.


# Summary of Findings

| Identifier     | Title                        | Severity      | Fixed |
| ------ | ---------------------------- | ------------- | ----- |
| C-01 | Hardcoded vlCVXTotal adjustment allows attacker to brick or create Convex-only Optimizor | Critical | ✓ |
| C-02 | Optimizor will only withdraw once per `lockingIntervalSec` from FallbackConvexFrax | Critical | ✓ |
| H-01 | Optimizor's core formula misallocates deposits when Convex has full 2.5x boost | High | ✓ |
| H-02 | When CVX totalSupply gets close to max supply, Optimizor will brick all Curve Convex calculations | High | ✓ |
| H-03 | Cached values can be manipulated by Convex | High | ✓ |
| H-04 | Withdrawals should always come from Convex Curve before Convex Frax, not vice versa | High | ✓ |
| M-01 | `migrateLP()` transfers LP tokens to governance, rather than the vault | Medium | ✓ |
| M-02 | If any fees are set to zero, `claim()` will be bricked | Medium | ✓ |
| M-03 | `claim3Crv()` function will always revert whenever notify argument is passed as `true` | Medium | ✓ |
| M-04 | If any Convex pool ever allows staking for other users, `killConvexFrax()` can be bricked | Medium | ✓ |
| M-05 | Turning off Optimizor can lead to funds being stuck in Convex | Medium | ✓ |
| M-06 | If `claimOnWithdraw` flag is set to true, FallbackConvexCurve will not distribute rewards | Medium | ✓ |
| M-07 | No `rebalance()` function is implemented | Medium | |
| M-08 | If Optimizor is deployed on a chain where Frax PID 0 is a Curve token, withdrawals can malfunction | Medium | ✓ |
| L-01 | CVX price estimate should include adjustment parameter | Low | ✓ |
| L-02 | FXS should be hardcoded into `getRewardTokens()` | Low | ✓ |
| L-03 | If `lockingIntervalSec` is lowered before `killConvexFrax()` is called, tokens can be locked | Low | ✓ |
| L-04 | `stakeLockedCurveLp()` does not appear to consistently return kekId | Low | ✓ |
| L-05 | StakeDAO admin can divert deposits to its own locker | Low |  |
| I-01 | Formula in section 4.2 of whitepaper flips numerator and denominator | Informational | ✓ |
| I-02 | Incorrect rewardsTokens length check in `claimRewards()` | Informational | ✓ |
| I-03 | Solidity 0.8.20 is unsafe on non-mainnet chains when defaulting to Shanghai | Informational | ✓ |
| G-01 | Optimizor caches all values, even when caching is turned off | Gas | ✓ |
| G-02 | Gas can be saved by not using uint8 as a loop counter | Gas | ✓ |
| G-03 | Can save gas by caching vault address in Frax `withdraw()` function | Gas | ✓ |

# Detailed Findings

## [C-01] Hardcoded vlCVXTotal adjustment allows attacker to brick or create Convex-only Optimizor

When `Optimizor.sol` calculates the `optimalAmount`, it requires a `boost` value. This boost represents an adjustment to the calculation to account for the CVX incentives earned on Convex.

Since these rewards are paid in CVX, the whitepaper shows that we can use the veCRV backing of vlCVX to estimate the exchange rate between the two, thereby converting the CVX rewards into CRV so they fit into our calculations.

`CVX/CRV price ratio is proportionate to (total veCRV owned by Convex / CVX locked in vlCVX contract)`

In order to get an exact calculation from this proportion, the formula in `Optimizor.sol` adjusts by 1e7:
```solidity
uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply() * 1e7;
uint256 boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);
```
If we check the live values of the contracts, this calculation works correctly:
- veCRV owned by Convex = 294mm
- CVX locked in vlCVX contract = 6
- vlCVX with adjustment = 60mm
- CVX/CRV ratio = 294mm/60mm = 4.916 (close to the actual value of 5)

However, you'll note two issues with this:

1) Needing to adjust by 1e7 implies that only 0.00001% of the veCRV is actually backing the vlCVX. That makes it seem like a poor peg to ensure the ratios stay aligned.

2) Having only 6 CVX in the contract seems suspicious.

It turns out that [the vlCVX contract was migrated in March 2022](https://convexfinance.medium.com/vote-locked-cvx-contract-migration-8546b3d9a38c), and the current `Optimizor.sol` contract is using the deprecated version. This is why the 1e7 adjustment was needed, to account for the very low CVX locked in the old contract.

### Attack Path

This error does not just lead to an inaccurate peg; it is highly abusable by an attacker.

This is because the vlCVX lock time only locked tokens for [a maximum of 16 weeks](https://docs.convexfinance.com/convexfinance/general-information/understanding-cvx/vote-locking), after which they can be kicked off by other users. Since the migration happened 15 months ago, all the 6 CVX remaining in the contract is vulnerable to be kicked off.

This allows an attacker to kick off the remaining CVX stakers, lowering the `lockedSupply()` and thus increasing the boost provided to Convex in the calculation. This allows them to perform two attacks:

1) If they kick off all the stakers except for the smallest one, the result will be an incredibly high boost. This will outweigh the StakeDAO benefits and result in all deposited LP tokens being routed to Convex.

2) If they kick off all the stakers, the result will be that the formula to calculate the boost will divide by 0 and will revert. This will brick the Optimizor.

### Proof of Concept

Here is a standalone Foundry fork test that can be run to verify that any attacker can kick off a remaining user, lowering locked supply and increasing boost.

Drop the following test file into the repo and run with `forge test --match-test testZach__KickExpiredLocks`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

interface VLCVX {
    function kickExpiredLocks(address account) external;
    function processExpiredLocks(bool _relock) external;
    function lockedSupply() external view returns (uint);
}

interface ERC20 {
    function balanceOf(address account) external view returns (uint);
    function totalSupply() external view returns (uint);
}

contract ZachTest is Test {

    function testZach__KickExpiredLocks() public {
        vm.createSelectFork("INSERT RPC URL");
        VLCVX vlcvx = VLCVX(0xD18140b4B819b895A3dba5442F959fA44994AF50);

        uint lockedSupplyBefore = vlcvx.lockedSupply();
        uint boostBefore = _calculateBoost();

        vlcvx.kickExpiredLocks(0x09c6872649Ce4f96D869e50a269E342333aE073a);

        uint lockedSupplyAfter = vlcvx.lockedSupply();
        uint boostAfter = _calculateBoost();

        emit log_string("Locked Supply (Before & After)");
        emit log_uint(lockedSupplyBefore);
        emit log_uint(lockedSupplyAfter);

        emit log_string("******");
        emit log_string("Boost (Before & After)");
        emit log_uint(boostBefore);
        emit log_uint(boostAfter);
    }

    function _calculateBoost() internal view returns (uint boost) {
        address LOCKER_CVX = 0xD18140b4B819b895A3dba5442F959fA44994AF50;
        address LOCKER_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
        address LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;
        ERC20 CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = VLCVX(LOCKER_CVX).lockedSupply() * 1e7;

        boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);
    }
}
```

### Recommendations

1) The vlCVX contract should be changed to the correct contract address: `0x72a19342e8F1838460eBFCCEf09F6585e32db86E`

2) This would allow getting rid of the adjustment for a ratio of 294mm / 56mm = 5.25 (unless an adjustment was used during the historical calculations regarding the peg, in which case that same adjustment should be used).

3) In the event that this ratio stops holding, there is no mechanism in `Optimizor.sol` to adjust for it. I would suggest adding an adjustment mechanism (similar to the one used for Convex Frax rewards) to ensure this ratio stays in line, as recommended in #27.

### Review

Fixed as recommended in [PR #37](https://github.com/stake-dao/strategy-optimizor/pull/37/).

## [C-02] Optimizor will only withdraw once per `lockingIntervalSec` from FallbackConvexFrax

When withdrawals are processed via the Optimizor, they begin by taking the balances of StakeDAO, Convex Curve and Convex Frax.
- StakeDAO: The balance of the liquidity gauge tokens held by the locker.
- Convex Curve: The balance of the CRV Rewards tokens held by the fallback contract.
- Convex Frax: The unlocked liquidity held by the fallback's vault.

If there are tokens in Convex Frax, the Optimizor is intended to remove them in full before tokens are removed from the other lockers.

This works because, when tokens are deposited via Convex Frax, we call `lockAdditionalCurveLp()` on the vault, which does not extend the lock time. This allows the lock time to be set upon the first deposit, and maintained.

However, when tokens are withdrawn, different logic is used, which resets the locking period to `lockingIntervalSec` (currently 7 days):
```solidity
function withdraw(address token, uint256 amount) external override requiresAuth {
    // Cache the pid
    uint256 pid = pids[stkTokens[token]].pid;

    // Release all the locked curve lp
    IStakingProxyConvex(vaults[pid]).withdrawLockedAndUnwrap(kekIds[vaults[pid]]);
    // Set kekId to 0
    delete kekIds[vaults[pid]];

    // Transfer the curve lp back to user
    ERC20(token).safeTransfer(address(curveStrategy), amount);

    emit Withdrawn(token, amount);

    // If there is remaining curve lp, stake it back
    uint256 remaining = ERC20(token).balanceOf(address(this));

    if (remaining == 0) return;

    // Safe approve lp token to personal vault
    ERC20(token).safeApprove(vaults[pid], remaining);
    // Stake back the remaining curve lp
    kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);

    emit Redeposited(token, remaining);
}
```

The result is that, when `curveStrategy.withdraw()` is called while there are any unlocked tokens in Convex Frax:

1) We will get a positive value from `balanceOf()`, and use Convex Frax for our withdrawal.

2) Using the above function, we will withdraw all tokens, redeposit the difference, and our locking window will be reset to `lockingIntervalSec`.

3) Any withdrawals in the next `lockingIntervalSec` will return a Convex Frax balance of 0, and will withdraw from StakeDAO instead.

This will lead to Convex Frax deposits being overweighted relative to StakeDAO deposits, harming the optimization of the protocol as well as the total funds directed towards StakeDAO.

The impact of this could be quite extreme, since it is possible that the withdrawal processed each `lockingIntervalSec` will be a small one that doesn't materially decrease the amount staked with Convex Frax.

### Malicious Attack

In an extreme case, this error could be abused by Convex, who could perform the following attack:

1) When a large user deposit is coming in via StakeDAO, front run it with their own deposit that will cause StakeDAO's boost to decrease to be on par with Convex Frax.

2) A portion of the large user deposit will be allocated to Convex Frax, instead of StakeDAO.

3) If there have been no withdrawals in the past `lockingIntervalSec`, withdraw a small amount in order to trigger a relocking of the Convex Frax tokens.

4) Withdraw the remainder of their deposit, which will all come out of the StakeDAO locker.

5) Repeat this pattern each time there is a large deposit to StakeDAO.

6) Every time the locking period expires (approximately once per week), use Flashbots to ensure they are the first transaction in the block and perform a small withdrawal to relock the tokens.

The result will be that large user deposits will be allocated partially to Convex Frax, and will not be able to be removed, regardless of the optimal ratio.

### Proof of Concept

The following test uses the testing setup in `CurveStrategy.t.sol` to compare the behaviors of performing a second withdrawal via Frax immediately vs waiting a week.

We can see that, when a second withdrawal is performed right away, the withdrawal comes from the StakeDAO locker, even though it should be coming from the Convex Frax fallback.

```solidity
function testZach__OnlyOneFraxWithdrawalPerWeek() public useFork(forkId1) {
    // === DEPOSIT PROCESS === //
    (uint256 partStakeDAO, uint256 partConvex) = _calculDepositAmount(ALUSD_FRAXBP, MAX, 1);
    _deposit(ALUSD_FRAXBP, partStakeDAO, partConvex);
    curveStrategy.withdraw(address(ALUSD_FRAXBP), partConvex / 2);

    uint snap = vm.snapshot();

    // First, let's see what happens if we withdraw immediately.
    uint before1 = ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER));
    curveStrategy.withdraw(address(ALUSD_FRAXBP), partConvex / 2);
    uint after1 = ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER));
    console.log("StakeDAO Withdrawals (Within 1 Week): ", before1 - after1);

    // Now, let's see what happens if we wait a week.
    vm.revertTo(snap);
    vm.warp(block.timestamp + fallbackConvexFrax.lockingIntervalSec());
    uint before2 = ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER));
    curveStrategy.withdraw(address(ALUSD_FRAXBP), partConvex / 2);
    uint after2 = ERC20(gauges[address(ALUSD_FRAXBP)]).balanceOf(address(LOCKER));
    console.log("StakeDAO Withdrawals (After 1 Week): ", before2 - after2);
}
```
```
Logs:
  StakeDAO Withdrawals (Within 1 Week):  500000000000000000000
  StakeDAO Withdrawals (After 1 Week):  0
```

### Recommendation

The withdrawal logic should change to handle two situations: (a) if all of the ConvexFrax deposits are being withdrawn, proceed or (b) if not all of the ConvexFrax deposits are being withdrawn, use the next option (ConvexCurve or StakeDAO).

This will lead to short term situations where ConvexFrax is overweighted.

We can then implement a `rebalance()` function that is allowed to withdraw from ConvexFrax, while rebalancing to the other pools optimally.

That would ensure that the once per `lockingIntervalSec` withdrawal is used to fully get the pool back into a balanced state, rather than being wasted or used to block other withdrawals, while leaving the pool misallocated.

Note: This also opens the door to a clever attack where the `rebalance()` call is sandwiched by a deposit and a withdrawal in order to keep Convex allocation high. To solve this, we likely need some mechanism to cap the speed of withdrawals, but we can discuss further in the fix review phase.

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.

## [H-01] Optimizor's core formula misallocates deposits when Convex has full 2.5x boost

On Page 5 of the whitepaper, it says:

> We can assume that when this balance is reached for a given gauge, neither Convex nor Stake DAO have maximum boost, which enables us to get rid of the min formula.

However, this assumption appears to be flawed.

The goal of the core Optimizor formula is to find the point at which:

```python
B*sd = (min(0.4bsd + 0.6S(wsd/W), bsd)) / 0.4bsd) * (1 - fsd)
B*cvx = (min(0.4bcvx + 0.6S(wcvx/W), bcvx)) / 0.4cvx) * (1 - fcvx + icvx)
B*sd < B*cvx
```

It is not safe to assume that any solution to this formula will not have the maximum boost.

As a trivial example of a place where this inequality might hold while both protocols have maximum boost, imagine that both sides have the maximum boost, but that `fsd = 1` (ie StakeDAO takes 100% fees). Now the left side of the equation is 0, while the right side is positive.

This is an extreme example, but it actually shines light on the real situation. If we plug in the current values, what we find is that `1 - fsd = 0.84`, while `1 - fcvx + icvx = 0.91`.

This means that, in the event that both sides of the equation ARE at the maximum 2.5x boost, the right side will be multiplied by the higher value (because Convex has lower fees offset by incentives), and all funds should be allocated to Convex.

However, because the formula assumes that this scenario should never happen, it outputs the wrong values in this situation.

Fundamentally, what is happening is that the Optimizor formula assumes that boost scales up infinitely, without a cap at 2.5x. That means that, even in the event where _in reality_ both protocols have a 2.5x boost, the formula believes that if StakeDAO has a lower `LP/veCRV` ratio, it should be the better investment, even though this better ratio doesn't actually change anything.

This leads to inaccurate calculations in situations where Convex has the full 2.5x boost, and is therefore strictly better.

### Proof of Concept

I took all the live values for the variables in the calculation and used them to create a `_calculateOptimalHardcoded()` function. Using an imaginary LP token with a `totalSupply = 1e18`, what we should find is that all funds should be sent to Convex until Convex holds more than 48.6% of the LP tokens (thus losing their 2.5x boost).

However, what we find is that funds are distributed between StakeDAO and Convex from the start, even when Convex holds less than this number of tokens. This is a misallocation of funds, because Convex would be the better investment at this point.

```solidity
function testZach__MaxBoostIgnored() public view {
    console.log(_calculateOptimalHardcoded(100e15));
    console.log(_calculateOptimalHardcoded(200e15));
    console.log(_calculateOptimalHardcoded(300e15));
    console.log(_calculateOptimalHardcoded(400e15));
    console.log(_calculateOptimalHardcoded(486e15));
    console.log(_calculateOptimalHardcoded(500e15));
}

function _calculateOptimalHardcoded(uint balanceConvex) internal pure returns (uint) {
    uint totalSupply = 1e18;
    return (
        3 * (1e18 - 16e16) * balanceConvex * 45638438391688844908436605
            / (
                (2 * (16e16 + 8e16 - 17e16) * balanceConvex * 604626671209527861113435591) / totalSupply
                    + 3 * 294301283928832182636330151 * (1e18 + 8e16 - 17e16)
            )
    );
}
```
```
Logs:
  14165270812244372
  28038221067611466
  41627807030582967
  54942622789098980
  66179902412333701
  67990918378607736
```

### Recommendation

The formula should be rethought to take into account the `min` operation.

I believe it can be simplified in a way such that, if Convex is getting 2.5x boost, the optimal amount for StakeDAO to have is 0, and after that, the existing formula holds.

However, I haven't reworked all the math, so we'll need more time thinking through this to be sure.

### Review

Fixed in [PR #42](https://github.com/stake-dao/strategy-optimizor/pull/42). Before relying on the formula, the Optimizor checks if Convex's `working_balances` of LP tokens is equal to their `balanceOf`. If these numbers match, it means Convex has full boost, and they are allocated all funds.

## [H-02] When CVX totalSupply gets close to max supply, Optimizor will brick all Curve Convex calculations

To calculate the target StakeDAO balance, the Optimizor uses the following formula:
```solidity
return (
    3 * (1e18 - FEES_STAKEDAO) * balanceConvex * veCRVStakeDAO
        / (
            (2 * (FEES_STAKEDAO + boost - FEES_CONVEX) * balanceConvex * veCRVTotal) / totalSupply
                + 3 * veCRVConvex * (1e18 + boost - FEES_CONVEX)
        )
);
```
As you can see, `FEES_STAKEDAO + boost - FEES_CONVEX` is performed without accounting for the situation in which this sum underflows (which will happen when `boost < FEES_CONVEX - FEES_STAKEDAO`).

Because the right side of that equation is hard coded (`17e16 - 16e16 = 1e16`), we know that when `boost < 1e16`, the formula will begin to underflow each time it is used.

While we can't predict the exact CVX `totalSupply()` at which this will occur (because it depends on the CVX/CRV exchange rate), if we assume the current exchange rate we can calculate that this level will be reached when CVX total supply equals 998.06mm.

Again, we are not able to predict exactly when this moment will arrive ([because it depends on CRV earned](https://docs.convexfinance.com/convexfinanceintegration/cvx-minting)), but we are already on cliff 999/1000 with 985.95mm tokens minted, so it is likely quickly approaching.

Note: This issue will not exist for Frax Convex calculations, because of the hard coded extra boost of `0.25`.

### Proof of Concept

Here is a drop in test that uses the current values for all the variables in the calculation, but plugs our increased CVX total supply in to the boost calculation. The result is an underflow.

```solidity
function testZach__BoostUnderflow() public {
    uint FEES_STAKEDAO = 16e16;
    uint FEES_CONVEX = 17e16;

    uint256 veCRVTotal = 603e24; // 603mm veCRV total
    uint256 veCRVConvex = 294e24; // 294mm veCRV owned by Convex
    uint veCRVStakeDAO = 45e24; // 45mm veCRV owned by SD

    // Liquidity Gauge
    uint256 totalSupply = 1e26;
    uint256 balanceConvex = 5e25;

    uint boost;
    {
        // CVX
        uint256 cvxTotal = 99806016828721292694549765;
        uint256 vlCVXTotal = 57031094518791102285673623;
        boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);
    }

    vm.expectRevert();
    uint optimized = (
        3 * (1e18 - FEES_STAKEDAO) * balanceConvex * veCRVStakeDAO
            / (
                (2 * (FEES_STAKEDAO + boost - FEES_CONVEX) * balanceConvex * veCRVTotal) / totalSupply
                    + 3 * veCRVConvex * (1e18 + boost - FEES_CONVEX)
            )
    );
}
```

### Recommendation

```diff
+     uint feeDiff = boost + FEES_STAKEDAO > FEES_CONVEX ? FEES_STAKEDAO + boost - FEES_CONVEX : 0;
        return (
            3 * (1e18 - FEES_STAKEDAO) * balanceConvex * veCRVStakeDAO
                / (
-                   (2 * (FEES_STAKEDAO + boost - FEES_CONVEX) * balanceConvex * veCRVTotal) / totalSupply
-                   (2 * (feeDiff) * balanceConvex * veCRVTotal) / totalSupply
                        + 3 * veCRVConvex * (1e18 + boost - FEES_CONVEX)
                )
        );
```

### Review

Fixed as recommended in [PR #33](https://github.com/stake-dao/strategy-optimizor/pull/33).

## [H-03] Cached values can be manipulated by Convex

In order to increase gas efficiency, the Optimizor caches values for the optimal Stake DAO balance for a given gauge. As long as three criteria are met, it will use this cached value:
1) The `useLastOpti` storage value is set to `true`
2) Less than `cachePeriod` has passed since it was cached (currently 7 days)
3) The StakeDAO locker's veCRV balance hasn't moved by `veCRVDifferenceThreshold` (currently 5%)

While these checks are likely sufficient for normal use, they do not adequately protect against intentional manipulation.

If we look at the formula for calculating the optimal Stake DAO amount, we can see a few important variables that can be manipulated:
```solidity
return (
    3 * (1e18 - FEES_STAKEDAO) * balanceConvex * veCRVStakeDAO
        / (
            (2 * (FEES_STAKEDAO + boost - FEES_CONVEX) * balanceConvex * veCRVTotal) / totalSupply
                + 3 * veCRVConvex * (1e18 + boost - FEES_CONVEX)
        )
);
```
If an adversary wanted to cache a lower optimal value for Stake DAO, there are a few important values that could be manipulated:
- `veCRVConvex` is the amount of veCRV held by Convex. Since it is a part of the denominator, increasing this value will lower the result.
- `balanceConvex` is the amount of LP tokens staked with Convex. Since it is multiplied by higher values in the numerator, decreasing this value will lower the result.

Fortunately, `veCRVConvex` cannot be manipulated because tokens are locked.

However, in the event that Convex (or someone who supports them) owns a large share of the LP submitted to a given gauge, they could perform the following manipulation:
- Wait until the `cachePeriod` has just ended (currently 7 days from the last cache on a given gauge)
- Withdraw all of their LP tokens from the given Convex gauge
- Perform a small deposit via StakeDAO's CurveStrategy contract
- This will trigger a new cached value to be saved, with a lower than optimal StakeDAO target balance
- Redeposit all of their LP tokens back into the Convex gauge

The result is that the Optimizor will use a deflated optimal StakeDAO value for the next week. This could be repeated weekly to manipulate the Optimizor into favoring Convex more than it should.

### Recommendation

When we check whether to use cached value in `_getOptimalAmount()`, add a fourth check which checks the Convex Balance:
```diff
if (
    // 1. Optimize calculation is activated
    useLastOpti
    // 2. The cached optimal amount is not too old
    && (
        (isMeta ? lastOptiMetapool[liquidityGauge].timestamp : lastOpti[liquidityGauge].timestamp) + cachePeriod
            > block.timestamp
    )
    // 3. The cached veCRV balance of Stake DAO is below the acceptability threshold
    && absDiff(cacheVeCRVLockerBalance, veCRVBalance) < veCRVBalance.mulWadDown(veCRVDifferenceThreshold)
+   // 4. The cached Convex balance is within the acceptability threshold
+   uint256 balanceConvex = ERC20(liquidityGauge).balanceOf(LOCKER_CONVEX);
+   && absDiff(cacheConvexBalance, balanceConvex) < convexBalance.mulWadDown(convexDifferenceThreshold)
) {
```

### Review

Fixed as recommended in [PR #43](https://github.com/stake-dao/strategy-optimizor/pull/43). A setter for the new `convexDifferenceThreshold` variable was added in [PR #45](https://github.com/stake-dao/strategy-optimizor/pull/45).

## [H-04] Withdrawals should always come from Convex Curve before Convex Frax, not vice versa

As the whitepaper states: "This leads to Convex Frax pools being strictly superior to Convex Curve pools."

The deposit logic gives a boost to Convex Frax pools, and always prefers them to Convex Curve pools if they are available.

However, the withdrawal logic prioritizes withdrawing from Convex Frax, with the following flow chart:

```
1) IF there are tokens in Convex Frax, THEN withdraw from Convex Frax first
    - IF the withdrawal needs more tokens AND Stake DAO has tokens, THEN withdraw from Stake DAO
    - IF the withdrawal needs more tokens AND Convex Curve has tokens, THEN withdraw from Convex Curve

2) ELSE IF there are tokens in Convex Curve, THEN withdraw from Convex Curve first
    - IF the withdrawal needs more tokens AND Stake DAO has tokens, THEN withdraw from Stake DAO

3) ELSE withdraw the full amount from Stake DAO
```

However, it is possible to end up in a situation where both Convex Frax and Convex Curve have tokens. For example, if there was no Frax pool and tokens were deposited to Convex Curve, and then a Frax pool was added and started taking in new deposits.

At this point, since the Convex Curve pool is strictly inferior to the Convex Frax pool, it should always have its tokens withdrawn first. However, the opposite happens — nothing can be removed from the Convex Curve pool until ALL the tokens have been removed from the Convex Frax pool. This creates an inefficiency in the allocation.

### Recommendation

The logic should instead check withdrawals in order of preference:
1) Convex Curve => Convex Frax => Stake DAO
2) Convex Frax => Stake DAO
3) Stake DAO

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.

## [M-01] If any fees are set to zero, `claim()` will be bricked

In `CurveStrategy.sol`, after CRV fees are claimed, the `_sendFee()` function is called to distribute the various fees.

```solidity
function _sendFee(address gauge, address rewardToken, uint256 rewardsBalance) internal returns (uint256) {
    Fees memory fee = feesInfos[gauge];

    // calculate the amount for each fee recipient
    uint256 multisigFee = rewardsBalance.mulDivDown(fee.perfFee, BASE_FEE);
    uint256 accumulatorPart = rewardsBalance.mulDivDown(fee.accumulatorFee, BASE_FEE);
    uint256 veSDTPart = rewardsBalance.mulDivDown(fee.veSDTFee, BASE_FEE);
    uint256 claimerPart = rewardsBalance.mulDivDown(fee.claimerRewardFee, BASE_FEE);

    // send
    ERC20(rewardToken).safeApprove(address(accumulator), accumulatorPart);
    accumulator.depositToken(rewardToken, accumulatorPart);
    ERC20(rewardToken).safeTransfer(rewardsReceiver, multisigFee);
    ERC20(rewardToken).safeTransfer(veSDTFeeProxy, veSDTPart);
    ERC20(rewardToken).safeTransfer(msg.sender, claimerPart);
    return rewardsBalance - multisigFee - accumulatorPart - veSDTPart - claimerPart;
}
```
The problem is that, if any of these fee percentages are reduced to 0, the resulting amount will equal 0.

If we look at the `accumulator.depositToken()` function, we can see it reverts if the amount passed is 0:
```solidity
function depositToken(address _token, uint256 _amount) external {
	require(_amount > 0, "set an amount > 0");
	IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
	emit TokenDeposited(_token, _amount);
}
```
Similarly, if we use `safeTransfer()` we are calling the `transfer()` function of an ERC20, which often reverts if an amount of 0 is passed.

If we check the function where these fees are set, we can see there are no restrictions against setting the various fees to 0:
```solidity
function manageFee(MANAGEFEE manageFee_, address gauge, uint256 newFee) external requiresAuth {
    if (gauge == address(0)) revert ADDRESS_NULL();

    if (manageFee_ == MANAGEFEE.PERFFEE) {
        // 0
        feesInfos[gauge].perfFee = newFee;
    } else if (manageFee_ == MANAGEFEE.VESDTFEE) {
        // 1
        feesInfos[gauge].veSDTFee = newFee;
    } else if (manageFee_ == MANAGEFEE.ACCUMULATORFEE) {
        //2
        feesInfos[gauge].accumulatorFee = newFee;
    } else if (manageFee_ == MANAGEFEE.CLAIMERREWARD) {
        // 3
        feesInfos[gauge].claimerRewardFee = newFee;
    }
    if (
        feesInfos[gauge].perfFee + feesInfos[gauge].veSDTFee + feesInfos[gauge].accumulatorFee
            + feesInfos[gauge].claimerRewardFee > BASE_FEE
    ) revert FEE_TOO_HIGH();

    emit FeeManaged(uint256(manageFee_), gauge, newFee);
}
```

Note that, while less likely, the fee amounts could also equal zero in a situation where a very small `rewardsBalance` was claimed, which multiplied by the fee percentage, rounded down to zero. However, this is less of a problem because we could simply wait for a higher reward balance and the claim would work.

### Recommendation

- If you DON'T want to allow 0 fees, add a check in the `manageFee()` function to ensure they aren't set this way.
- If you DO want to allow 0 fees, add a check in `_sendFee()` to confirm each "part" is greater than zero, and to skip the deposit / transfer if not.

### Review

Fixed in [PR #29](https://github.com/stake-dao/strategy-optimizor/pull/29). Fees of zero are allowed, and a check was added to `_sendFee()` to confirm that each part is greater than 0 before performing the deposit or transfer.

## [M-02] `migrateLP()` transfers LP tokens to governance, rather than the vault

The `CurveStrategy.sol` contract has a `migrateLP()` function, which is intended to allow governance to withdraw LP tokens from a gauge and transfer them to the vault.

We can see in the comments that only governance can call the function:
```solidity
/// @notice Migrate LP token from the locker to the vault
/// @dev Only callable by the governance
/// @param token Address of LP token to migrate
function migrateLP(address token) external requiresAuth {
    ...
}
```
When the final tokens are transferred, the comments specify that they should be going to the vault:
```solidity
// Locker transfer the LP token to the vault
(success,) = LOCKER.execute(token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount));
if (!success) revert CALL_FAILED();
```
However, because `msg.sender` will be governance, this is where the tokens will be transferred.

### Recommendation

Governance should input the vault's address and the tokens should be transferred to that address instead of `msg.sender`.

### Review

Fixed in [PR #30](https://github.com/stake-dao/strategy-optimizor/pull/30). The function now only accepts calls from vaults, not governance, so the `msg.sender` will be the vault address and it will work as intended.

## [M-03] `claim3Crv()` function will always revert whenever notify argument is passed as `true`

When `curveStrategy.claim3Crv()` is called, we claim the locker's 3CRV rewards from Curve and transfer the rewards from the locker to the accumulator.

Then, if the `notify` flag is passed as `true`, we tell the `accumulator` to notify:
```solidity
if (notify) {
    accumulator.notifyAll();
}
```
However, if we look at the `notifyAll()` function on the live accumulator (0x..), we can see that, among other actions, it also calls `CurveStrategy(strategy).claim3Crv()`:
```solidity
function notifyAll() external {
    CurveStrategy(strategy).claim3Crv(false);
    uint256 crv3Amount = IERC20(CRV3).balanceOf(address(this));
    uint256 crvAmount = IERC20(CRV).balanceOf(address(this));
    _notifyReward(tokenReward, crv3Amount);
    _notifyReward(CRV, crvAmount);
    _distributeSDT();
}
```
This goes back for an additional call of `claim3Crv()`. However, this time, there will be no rewards claimed. The function has a check that, if nothing was claimed, it reverts:
```solidity
uint256 amountToSend = ERC20(CRV3).balanceOf(address(LOCKER));
if (amountToSend == 0) revert AMOUNT_NULL();
```
The result is that the function will revert any time the `true` flag is passed.

### Proof of Concept

Below is an edited version of an existing test from your test suite. Your test does, in fact, pass the `true` bool to the function, but it uses a mock accumulator that doesn't perform the `notifyAll()` actions, which makes the test pass. By subbing in the correct accumulator, we can see that it causes a revert:
```solidity
function testZach_Claim3CRVReverts() public useFork(forkId1) {
    curveStrategy.setAccumulator(0xa44bFD194Fd7185ebecEcE4F7fA87a47DaA01c6A);
    vm.expectRevert("nothing claimed");
    curveStrategy.claim3Crv(true);
}
```

### Recommendation

Rather than revert if `amountToSend == 0`, simply return early.
```diff
function claim3Crv(bool notify) external requiresAuth {
    // Claim 3crv from the curve fee Distributor, it will send 3crv to the crv locker
    (bool success,) = LOCKER.execute(CRV_FEE_D, 0, abi.encodeWithSignature("claim()"));
    if (!success) revert CLAIM_FAILED();

    // Cache amount to send to accumulator
    uint256 amountToSend = ERC20(CRV3).balanceOf(address(LOCKER));
-   if (amountToSend == 0) revert AMOUNT_NULL();
+   if (amountToSend == ) return;

    // Send 3crv from the LOCKER to the accumulator
    (success,) = LOCKER.execute(
        CRV3, 0, abi.encodeWithSignature("transfer(address,uint256)", address(accumulator), amountToSend)
    );
    if (!success) revert CALL_FAILED();

    if (notify) {
        accumulator.notifyAll();
    }
    emit Crv3Claimed(amountToSend, notify);
}
```

### Review

Fixed as recommended in [PR #39](https://github.com/stake-dao/strategy-optimizor/pull/39).

## [M-04] If any Convex pool ever allows staking for other users, `killConvexFrax()` can be bricked

If the StakeDAO team decides to kill the Convex Frax option, the process is as follows:
- call `pauseConvexFraxDeposit()`
- wait `lockingIntervalSec()`, which is currently set to 7 days
- call `killConvexFrax()`
- this will iterate through all pids and check if they have a balance with `fallbackConvexFrax.balanceOf(i)`
- for any pid with a balance, it will call `getLP()` to get the token, and then `fallbackConvexFrax.withdraw(token, balance)` to withdraw, and then finally `curveStrategy.depositForOptimizor(token, balance)` to deposit into the next optimal option

This issue stems from the ability to have `balanceOf()` return a positive value for a non-Curve token, which initiates the withdrawal process for a token that is not registered in the FallbackConvexFrax contract.

If we follow the logic when `balanceOf()` is called, we see the following:
```solidity
function balanceOf(uint256 pid) public view returns (uint256) {
    IFraxUnifiedFarm.LockedStake memory infos = _getInfos(pid);

    // If the lock is not expired, then return 0, as only the liquid balance is needed
    return block.timestamp >= infos.ending_timestamp ? infos.liquidity : 0;
}
```
```solidity
function _getInfos(uint256 pid) internal view returns (IFraxUnifiedFarm.LockedStake memory infos) {
    (, address staking,,,) = POOL_REGISTRY_CONVEX_FRAX.poolInfo(pid);
    // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
    // and the last one is emptyed. So we need to get the last one.
    uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(vaults[pid]);

    // If no lockedStakes, return 0
    if (lockCount == 0) return infos;

    // Cache lockedStakes infos
    infos = IFraxUnifiedFarm(staking).lockedStakesOf(vaults[pid])[lockCount - 1];
}
```

As we can see, we get `vaults[pid]` for the given `pid`. We then get the latest locked stake for that user and, if it is unlocked, return the liquidity of that stake.

Since the `pid` is not registered for assets that are non-Curve tokens, `vaults[pid]` will return `address(0)`.

The consequence is that, if `address(0)` has any assets staked and ready to withdraw, the `balanceOf()` function for the `pid` will return the liquidity of address(0), which will be greater than 0.

If that's the case, we try to withdraw the tokens. First, we get the `token` for the `pid` by calling `getLP()`:
```solidity
function getLP(uint256 pid) public returns (address, address) {
    // Get the staking token address
    (,, address stkToken,,) = POOL_REGISTRY_CONVEX_FRAX.poolInfo(pid);

    // Get the underlying curve lp token address
    (bool success, bytes memory data) = stkToken.call(abi.encodeWithSignature("curveToken()"));

    // Return the curve lp token address if call succeed otherwise return address(0)
    return success ? (abi.decode(data, (address)), stkToken) : (address(0), stkToken);
}
```
As we can see, in the event that the token is non-Curve, we simply return `address(0)` as the token.

We then call `withdraw(token, balance)`, and `address(0)` will be used as the first argument. This will revert when the `pid` for this token is used to find a vault (also `address(0)`) and call `withdrawLockedAndUnwrap()` on a non-contract address:
```solidity
uint256 pid = pids[stkTokens[token]].pid;
IStakingProxyConvex(vaults[pid]).withdrawLockedAndUnwrap(kekIds[vaults[pid]]);
```

The result is that the `killConvexFrax()` function will revert, and there will be no way to get around it.

### Proof of Concept

Here is a test that can be dropped into `CurveStrategy.t.sol` to show this behavior. Since Convex pools currently only allow staking for your own address (except during migration), I showed the behavior by pranking `address(0)`.

```solidity
function testZach__BalanceOfInvalidPid() public useFork(forkId2) {
    // setup
    uint targetPid = 1;
    address stakingAddress = 0x10460d02226d6ef7B2419aE150E6377BdbB7Ef16;
    address stakingToken = 0x6021444f1706f15465bEe85463BCc7d7cC17Fc03;
    uint amount = 100;
    deal(stakingToken, address(0), amount);

    // stake tokens on behalf of address(0)
    vm.startPrank(address(0));
    ERC20(stakingToken).approve(stakingAddress, amount);
    stakingAddress.call(abi.encodeWithSignature("stakeLocked(uint256,uint256)", amount, 1 days));
    vm.stopPrank();

    // liquidity isn't counted in balance until it's unlocked (wait 1 day)
    StakingAddress.LockedStake memory stake = StakingAddress(stakingAddress).lockedStakesOf(address(0))[0];
    vm.warp(stake.ending_timestamp + 1);

    // if we check, we're now returning a positive balance for balanceOf
    uint balance = fallbackConvexFrax.balanceOf(targetPid);
    console.log("Balance: ", balance);

    // give optimizor permissions to withdraw
    rolesAuthority.setUserRole(address(optimizor), 2, true);

    // to kill, we first need to pause and wait...
    optimizor.pauseConvexFraxDeposit();
    vm.warp(block.timestamp + fallbackConvexFrax.lockingIntervalSec());

    // attempts to kill will fail because getLP() returns address(0), and fallbackConvexFrax.withdraw(address(0), amount) reverts
    vm.expectRevert();
    optimizor.killConvexFrax();
}
```
Note that you'll need to add the following interface to the top of the file:
```solidity
interface StakingAddress {
    struct LockedStake {
        bytes32 kek_id;
        uint256 start_timestamp;
        uint256 liquidity;
        uint256 ending_timestamp;
        uint256 lock_multiplier; // 6 decimals of precision. 1x = 1000000
    }

    function stakeLocked(uint256 liquidity, uint256 secs) external returns (bytes32);
    function lockedStakesOfLength(address account) external view returns (uint256);
    function lockedStakesOf(address account) external view returns (LockedStake[] memory);
}
```

### Recommendation

`_getInfos()` should not be able to be tricked to operating on `address(0)` for uninitialized pids.

The following check should be added to ensure this is the case:
```diff
function _getInfos(uint256 pid) internal view returns (IFraxUnifiedFarm.LockedStake memory infos) {
    (, address staking,,,) = POOL_REGISTRY_CONVEX_FRAX.poolInfo(pid);
    // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
    // and the last one is emptyed. So we need to get the last one.
    uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(vaults[pid]);
+   bool initializedPid = vaults[pid] != address(0);

    // If no lockedStakes, return 0
-   if (lockCount == 0) return infos;
+   if (lockCount == 0 || !initializedPid) return infos;

    // Cache lockedStakes infos
    infos = IFraxUnifiedFarm(staking).lockedStakesOf(vaults[pid])[lockCount - 1];
}
```

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.

## [M-05] Turning off Optimizor can lead to funds being stuck in Convex

When new deposits or withdrawals are sent to `CurveStrategy.sol`, the Optimizor determines the proportions that are sent to StakeDAO vs the fallback Convex options.

In the event where there is no Optimizor set (ie `address(optimizor) == address(0)`), the strategy defaults to using StakeDAO for all deposits and withdrawals.

```solidity
if (address(optimizor) != address(0)) {
    (recipients, optimizedAmounts) = optimizor.optimizeWithdraw(token, gauge, amount);
} else {
    // Shortcut if no Optimizor contract, withdraw all from Stake DAO
    _withdrawFromLiquidLocker(token, gauge, amount);

    // No need to go futher on the function
    return;
}
```
However, in the event that the Optimizor is turned off, it is likely that there are some funds in Convex. At that point, removing the Optimizor will lead to all withdrawals coming from StakeDAO, and leave the funds locked in Convex permanently.

This can be resolved, of course, by deploying an intermediate Optimizor that specifies the logic to take withdrawals from Convex and put deposits in StakeDAO, but this seems like a lot of additional logic to figure out at what would likely be a high stress time, so it would be preferable for the correct unwind logic to be built into the protocol.

### Recommendation

Rather than simply checking whether `address(optimizor) == address(0)`, a specific enum should set the `optimizorStatus` to `ACTIVE`, `UNWINDING` or `OFF`.

When in the `UNWINDING` position, all withdrawals should come through Convex if possible. Once Convex is out of funds, the rest should come from StakeDAO (and at that point, the flag could be safely set to `OFF`).

This multi step approach makes sure that the unwind happens automatically as expected.

### Review

Fixed in [PR #46](https://github.com/stake-dao/strategy-optimizor/pull/46) by removing the ability for the Optimizor to be turned off. The team is aware that, in the case of removing a fallback, they will need an intermediate Optimizor that unwinds this position before implementing the new Optimizor without it.

## [M-06] If `claimOnWithdraw` flag is set to true, FallbackConvexCurve will not distribute rewards

When `FallbackConvexCurve.withdraw()` is called, it calls the reward token to burn its tokens and send back the underlying Curve LP token:
```solidity
function withdraw(address token, uint256 amount) external override requiresAuth {
    // Get cvxLpToken address
    (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pids[token].pid);
    // Withdraw from ConvexCurve gauge and claim rewards if toggle is on
    IBaseRewardsPool(crvRewards).withdrawAndUnwrap(amount, claimOnWithdraw);

    // Transfer the amount
    ERC20(token).safeTransfer(curveStrategy, amount);

    emit Withdrawn(token, amount);
}
```
The `claimOnWithdraw` argument that is passed to the function call is pulled from storage, and can be set by the admins to either true or false.

If this variable is set to true, `withdrawAndUnwrap()` will send all extra rewards to `msg.sender`:
```solidity
    function withdrawAndUnwrap(uint256 amount, bool claim) public updateReward(msg.sender) returns(bool){

        //also withdraw from linked rewards
        for(uint i=0; i < extraRewards.length; i++){
            IRewards(extraRewards[i]).withdraw(msg.sender, amount);
        }

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        //tell operator to withdraw from here directly to user
        IDeposit(operator).withdrawTo(pid,amount,msg.sender);
        emit Withdrawn(msg.sender, amount);

        //get rewards too
        if(claim){
            getReward(msg.sender,true);
        }
        return true;
    }
```
```solidity
    function getReward(address _account, bool _claimExtras) public updateReward(_account) returns(bool){
        uint256 reward = earned(_account);
        if (reward > 0) {
            rewards[_account] = 0;
            rewardToken.safeTransfer(_account, reward);
            IDeposit(operator).rewardClaimed(pid, _account, reward);
            emit RewardPaid(_account, reward);
        }

        //also get rewards from linked rewards
        if(_claimExtras){
            for(uint i=0; i < extraRewards.length; i++){
                IRewards(extraRewards[i]).getReward(_account);
            }
        }
        return true;
    }
```
This will send all the extra reward tokens back to the Fallback, but they will be not distributed to `CurveStrategy.sol` and will remain in the Fallback contract.

Fortunately, BaseFallback.sol has a `rescueERC20()` function, so these extra rewards tokens could be manually saved, but this will be manual and inconvenient and should be handled by the protocol.

### Recommendation

Use the already existing `_handleRewards()` logic to distribute the rewards:
```diff
function withdraw(address token, uint256 amount) external override requiresAuth {
    // Get cvxLpToken address
    (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pids[token].pid);
    // Withdraw from ConvexCurve gauge and claim rewards if toggle is on
    IBaseRewardsPool(crvRewards).withdrawAndUnwrap(amount, claimOnWithdraw);

    // Transfer the amount
    ERC20(token).safeTransfer(curveStrategy, amount);

+   if (claimOnWithdraw) {
+       address[] memory rewardsTokens = getRewardsTokens(token);
+       _handleRewards(token, rewardsTokens, msg.sender);
+   }

    emit Withdrawn(token, amount);
}
```

### Review

Fixed as recommended in [PR #36](https://github.com/stake-dao/strategy-optimizor/pull/36). Note that the recommendation to use `msg.sender` as the claimer was incorrect, as the sender will always be the CurveStrategy. Instead, the claim uses `address(0)`, and the `_sendFee()` function has been adjusted to skip sending any funds to the `claimer` if `address(0)` in used.

## [M-07] No `rebalance()` function is implemented

On page 9 of the whitepaper, it says:

> A rebalance function is implemented to force optimisation in case of big movements in TVL leading to over exposure to one of the other locker.

This rebalance concept is very important for a number of reasons:
- Handling big movements in TVL (as mentioned above)
- Ensuring that the simplified withdrawal mechanism (always withdraw from Convex first) doesn't lead to overindexing into StakeDAO, which could result in a worse APR for users than investing in Convex directly
- It is likely to be needed for the solution to C-03 to work correctly.

However, it appears this function has not yet been implemented.

### Recommendation

Implement a `rebalance()` function that adjusts allocation to the optimal amount.

### Review

Acknowledged. This is planned for the future but is not implemented yet.

## [M-08] If Optimizor is deployed on a chain where Frax PID 0 is a Curve token, withdrawals can malfunction

When optimizing withdrawals, we calculate our Frax balance of a given LP token as follows:
```solidity
function balanceOf(address token) public view override returns (uint256) {
    // Cache the pid
    uint256 pid = pids[stkTokens[token]].pid;

    return balanceOf(pid);
}

function balanceOf(uint256 pid) public view returns (uint256) {
    IFraxUnifiedFarm.LockedStake memory infos = _getInfos(pid);

    // If the lock is not expired, then return 0, as only the liquid balance is needed
    return block.timestamp >= infos.ending_timestamp ? infos.liquidity : 0;
}

function _getInfos(uint256 pid) internal view returns (IFraxUnifiedFarm.LockedStake memory infos) {
    (, address staking,,,) = POOL_REGISTRY_CONVEX_FRAX.poolInfo(pid);
    // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
    // and the last one is emptyed. So we need to get the last one.
    uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(vaults[pid]);

    // If no lockedStakes, return 0
    if (lockCount == 0) return infos;

    // Cache lockedStakes infos
    infos = IFraxUnifiedFarm(staking).lockedStakesOf(vaults[pid])[lockCount - 1];
}
```
In short, we perform the following:
- get the `pid` for the `staking token` associated with our LP token
- get `poolInfo` for that `pid` in order to get the `staking address`
- look up our vault associated with that `pid` using `vaults[pid]`
- get the unlock time and liquidity of the latest stake in that vault
- if the unlock time is in the past, return the liquidity; otherwise return 0

If we enter a token that is not supported by Convex Frax, the `pid` will not be registered and will return `0`. This will check the staking contract's balance for `vaults[0]`, and return that value if it is unlocked.

This works because, on Ethereum mainnet, the pool with `pid = 0` is not a Curve token. This means it will never have any balance from our Fallback, and therefore will return zero.

However, when deploying on other chains, it may be the case that `pid = 0` is a Curve token that is supported by the Fallback.

In that case, any time the balance was checked for an unsupported token, it would:
- not find the token, so return `pid = 0`
- get `poolInfo` for the pool with `pid = 0`, which returns a real staking address
- find a real vault that interacts with that staking address at `vaults[0]`
- find real liquidity and unlock time there, and return the response based on those values

The result is that unsupported tokens would return a positive balance from Convex Frax.

Imagining a situation where the token's balance was held on Convex Curve, this would lead to unexpected behavior. A user would call `optimizeWithdraw()`, the `balanceOfConvexFrax` would return a positive value, and we would end up in Situation n°1. Therefore, the chain of withdrawals would go `Convex Frax => Stake DAO => Convex Curve`.

Where we should have ended up (in Situation n°2), withdrawals would have properly been allocated to `Convex Curve` first.

### Recommendation

At a minimum, `balanceOf()` should only work for `pid` values that have been initialized.

```diff
function balanceOf(address token) public view override returns (uint256) {
    // Cache the pid
    PidsInfo memory pid = pids[stkTokens[token]];
+   if (!pid.isInitialized) return 0;
    return balanceOf(pid);
}
```
However, depending how the code is edited in the future, I could imagine many places where this same "uninitialized pid = 0" risk would exist (including in the FallbackConvexCurve.sol code), and could lead to much worse outcomes.

My recommendation is to make this a more global solution. The `getPid()` function should be made public so it can be accessed internally, and should include an extra check to make sure it's safe. Then, anywhere we look up a pid in that mapping, we should use the function instead.
```solidity
// for FallbackConvexFrax
function getPid(address token) public view override returns (PidsInfo memory pid) {
    PidsInfo pid = pids[stkTokens[token]];
    if (!pid.isInitialized) revert NOT_VALID_PID();
}

// for FallbackConvexCurve
function getPid(address token) public view override returns (PidsInfo memory pid) {
    PidsInfo pid = pids[token];
    if (!pid.isInitialized) revert NOT_VALID_PID();
}
```

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.

However, the underlying issue of uninitialized PIDs being returned was addressed. [PR #34](https://github.com/stake-dao/strategy-optimizor/pull/34) implemented a hybrid approach, where `deposit()` and `withdraw()` calls revert if a PID is not initialized, while other cases return 0.

A small gas optimization was added to this solution in [PR #44](https://github.com/stake-dao/strategy-optimizor/pull/44).

## [L-01] CVX price estimate should include adjustment parameter

In order to estimate the price of CVX in CRV, we calculate:

`amount of veCRV owned by Convex / total CVX locked for vlCVX`

Based on the whitepaper, it appears that this ratio has remained within +/-20% of the actual exchange rate over the past year, making it a solid estimate for the price.

However, there is no guarantee that this ratio will remain. As an example, looking at the quantity of CVX that is locked in the vlCVX contract, we can see that it is only 57mm of the 98mm total supply. This leaves quite a bit of room for some changed incentives or market conditions to impact the locked amount, which would be likely to change the ratio.

### Recommendation

To ensure that a new Optimizor doesn't need to be deployed to address this, I would recommend including an adjustment parameter that the Stake DAO team can use to tune this calculation.

Since the Optimizor is set by the Stake DAO team, this doesn't add any additional rug vectors, but would do a lot to ensure that you can keep the Optimizor acting in an optimal fashion, even if market conditions change.

### Review

Fixed in [PR #37](https://github.com/stake-dao/strategy-optimizor/pull/37) by making the existing `1e18` constant included in the calculation a variable that can be adjusted.

## [L-02] FXS should be hardcoded into `getRewardTokens()`

In `FallbackConvexFrax.sol`, when `claimRewards()` is called, we start by getting a list of reward tokens. This list is hardcoded to include CRV and CVX, and then additionally includes the reward tokens returned by the staking address.

```solidity
function getRewardsTokens(address token) public view override returns (address[] memory) {
    // Cache the pid
    PidsInfo memory pidInfo = pids[stkTokens[token]];

    // Only claim if the pid is initialized
    if (!pidInfo.isInitialized) return (new address[](0));

    // Get all the reward tokens
    address[] memory tokens_ =
        IFraxFarmERC20(IStakingProxyConvex(vaults[pidInfo.pid]).stakingAddress()).getAllRewardTokens();

    // Create new rewards tokens empty array
    address[] memory tokens = new address[](tokens_.length + 2);

    // Add CRV and CVX to the rewards tokens
    tokens[0] = address(CRV);
    tokens[1] = address(CVX);

    for (uint256 i = 2; i < tokens.length;) {
        tokens[i] = tokens_[i - 2];

        // No need to check for overflow, since i can't be bigger than 2**256 - 1
        unchecked {
            ++i;
        }
    }

    return tokens;
}
```

If we examine the `getReward()` function that is called on the vault later, we can see why CRV and CVX were hardcoded, as they are manually sent if they include any balance before the list of reward tokens are processed.
```solidity
function getReward(bool _claim) public override{

    //claim
    if(_claim){
        //claim frax farm
        IFraxFarmERC20(stakingAddress).getReward(address(this));
        //claim convex farm and forward to owner
        IConvexWrapper(stakingToken).getReward(address(this),owner);

        //double check there have been no crv/cvx claims directly to this address
        uint256 b = IERC20(crv).balanceOf(address(this));
        if(b > 0){
            IERC20(crv).safeTransfer(owner, b);
        }
        b = IERC20(cvx).balanceOf(address(this));
        if(b > 0){
            IERC20(cvx).safeTransfer(owner, b);
        }
    }

    //process fxs fees
    _processFxs();

    //get list of reward tokens
    address[] memory rewardTokens = IFraxFarmERC20(stakingAddress).getAllRewardTokens();

    //transfer
    _transferTokens(rewardTokens);

    //extra rewards
    _processExtraRewards();
}
```
However, we can also see that there is an internal call to `_processFxs()` that occurs. If we examine this logic, we can see that it is similar to the CRV and CVX logic, sending FXS rewards even if it is not a part of the `rewardTokens` array.
```solidity
function _processFxs() internal{

    //get fee rate from fee registry
    uint256 totalFees = IFeeRegistry(feeRegistry).totalFees();

    //send fxs fees to fee deposit
    uint256 fxsBalance = IERC20(fxs).balanceOf(address(this));
    uint256 sendAmount = fxsBalance * totalFees / FEE_DENOMINATOR;
    if(sendAmount > 0){
        IERC20(fxs).transfer(IFeeRegistry(feeRegistry).getFeeDepositor(usingProxy), sendAmount);
    }

    //transfer remaining fxs to owner
    sendAmount = IERC20(fxs).balanceOf(address(this));
    if(sendAmount > 0){
        IERC20(fxs).transfer(owner, sendAmount);
    }
}
```
While, from the staking addresses I have researched, it appears that FXS is always included as one of the reward tokens, the fact that it is hardcoded to distribute regardless of whether it appears in that array should be reflected, by hardcoding it when we create the array on our end.

### Recommendation

```diff
        // Create new rewards tokens empty array
-       address[] memory tokens = new address[](tokens_.length + 2);
+       address[] memory tokens = new address[](tokens_.length + 3);

-       // Add CRV and CVX to the rewards tokens
+       // Add CRV, CVX and FXS to the rewards tokens
        tokens[0] = address(CRV);
        tokens[1] = address(CVX);
+       tokens[2] = address(FXS);

        for (uint256 i = 3; i < tokens.length;) {
+          if (tokens_[i-3] != CRV && tokens_[i-3] != CRV && tokens_[i-3] != FXS) {
+              tokens[i] = tokens_[i - 3];
-              tokens[i] = tokens_[i - 2];
+           }

            // No need to check for overflow, since i can't be bigger than 2**256 - 1
            unchecked {
                ++i;
            }
        }

        return tokens;
    }
```

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.

## [L-03] If `lockingIntervalSec` is lowered before `killConvexFrax()` is called, tokens can be locked

When the first deposit is made to a vault via `FallbackConvexFrax`, the tokens are locked for a time determined by the `lockingIntervalSec` variables (currently set to 7 days).

```solidity
kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);
```

When we check the balance of our Frax vaults with `fallbackConvexFrax.balanceOf(pid)`, the return value is `0` if the tokens are still locked, and their full value if they've been unlocked.

This is important because, if the admins call `killConvexFrax()`, it requires that `lockingIntervalSecs` has passed since the time Convex Frax was paused. If so, it rotates through the balances and, for each one that is positive, withdraws the token and moves them to a new strategy.

The risk comes from the very, very specific edge case where:
- a new vault is deposited into
- the admins reduce the `lockingIntervalSecs` time
- the admins call `pauseConvexFraxDeposits`
- `lockingIntervalSecs` later (but before the original deposit is unlocked), they call `killConvexFrax()`

The result is that the shutdown will go forward, but it will read the balances of the vault as `0` and skip it.

Afterwards, the tokens will become available to unlock, but will remain stuck because the `isConvexFraxKilled` flag will be set to `true`, forcing the `balanceOfConvexFrax` value in the Optimizor to always return 0.

### Recommendation

This is a rare enough edge case without a simple solution in code that I don't think there's a need to overengineer a check.

I would recommend adding clear comments to the `setLockingIntervalSec()` function that warms the caller that this value should never be lowered when within `lockingIntervalSec` of pausing or killing Convex Frax.

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.

## [L-04] `stakeLockedCurveLp()` does not appear to consistently return kekId

When deposits are made via `FallbackConvexFrax`, we check whether we have a saved value for the `kekIds` for the vault. If the value doesn't exist, we stake the LP tokens and save the returned `kekId`. If the value does exist, we use it to lock additional LP tokens to the existing stake.
```solidity
if (kekIds[vaults[pid]] == bytes32(0)) {
    // Stake locked curve lp on personal vault and update kekId mapping for the corresponding vault
    kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);
} else {
    // Else lock additional curve lp
    IStakingProxyConvex(vaults[pid]).lockAdditionalCurveLp(kekIds[vaults[pid]], amount);
}
```
If we look at the [ALUSD_FRAXBP contract](https://etherscan.io/address/0x2F9f08087297a2C14BABe5f3C74705DB45d939dA#code) used in the test suite, it returns `kekId` as expected.

However, if we look at [other versions of the same contract](https://etherscan.io/address/0x689339C08836471BE7FD5915e1f676471C4c7225#code), we can see that this identical function does not return a `kekId`.

This creates a risk for deposits, for any vault that does not return this value will revert and not allow funds to be deposited.

### Recommendation

Based on this discovery, the StakeDAO team has manually checked all 61 pids and confirmed that all pids where the underlying token is a CurveLP do return a `kekId`. This confirms that the protocol today should work as expected.

However, if we trace back where these contracts come from, they are cloned from the `pool.implementation` value, which is specified separately for each pool on `POOL_REGISTRY_CONVEX_FRAX`.

This creates the possibility that, because we don't understand the underlying mechanism for why these pools behave differently, a future CurveLP pool may not return the correct value, which will make it unusable via StakeDAO.

If possible, confirm the intention with the inconsistent return values with the developers of the system, or explore it more thoroughly in order to feel confident

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.

## [L-05] StakeDAO admin can divert deposits to its own locker

The goal of the Optimizor contract is to assure users that deposits will always be directed in the most efficient way possible across the various protocols.

However, the system relies on the `optimizor` address set by the StakeDAO team, which gives them the ability to either (a) set the `optimizor` to `address(0)` to disable it and send all funds to the StakeDAO locker or (b) set it to another address that will perform calculations in a dishonest way.

This creates a centralizing vector of control for the system, which is not guaranteed to act in accordance with the user's expectations.

### Recommendation

In order to maximize user assurance of the promise of the protocol, it would be valuable to ensure the `setOptimizor()` function is callable only by governance with an appropriate time lock.

### Review

Acknowledged. Contract ownership will be moved to veSDT governance when it is appropriate.

## [I-01] Formula in section 4.2 of whitepaper flips numerator and denominator

In section 4.2 of the whitepaper, a formula is given to linearly approximate the boost.

It is derived as follows:
1) `(Bsd * (1 - fsd)) < (Bcvx * (1 - Fcvx))`
2) `(wsd / bsd * (1 - fsd)) < (wcvx / bcvx * (1 - Fcvx))`
3) `((wsd / wcvx) * (1 - Fcvx / 1 - fsd) * bcvx) < bsd`

However, we can see that the `1 - Fcvx` and `1-fsd` were flipped in the final step.

The team has confirmed that the calculations in the whitepaper were done correctly, and the issue was simply a typo in the formula presentation within the whitepaper.

### Recommendation

Flip the numerator and denominator to present the correct formula:

`((wsd / wcvx) * (1 - fsd / 1 - Fcvx) * bcvx) < bsd`

### Review

Fixed in the new version of the whitepaper.

## [I-02] Incorrect rewardsTokens length check in `claimRewards()`

When `claimRewards()` is called in `FallbackConvexCurve.sol`, we use the `getRewardsToken()` function to generate a list of reward tokens. This function is implemented as follows:
```solidity
function getRewardsTokens(address token) public view override returns (address[] memory) {
    // Cache the pid
    PidsInfo memory pidInfo = pids[token];
    // Only claim if the pid is initialized
    if (!pidInfo.isInitialized) return (new address[](0));

    // Get cvxLpToken address
    (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidInfo.pid);
    // Check if there is extra rewards
    uint256 extraRewardsLength = IBaseRewardsPool(crvRewards).extraRewardsLength();

    address[] memory tokens = new address[](extraRewardsLength + 2);
    tokens[0] = address(CRV);
    tokens[1] = address(CVX);

    // If there is extra rewards, add them to the array
    if (extraRewardsLength > 0) {
        for (uint256 i = 0; i < extraRewardsLength;) {
            // Add the extra reward token to the array
            tokens[i + 2] = IBaseRewardsPool(crvRewards).extraRewards(i);

            // No need to check for overflow, since i can't be bigger than 2**256 - 1
            unchecked {
                ++i;
            }
        }
    }

    return tokens;
}
```
As we can see, the returned array is hardcoded with `CRV` and `CVX` as the two first values, and then fills in the rest of the list with the `extraRewards` tokens of the pool.

Later in `claimRewards()`, when we actually get the reward, there is a gas optimization where we only pass `true` regarding extra rewards if there are, in fact, extra rewards tokens to claim:
```solidity
IBaseRewardsPool(crvRewards).getReward(address(this), rewardsTokens.length > 0 ? true : false);
```
However, this check compares `rewardTokens.length` to `0`, when it should be compared to `2`, because of the hardcoded values that come before the extra rewards tokens.

### Recommendation

```diff
- IBaseRewardsPool(crvRewards).getReward(address(this), rewardsTokens.length > 0 ? true : false);
+ IBaseRewardsPool(crvRewards).getReward(address(this), rewardsTokens.length > 2 ? true : false);
```

### Review

Fixed as recommended in [PR #38](https://github.com/stake-dao/strategy-optimizor/pull/38/).

## [I-03] Solidity 0.8.20 is unsafe on non-mainnet chains when defaulting to Shanghai

[The Solidity 0.8.20 release adds support for the PUSH0 opcode and sets the default EVM version to Shanghai](https://github.com/ethereum/solidity/releases/tag/v0.8.20)

This is great when deploying only to Ethereum mainnet, as PUSH0 will decrease deployment and runtime costs. However, other EVM chains have not yet added this opcode.

In your `foundry.toml` file, you have (correctly) selected `paris` as the `evm_version`. However, there is a note that says "Shanghai will be tested in the CI.".

### Recommendation

If you plan to deploy on other chains, be sure not to use Shanghai unless you have verified that they have support for PUSH0.

### Review

Confirmed.

## [G-01] Optimizor caches all values, even when caching is turned off

The Optimizor contract has a `useLastOpti` flag that determines whether caching is used or not. If the flag is false, no cached values will ever be used, as the logic for determine whether to use cached values is:
```solidity
if (
    // 1. Optimize calculation is activated
    useLastOpti
    // 2. The cached optimal amount is not too old
    && (
        (isMeta ? lastOptiMetapool[liquidityGauge].timestamp : lastOpti[liquidityGauge].timestamp) + cachePeriod
            > block.timestamp
    )
    // 3. The cached veCRV balance of Stake DAO is below the acceptability threshold
    && absDiff(cacheVeCRVLockerBalance, veCRVBalance) < veCRVBalance.mulWadDown(veCRVDifferenceThreshold)
) {
```
However, when a cached value isn't used, we always cache the locker balance and optimization value:
```solidity
if (cacheVeCRVLockerBalance != veCRVBalance) cacheVeCRVLockerBalance = veCRVBalance;

// Cache optimal amount and timestamp
if (isMeta) {
    // Update the cache for Metapool
    lastOptiMetapool[liquidityGauge] = CachedOptimization(opt, block.timestamp);
} else {
    // Update the cache for Classic Pool
    lastOpti[liquidityGauge] = CachedOptimization(opt, block.timestamp);
}
```
Gas can be saved by only caching the values in the event that `useLastOpti` is `true`. In the event that `useLastOpti` is turned off and later turned back on, it will simply skip using an optimization on the first run (because the timestamp will be too old), cache the first value, and pick up as normal.

### Recommendation
```diff
} else {
    // Calculate optimal amount
    opt = optimalAmount(liquidityGauge, veCRVBalance, isMeta);

+   if (useLastOpti) {
        // Cache veCRV balance of Stake DAO, no need if already the same
        if (cacheVeCRVLockerBalance != veCRVBalance) cacheVeCRVLockerBalance = veCRVBalance;

        // Cache optimal amount and timestamp
        if (isMeta) {
            // Update the cache for Metapool
            lastOptiMetapool[liquidityGauge] = CachedOptimization(opt, block.timestamp);
        } else {
            // Update the cache for Classic Pool
            lastOpti[liquidityGauge] = CachedOptimization(opt, block.timestamp);
        }
+   }
}
```

### Review

Fixed as recommended in [PR #40](https://github.com/stake-dao/strategy-optimizor/pull/40).

## [G-02] Gas can be saved by not using uint8 as a loop counter

In `CurveStrategy.sol#_deposit()`, we loop over all recipients in order to deposit the optimized amount:
```solidity
for (uint8 i; i < recipients.length; ++i) {
    // Skip if the optimized amount is 0
    if (optimizedAmounts[i] == 0) continue;

    // Special process for Stake DAO locker
    if (recipients[i] == address(LOCKER)) {
        _depositIntoLiquidLocker(token, gauge, optimizedAmounts[i]);
    }
    // Deposit into other fallback
    else {
        ERC20(token).safeTransfer(recipients[i], optimizedAmounts[i]);
        BaseFallback(recipients[i]).deposit(token, optimizedAmounts[i]);
    }
}
```
This loop uses a `uint8` to represent `i`. However, it is more efficient to use a `uint256`, as using a `uint8` force a conversion back and forth into `uint256`s, which wastes gas.

The same change can also be made in the following functions:
- `BaseFallback.sol#_handleRewards()`
- `CurveStrategy.sol#claimFallbacks()`

### Proof of Concept

The following standalone test compares two loops. You can see an increase in gas from using `uint8`:
```solidity
function testZach__Uint8GasLoop() public {
    address[] memory recipients = new address[](100);
    for (uint i = 0; i < recipients.length; i++) {
        recipients[i] = address(uint160(i));
    }

    uint gasBefore1 = gasleft();
    for (uint i; i < recipients.length; ++i) {}
    uint gasAfter1 = gasleft();
    console.log("Gas Used with uint256: ", gasBefore1 - gasAfter1);

    uint gasBefore2 = gasleft();
    for (uint8 i; i < recipients.length; ++i) {}
    uint gasAfter2 = gasleft();
    console.log("Gas Used with uint8: ", gasBefore2 - gasAfter2);
}
```
```
Logs:
  Gas Used with uint256:  10945
  Gas Used with uint8:  12951
```

### Recommendation

```diff
  // Loops on fallback to deposit lp tokens
- for (uint8 i; i < recipients.length; ++i) {
+ for (uint256 i; i < recipients.length; ++i) {
    // Skip if the optimized amount is 0
    if (optimizedAmounts[i] == 0) continue;
    ...
}
```

### Review

Fixed as recommended in [PR #32](https://github.com/stake-dao/strategy-optimizor/pull/32).

## [G-03] Can save gas by caching vault address in Frax `withdraw()` function

When `withdraw()` is called on `FallbackConvexFrax.sol`, the value of `vaults[pid]` is accessed 6 times within the function:
```solidity
function withdraw(address token, uint256 amount) external override requiresAuth {
    // Cache the pid
    uint256 pid = pids[stkTokens[token]].pid;

    // Release all the locked curve lp
    IStakingProxyConvex(vaults[pid]).withdrawLockedAndUnwrap(kekIds[vaults[pid]]);
    // Set kekId to 0
    delete kekIds[vaults[pid]];

    // Transfer the curve lp back to user
    ERC20(token).safeTransfer(address(curveStrategy), amount);

    emit Withdrawn(token, amount);

    // If there is remaining curve lp, stake it back
    uint256 remaining = ERC20(token).balanceOf(address(this));

    if (remaining == 0) return;

    // Safe approve lp token to personal vault
    ERC20(token).safeApprove(vaults[pid], remaining);
    // Stake back the remaining curve lp
    kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);

    emit Redeposited(token, remaining);
}
```
Gas can be saved by caching the value once and using the cached value in each of these cases.

### Recommendation

```diff
function withdraw(address token, uint256 amount) external override requiresAuth {
    // Cache the pid
    uint256 pid = pids[stkTokens[token]].pid;
+   address vault = vaults[pid];

    // Release all the locked curve lp
-   IStakingProxyConvex(vaults[pid]).withdrawLockedAndUnwrap(kekIds[vaults[pid]]);
+   IStakingProxyConvex(vault).withdrawLockedAndUnwrap(kekIds[vault]);
    // Set kekId to 0
-   delete kekIds[vaults[pid]];
+   delete kekIds[vault];

    // Transfer the curve lp back to user
    ERC20(token).safeTransfer(address(curveStrategy), amount);

    emit Withdrawn(token, amount);

    // If there is remaining curve lp, stake it back
    uint256 remaining = ERC20(token).balanceOf(address(this));

    if (remaining == 0) return;

    // Safe approve lp token to personal vault
-   ERC20(token).safeApprove(vaults[pid], remaining);
+   ERC20(token).safeApprove(vault, remaining);
    // Stake back the remaining curve lp
-   kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);
+   kekIds[vault] = IStakingProxyConvex(vault).stakeLockedCurveLp(amount, lockingIntervalSec);

    emit Redeposited(token, remaining);
}
```

### Review

The Frax Convex fallback has been removed from the protocol in [PR #41](https://github.com/stake-dao/strategy-optimizor/pull/41), which resolves this issue.