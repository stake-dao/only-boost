
# <h1 align="center">Only Boost</h1>

This repo contains the implementation of OnlyBoost white paper. Smart contracts related to the CRV Liquid Locker to optimize distribution of funds between Stake DAO and Convex Curve / Convex Frax in order to maximizing boost.


## Installation

Install Foundry:
```bash
   # This will install Foundryup
   curl -L https://foundry.paradigm.xyz | bash
   # Then Run
   foundryup
```

Install Dependencies:
```bash
    forge install
```

Build:
```bash
    forge b
```

Run all tests:
```bash
    make test
```
    
## What is OnlyBoost

OnlyBoost is a set of smart contract designed to maximize the boost on the Curve LP with Stake DAO using Convex Curve and Convex Frax as fallback, when boost is not optimal anymore on Stake DAO. 

The splitting logic is the following: 
-  First deposit as much as possible through Stake DAO Liquid Locker, as long as the boost remains optimal. 
- Once the boost is not optimal, check if the pool exists on Convex Frax. 
    - If yes then deposit on Convex Frax, because we assumed that yield for the same pool is always better on Convex Frax than on Convex Curve. 
    - If no then deposit on Convex Curve. 

The optimal amount that should held Stake DAO Liquid Locker is calculated using the following formula: 
<img width="1218" alt="Capture d’écran 2023-07-07 à 16 09 56" src="https://github.com/stake-dao/strategy-optimizor/assets/55331875/e2c99740-39cc-4f09-8c2d-fb732d274baa">

- Nomenclature
    - BalanceOf Convex : B_CVX 
    - BalanceOf veCRV Stake DAO: veCRV_SDT
    - BalanceOf veCRV Convex: veCRV_CVX 
    - Total veCRV: veCRV_TOTAL
    - TotalSupply: TS
    - Fees Convex: F_CVX
    - Fees Stake DAO: F_SDT
    - Boost from Convex Frax : AddBoost_FRAX (correspond to extra yield between Convex Curve and Convex Frax)

The following architectur has been implemented using 4 main contracts : 
1. Optimizor
2. Strategy
3. ConvexFallback
4. FallbackConvexFrax

<img width="819" alt="Capture d’écran 2023-07-07 à 16 10 27" src="https://github.com/stake-dao/strategy-optimizor/assets/55331875/10a4358f-f4a4-4246-b1f4-a826b21b0b47">



## Optimizor

The optimizor has 2 main roles, one for deposit, one for withdraw and an option to stop deposit into Convex Frax. 

1. Deposit: When on Strategy contract, `deposit()` is called, `optimizeDeposit()` will be called to on the Optimizor. This will return to the Strategy contract 2 arrays. First one with addresses where LP have to be sent and second one amounts of LP to sent. The first array always starts with Stake DAO Liquid Locker.  

- Amounts are calculated using the previous optimization formula. For gas saving, a cached value can be used. It will be used if the 3 following conditions are true: 

    - `cacheEnabled` boolean is true.
    - if last cached timestamp for this gauge is older than `cachePeriod` (7 days by default).
    - if the cached veCRV balance of Stake DAO Liquid Locker is below the acceptability threshold `veCRVDifferenceThreshold` (5% by default).

2. Withdraw: Withdrawal doesn't follow any optimization formula, it just remove liquidity first from Convex, then withdraw liquidity from Stake DAO Liquid Locker. As on deposit, it returns two arrays, one for addresses to withdraw liquidity, one for the amounts to withdraw.

3. There is one option on this Optimizor to kill Convex Frax deposit. This situation can be useful if we want to use Stake DAO Frax Liquid Locker instead of Convex Frax as fallback. To trigger this kills, Convex Frax fallback should be paused for more than the `lockingIntervalSec` defined on the Convex Frax fallback. When this is ok, it will go through all of the `pids` where fallback has some liquidity, withdraw all of it, and then deposit it again using the Curve Strategy `depositForOptimizor()`. 
## Curve Strategy
This contract is the core contract where all the LPs will transfer from the Stake DAO Vaults into the corresponding locker (Stake DAO, Convex Curve, Convex Frax). This contract can be seen as an update of the previous Curve Strategy already deployed on mainnet : `0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6`;

- When Optimizor contract is set, this contract doesn't have to "think" to where should the liquidity be deposited or withdraw. It just receive destination and amount from Optimizor and sends it. 
- When Optimizor contract is not set, this contract only deposit and withdraw from Stake DAO Liquid Locker.
## Fallbacks
Fallbacks refer to the other protocol to use in order to maximize boost on Curve LP. At the moment, there are two fallback contract : Convex Curve and Convex Frax.
The split between Convex Curve and Convex Frax is the following: if the pool corresponding to the LPs in available en Convex Frax then use it, otherwise use Convex Curve.

Both fallback use the same base: `BaseFallback`.

Because there is no on-chain mapping from LP Token to pool id from Convex (named pid), this is done on the deployment of the contract by checking the LP Token into each actual pid on Convex.

Regarding the fees, there are only taken on `CRV`, all of the remaining rewards are sends into current `LiquidityGauge`.

### Convex Curve
This contract is straight forward and handle all the interaction with Convex Curve Booster contract: 
- `deposit()`
- `withdraw()`
- `claimRewards()`

### Convex Frax 
This contract handle all of the interaction with Convex Frax Booster / Pool Registry contract.

- On first `deposit()` a personal vault need to be created, and LPs are locked for `lockingIntervalSec` (7 days by default). Then all the following deposit will be on the same vault without increasing the lock period.
- On `withdraw()` all of the LPs are withdrawn from personal vault, and remaining is then relocked again for `lockingIntervalSec` (7 days by default).

There's a subtlety here, because there are some periods where LP are locked. `balanceOf()` return only the liquid liquidity.
## Dependencies

All of the previous contract inherit from `Auth` from [Solmate]( 
https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol).

The authority will be `RolesAuthority` contract from [Solmate]( 
https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/RolesAuthority.sol).

All of the previous contract use `SafeTransferLib` library from [Solmate](https://github.com/transmissions11/solmate/blob/main/src/utils/SafeTransferLib.sol) for ERC20 interactions. 

All of the previous contract use `FixedPointMathLib` library from [Solmate](https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol) for most off percentage calculation. 
