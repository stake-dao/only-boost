# Curve strategy update

General idea: deposit into Convex as fallback for APR optimization


## Moving from old strategy to new strategy

Call `setCurveStrategy(address _newStrat)` on `CurveVault.sol`. 
This bring several issues like:
1. For each time `setCurveStrategy` is called, LPs from the CurveVault are withdrawn from the gauge, transfered back to the CurveVault, and the send back to the gauge throught the locker and the new strategy. 
This cost at 30gwei around 0.015ETH (if the old strategy is used as new strategy). There is 104 strategies, this will cost roughly 1.5-2 ETH for calling setCurveStrategy on all vault. 

2. If a CurveVault is forgotten, funds will be stuck. Because when setCurveStrategy is called, funds are withdraw by the strategy from the locker. But for this actions strategy need to have "strategy" or "governance" role on the locker. 

3. There is some ownership issues to take into account too. Because on the setCurveStrategy, LPs are withdrawn from the locker by the strategy which need the role to do it. But right after the LPs are deposited again on the locker throught the new strategy which need the role to deposit too. So at the end the roles "governance" or "strategy" must be done in one way and then in the other. 

4. The current strategy on the locker is the `CurveDepositor` contract and the current governance on the locker is the `CurveStrategy`. The governance of the `CurveStrategy` is the `CurveVoterV2`, and the governance of the `CurveVoterV2` is the multisig.

Suggestion : There are two addresses that can call `execute` function from locker : "governance" (the current `CurveStrategy`) and "strategy" (the current `CurveDepositor`). The "strategy" role can be temporaly set to the new strategy, this will allow a easier transition from old strategy to new one.
## New strategy logic


#### Optimizor
- The new optimizor should work like an external module that only do the calculation and return the optimal amount to deposit into Stake DAO. 
- The optimal value should be calculated on each `earn` call. Storing this value can save some gas, instead of calculate it at every `earn`.

#### LPs flow
- Main objectiv is to use the Stake DAO locker until the maximum, given by the optimization formula below.
- If the maximum is reached, then use Convex as fallback for depositing LPs. 
- If there is a gauge for this on convexFrax then use it, otherwise use convexCurve. If a gauge exist should be take into account on the optimization formula. 
- Stratey should handle different path for deposit, at the moment there is only Stake DAO and Convex to deposit in, but if in the futur there is more, it should be easy to do.

#### Rewards
- All rewards claimed from Curve, Convex or convexFrax are deposite in a LiquidityGauge corresponding to the `CurveVault`.
## Calculation for the optimization

### Nomenclature
    1. BalanceOf Convex : B_CVX 
    2. BalanceOf StakeDAO: B_SDT (Not used)
    3. BalanceOf veCRV Stake DAO: veCRV_SDT
    4. BalanceOf veCRV Convex: veCRV_CVX 
    5. Total veCRV: veCRV_TOTAL
    6. TotalSupply: TS
    7. Gauge Working Supply:  GWS
    8. CVX Total Supply: CVX_Total
    9. vlCVX Total Supply : vlCVX_Total
    10. Fees Convex: F_CVX
    11. Fees Stake DAO: F_SDT
    12. Boost from Frax : AddBoost_FRAX (tbd)

### Calculation
    1. Additional convex boost : AddBoost_FRAX + AddBoost_CVX = (1 - CVX_Total / 10^8) * veCRV_CVX / vlCVX_TOTAL 

### Optimization
    1. B_CVX * (veCRV_SDT / veCRV_CVX) * (1 - F_SDT) / (1 - F_CVX + AddBoost_CVX)
    2. 3 * (1 - F_SDT) * B_CVX * veCRV_SDT * TS / (2 * (F_SDT - F_CVX  + AddBoost_CVX) * B_CVX * veCRV_TOTAL + 3 * veCRV_CVX * TS * (1 - F_CVX + AddBoost_CVX))
    3. B_CVX * veCRV_SDT / (veCRV_CVX * (1 + AddBoost_CVX))