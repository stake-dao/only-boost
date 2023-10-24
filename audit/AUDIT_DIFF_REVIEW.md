# Code Audit Diff Review

*Commit Hash:* [6d2929fa8a68b02bec39025986159f1186576229] (After fix complexions)

## Vulnerabilities found after audit

1. **Fix for H-03 is wrong:**  
   - *Location:* Optimizor.sol.
   - *Description:* Convex has the ability to manipulate the cached value. A solution was suggested to also cache the Convex Balance. However, the proposed fix was flawed because it compared the liquidity gauge's balance with a stored value, rather than using a mapping for each gauge.

   ```solidity
   /// @notice Cached Convex balance
   uint256 public cacheConvexBalance;

   uint256 balanceConvex = ERC20(liquidityGauge).balanceOf(LOCKER_CONVEX);
   ...
    && absDiff(cacheConvexBalance, balanceConvex) < balanceConvex.mulWadDown(convexDifferenceThreshold)
   ```

2. **Claim on Convex can be bricked due to the nature of the rewards:**  
   - *Location:* FallbackConvexCurve.sol
   - *Description:* The `claimRewards` function invokes the `getRewardsToken` function, which is designed to fetch all claimable tokens and additional reward addresses. Once all rewards are claimed, they are forwarded to the strategy. However, the `extraRewards` function returns the address of a `VirtualBalanceRewardPool` rather than the actual token address. As a result, the transfer to the strategy doesn't occur, leaving the funds stranded in the FallbackConvexCurve.

   Source: <https://docs.convexfinance.com/convexfinanceintegration/baserewardpool>

3. **Anyone can claim for users on Convex:**  
   - *Location:* FallbackConvexCurve.sol
   - *Description:* On Convex, anyone can claim rewards for someone else. This can be misused, letting people take others' rewards. Someone might claim from a large pool on Convex, and because the contract sends the whole balance to the strategy, they might end up getting more rewards if they have a lot of shares in the liquidity gauge. Additionnaly, there's no way to correctly identify where the funds should be allocated if by mistake an external claim happens unless using `rescueERC20` but it requires off-chain work.

4. **PID Can be overridden and brick Withdrawals:**  
   - *Location:* FallbackConvexCurve.sol
   - *Description:* If Curve upgrades its gauge technology to add new features, like supporting crvUSD collateral which requires new oracles not available in their older tech, they might release newer versions as they've done before (e.g., V2, V4). Convex might respond by closing an outdated pool and launching a new one using the same lpToken. In our FallbackConvexCurve setup, this can lead to issues. Specifically, using the setAllPidsOptimized function to map tokens to pids might overwrite existing mappings. If we've already made deposits, this change can disrupt withdrawals.

   ```solidity
        // Cache the length of the pool registry
        uint256 len = BOOSTER_CONVEX_CURVE.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCount == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCount; i < len;) {
            // Get the LP token address
            (address token,,,,,) = BOOSTER_CONVEX_CURVE.poolInfo(i);

            // Map the LP token to the pool infos
            pids[token] = PidsInfo(i, true);

            // No need to check for overflow, since i can't be bigger than 2**256 - 1
            unchecked {
                ++i;
            }
        }
    ```

   Source: <https://curve.readthedocs.io/dao-gauges.html>