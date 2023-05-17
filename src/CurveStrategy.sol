// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Optimizor} from "src/Optimizor.sol";
import {ConvexMapper} from "src/ConvexMapper.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {IAccumulator} from "src/interfaces/IAccumulator.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {IBaseRewardsPool} from "src/interfaces/IBaseRewardsPool.sol";
import {IFraxUnifiedFarm} from "src/interfaces/IFraxUnifiedFarm.sol";
import {ISdtDistributorV2} from "src/interfaces/ISdtDistributorV2.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IStakingProxyConvex} from "src/interfaces/IStakingProxyConvex.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract CurveStrategy is Auth {
    using SafeTransferLib for ERC20;

    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV token
    address public constant CRV_MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0; // CRV minter
    ILocker public constant LOCKER_STAKEDAO = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker
    uint256 public constant BASE_FEE = 10_000;

    Optimizor public optimizor; // Optimizor contract
    ConvexMapper public convexMapper; // Convex mapper
    IBoosterConvexFrax public boosterConvexFrax; // Convex Frax booster
    IAccumulator public accumulator = IAccumulator(0xa44bFD194Fd7185ebecEcE4F7fA87a47DaA01c6A); // Accumulator contract

    uint256 public lockingIntervalSec = 7 days; // 7 days

    address public veSDTFeeProxy = 0x9592Ec0605CE232A4ce873C650d2Aa01c79cb69E; // veSDT fee proxy
    address public sdtDistributor = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C; // SDT distributor
    address public rewardsReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063; // Rewards receiver

    mapping(address => address) public gauges; // lp token from curve -> curve gauge
    mapping(uint256 => address) public vaults; // pid from convex frax -> personal vault for convex frax
    mapping(address => bytes32) public kekIds; // personal vault on convex frax -> kekId

    // To be initialized by governance at the deployment
    mapping(address => uint256) public perfFee;
    mapping(address => address) public multiGauges;
    mapping(address => uint256) public accumulatorFee; // gauge -> fee
    mapping(address => uint256) public claimerRewardFee; // gauge -> fee
    mapping(address => uint256) public veSDTFee; // gauge -> fee
    mapping(address => uint256) public lGaugeType;

    error ADDRESS_NULL();
    error DEPOSIT_FAIL();

    constructor(Authority _authority) Auth(msg.sender, _authority) {
        optimizor = new Optimizor();
        convexMapper = new ConvexMapper();
        boosterConvexFrax = IBoosterConvexFrax(0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa);
    }

    function deposit(address token, uint256 amount) external {
        // Only vault can call this function
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Check if the pool is active on convexFrax
        (uint256 isOnCurveOrFrax, uint256 pid) = convexMapper.getPid(token);

        // Call the optimizor to get the optimal amount to deposit in Stake DAO
        uint256 result = optimizor.optimization(gauge, isOnCurveOrFrax == 2);

        // Deposit first on Stake DAO
        uint256 balanceStakeDAO = ERC20(gauge).balanceOf(address(LOCKER_STAKEDAO));
        if (balanceStakeDAO < result) {
            // Is there is no vault on Convex deposit all on Stake DAO
            uint256 toDeposit = isOnCurveOrFrax == 0 ? amount : min(result - balanceStakeDAO, amount);
            // Update amount, cannot underflow due to previous min()
            amount -= toDeposit;

            ERC20(token).safeTransfer(address(LOCKER_STAKEDAO), toDeposit);

            // Approve LOCKER_STAKEDAO to spend token
            LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
            LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, toDeposit));

            // Locker deposit token
            (bool success,) = LOCKER_STAKEDAO.execute(gauge, 0, abi.encodeWithSignature("deposit(uint256)", toDeposit));
            require(success, "Deposit failed!");
        }

        // Deposit all the remaining on Convex
        if (amount > 0) {
            if (isOnCurveOrFrax == 2) {
                // Deposit on ConvexFrax
                if (vaults[pid] == address(0)) {
                    // Create personal vault if not exist
                    vaults[pid] = boosterConvexFrax.createVault(pid);
                }
                // Safe approve lp token to personal vault
                ERC20(token).safeApprove(vaults[pid], amount);

                if (kekIds[vaults[pid]] == bytes32(0)) {
                    // If no kekId, stake locked curve lp
                    kekIds[vaults[pid]] =
                        IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);
                } else {
                    // Else lock additional curve lp
                    IStakingProxyConvex(vaults[pid]).lockAdditionalCurveLp(kekIds[vaults[pid]], amount);
                }
            } else {
                // Deposit on ConvexCurve
                // Cache Convex Curve booster address
                IBoosterConvexCurve convex = convexMapper.boosterConvexCurve();
                // Safe approve lp token to convex curve booster
                ERC20(token).safeApprove(address(convex), amount);
                // Deposit on ConvexCurve
                if (!convex.deposit(pid, amount, true)) revert DEPOSIT_FAIL();
            }
        }
    }

    function withdraw(address token, uint256 amount) external {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Check if the pool is active on convexFrax
        (uint256 isOnCurveOrFrax, uint256 pid) = convexMapper.getPid(token);

        uint256 balanceLPBefore = ERC20(token).balanceOf(address(this));
        // Withdraw from Convex first
        if (isOnCurveOrFrax == 1) {
            // Cache Convex Curve booster address
            IBoosterConvexCurve convex = convexMapper.boosterConvexCurve();

            // Get cvxLpToken address
            (,,, address crvRewards,,) = convex.poolInfo(pid);
            // Check current balance on convexCurve
            uint256 balanceCvxLPToken = ERC20(crvRewards).balanceOf(address(this));

            // Amount to withdraw from convexCurve
            uint256 toWithdraw = min(balanceCvxLPToken, amount);
            // Update amount, cannot underflow due to previous min()
            amount -= toWithdraw;

            // Withdraw from ConvexCurve gauge
            IBaseRewardsPool(crvRewards).withdrawAndUnwrap(toWithdraw, false);
        } else if (isOnCurveOrFrax == 2) {
            // Cache convex frax pool registry address
            IPoolRegistryConvexFrax poolRegistryConvexFrax = convexMapper.poolRegistryConvexFrax();
            // Withdraw from ConvexFrax
            (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pid);
            // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
            // and the last one is emptyed. So we need to get the last one.
            uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(vaults[pid]);
            // Cache lockedStakes infos
            IFraxUnifiedFarm.LockedStake memory infos =
                IFraxUnifiedFarm(staking).lockedStakesOf(vaults[pid])[lockCount - 1];

            // If locktime has endend, withdraw
            if (block.timestamp >= infos.ending_timestamp) {
                uint256 toWithdraw = min(infos.liquidity, amount);
                amount -= toWithdraw;

                // Release all the locked curve lp
                IStakingProxyConvex(vaults[pid]).withdrawLockedAndUnwrap(kekIds[vaults[pid]]);
                // Set kekId to 0
                delete kekIds[vaults[pid]];

                // Safe approve lp token to personal vault
                ERC20(token).safeApprove(vaults[pid], infos.liquidity - toWithdraw);
                // Stake back the remaining curve lp
                kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(
                    infos.liquidity - toWithdraw, lockingIntervalSec
                );
            }
        }

        // Withdraw the remaining from Stake DAO
        if (amount > 0) {
            uint256 _before = ERC20(token).balanceOf(address(LOCKER_STAKEDAO));

            (bool success,) = LOCKER_STAKEDAO.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));
            require(success, "Transfer failed!");
            uint256 _after = ERC20(token).balanceOf(address(LOCKER_STAKEDAO));

            uint256 _net = _after - _before;
            (success,) = LOCKER_STAKEDAO.execute(
                token, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), _net)
            );
            require(success, "Transfer failed!");
        }

        // Transfer all the remaining token to vault
        ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)) - balanceLPBefore);
    }

    function claimRewards(address token) external {
        address gauge = gauges[token];
        require(gauge != address(0), "!gauge");

        uint256 crvBeforeClaim = CRV.balanceOf(address(LOCKER_STAKEDAO));

        // Claim CRV
        // within the mint() it calls the user checkpoint
        (bool success,) = LOCKER_STAKEDAO.execute(CRV_MINTER, 0, abi.encodeWithSignature("mint(address)", gauge));
        require(success, "CRV mint failed!");

        uint256 crvMinted = CRV.balanceOf(address(LOCKER_STAKEDAO)) - crvBeforeClaim;

        // Send CRV here
        (success,) = LOCKER_STAKEDAO.execute(
            address(CRV), 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), crvMinted)
        );
        require(success, "CRV transfer failed!");

        // Distribute CRV
        uint256 crvNetRewards = sendFee(gauge, address(CRV), crvMinted);
        CRV.approve(multiGauges[gauge], crvNetRewards);
        ILiquidityGauge(multiGauges[gauge]).deposit_reward_token(address(CRV), crvNetRewards);
        //emit Claimed(gauge, CRV, crvMinted);

        // Distribute SDT to the related gauge
        ISdtDistributorV2(sdtDistributor).distribute(multiGauges[gauge]);

        // Claim rewards only for lg type 0 and if there is at least one reward token added
        if (lGaugeType[gauge] == 0 && ILiquidityGauge(gauge).reward_tokens(0) != address(0)) {
            (success,) = LOCKER_STAKEDAO.execute(
                gauge,
                0,
                abi.encodeWithSignature("claim_rewards(address,address)", address(LOCKER_STAKEDAO), address(this))
            );
            if (!success) {
                // Claim on behalf of LOCKER_STAKEDAO
                ILiquidityGauge(gauge).claim_rewards(address(LOCKER_STAKEDAO));
            }
            address rewardToken;
            uint256 rewardsBalance;
            for (uint8 i = 0; i < 8; i++) {
                rewardToken = ILiquidityGauge(gauge).reward_tokens(i);
                if (rewardToken == address(0)) {
                    break;
                }
                if (success) {
                    rewardsBalance = ERC20(rewardToken).balanceOf(address(this));
                } else {
                    rewardsBalance = ERC20(rewardToken).balanceOf(address(LOCKER_STAKEDAO));
                    (success,) = LOCKER_STAKEDAO.execute(
                        rewardToken,
                        0,
                        abi.encodeWithSignature("transfer(address,uint256)", address(this), rewardsBalance)
                    );
                    require(success, "Transfer failed");
                }
                ERC20(rewardToken).approve(multiGauges[gauge], rewardsBalance);
                ILiquidityGauge(multiGauges[gauge]).deposit_reward_token(rewardToken, rewardsBalance);
                //emit Claimed(gauge, rewardToken, rewardsBalance);
            }
        }
    }

    function sendFee(address _gauge, address _rewardToken, uint256 _rewardsBalance) internal returns (uint256) {
        // calculate the amount for each fee recipient
        uint256 multisigFee = (_rewardsBalance * perfFee[_gauge]) / BASE_FEE;
        uint256 accumulatorPart = (_rewardsBalance * accumulatorFee[_gauge]) / BASE_FEE;
        uint256 veSDTPart = (_rewardsBalance * veSDTFee[_gauge]) / BASE_FEE;
        uint256 claimerPart = (_rewardsBalance * claimerRewardFee[_gauge]) / BASE_FEE;
        // send
        ERC20(_rewardToken).approve(address(accumulator), accumulatorPart);
        accumulator.depositToken(_rewardToken, accumulatorPart);
        ERC20(_rewardToken).transfer(rewardsReceiver, multisigFee);
        ERC20(_rewardToken).transfer(veSDTFeeProxy, veSDTPart);
        ERC20(_rewardToken).transfer(msg.sender, claimerPart);
        return _rewardsBalance - multisigFee - accumulatorPart - veSDTPart - claimerPart;
    }

    function setGauge(address token, address gauge) external {
        gauges[token] = gauge;
    }

    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return (a < b) ? a : b;
    }
}
