// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// --- Solmate Contracts
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// --- Core Contracts
import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";

// --- Interfaces
import {ILocker} from "src/interfaces/ILocker.sol";
import {IAccumulator} from "src/interfaces/IAccumulator.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ISdtDistributorV2} from "src/interfaces/ISdtDistributorV2.sol";

contract CurveStrategy is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////
    /// --- STRUCTS & ENUMS
    //////////////////////////////////////////////////////
    // --- Structs
    struct Fees {
        uint256 perfFee;
        uint256 accumulatorFee;
        uint256 veSDTFee;
        uint256 claimerRewardFee;
    }

    // --- Enums
    enum MANAGEFEE {
        PERFFEE,
        VESDTFEE,
        ACCUMULATORFEE,
        CLAIMERREWARD
    }

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////
    // --- Interfaces
    ILocker public constant LOCKER = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker

    // --- Addresses
    address public constant CRV_MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
    address public constant CRV_FEE_D = 0xA464e6DCda8AC41e03616F95f4BC98a13b8922Dc;
    address public constant CRV3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    // --- Uints
    uint256 public constant BASE_FEE = 10000; // 100% fees

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    // --- Contracts and Interfaces
    Optimizor public optimizor; // Optimizor contract
    IAccumulator public accumulator = IAccumulator(0xa44bFD194Fd7185ebecEcE4F7fA87a47DaA01c6A); // Stake DAO CRV Accumulator

    // --- Addresses
    address public rewardsReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063; // Stake DAO Rewards Receiver
    address public sdtDistributor = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C; // Stake DAO SDT Distributor
    address public veSDTFeeProxy = 0x9592Ec0605CE232A4ce873C650d2Aa01c79cb69E; // Stake DAO veSDT Proxy

    // --- Bools
    bool public claimAll = true; // Flag for claiming rewards from fallbacks on `claim()`

    // --- Mappings
    // Following mappings need to be initialized on the deployment to match with the previous contract
    mapping(address => bool) public vaults; // vault addres -> is vault active
    mapping(address => address) public gauges; // lp token from curve -> curve gauge
    mapping(address => uint256) public lGaugeType; // liquidity gauge address -> gauge type (0,1,2,3)

    mapping(address => Fees) public feesInfos; // gauge -> fees

    mapping(address => address) public rewardDistributors; // Curve Gauge -> Stake DAO Reward Distributor

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////
    event OptimizorSet(address _optimizor);
    event VeSDTProxySet(address _veSDTProxy);
    event AccumulatorSet(address _accumulator);
    event GaugeSet(address _gauge, address _token);
    event Crv3Claimed(uint256 amount, bool notified);
    event VaultToggled(address _vault, bool _newState);
    event RewardsReceiverSet(address _rewardsReceiver);
    event GaugeTypeSet(address _gauge, uint256 _gaugeType);
    event MultiGaugeSet(address _gauge, address _multiGauge);
    event Claimed(address _gauge, address _token, uint256 _amount);
    event Deposited(address _gauge, address _token, uint256 _amount);
    event Withdrawn(address _gauge, address _token, uint256 _amount);
    event FeeManaged(uint256 _manageFee, address _gauge, uint256 _fee);

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////
    error AMOUNT_NULL();
    error MINT_FAILED();
    error CALL_FAILED();
    error ADDRESS_NULL();
    error CLAIM_FAILED();
    error FEE_TOO_HIGH();
    error WITHDRAW_FAILED();
    error TRANSFER_FROM_LOCKER_FAILED();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address owner, Authority authority) Auth(owner, authority) {}

    //////////////////////////////////////////////////////
    /// --- DEPOSIT
    //////////////////////////////////////////////////////
    function deposit(address token, uint256 amount) external requiresAuth {
        // Transfer the token to this contract
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Do the deposit process
        _deposit(token, amount);
    }

    function depositForOptimizor(address token, uint256 amount) external requiresAuth {
        // Should be better named after
        // Do the deposit process
        _deposit(token, amount);
    }

    function _deposit(address token, uint256 amount) internal {
        // Get the gauge address
        address gauge = gauges[token];
        // Revert if the gauge is not set
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Call the Optimizor contract
        (address[] memory recipients, uint256[] memory optimizedAmounts) =
            optimizor.optimizeDeposit(token, gauge, amount);

        // Loops on fallback to deposit lp tokens
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
    }

    function _depositIntoLiquidLocker(address token, address gauge, uint256 amount) internal {
        ERC20(token).safeTransfer(address(LOCKER), amount);

        // Approve LOCKER to spend token
        LOCKER.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
        LOCKER.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, amount));

        // Locker deposit token
        (bool success,) = LOCKER.execute(gauge, 0, abi.encodeWithSignature("deposit(uint256)", amount));
        if (!success) revert CALL_FAILED();

        emit Deposited(gauge, token, amount);
    }

    //////////////////////////////////////////////////////
    /// --- WITHDRAW
    //////////////////////////////////////////////////////
    function withdraw(address token, uint256 amount) external requiresAuth {
        // Do the withdraw process
        _withdraw(token, amount);

        // Transfer the token to the user
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    function _withdraw(address token, uint256 amount) internal {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Call the Optimizor contract
        (address[] memory recipients, uint256[] memory optimizedAmounts) =
            optimizor.optimizeWithdraw(token, gauge, amount);

        uint256 len = recipients.length;
        for (uint8 i; i < len; ++i) {
            // Skip if the optimized amount is 0
            if (optimizedAmounts[i] == 0) continue;

            // Special process for Stake DAO locker
            if (recipients[i] == address(LOCKER)) {
                _withdrawFromLiquidLocker(token, gauge, optimizedAmounts[i]);
            }
            // Deposit into other fallback
            else {
                BaseFallback(recipients[i]).withdraw(token, optimizedAmounts[i]);
            }
        }
    }

    function _withdrawFromLiquidLocker(address token, address gauge, uint256 amount) internal {
        (bool success,) = LOCKER.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));
        if (!success) revert WITHDRAW_FAILED();

        (success,) =
            LOCKER.execute(token, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), amount));
        if (!success) revert TRANSFER_FROM_LOCKER_FAILED();

        emit Withdrawn(gauge, token, amount);
    }

    //////////////////////////////////////////////////////
    /// --- CLAIM
    //////////////////////////////////////////////////////
    function claim(address token) external requiresAuth {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        if (claimAll) claimFallbacks(token);

        // Get the CRV amount before claim
        uint256 crvBeforeClaim = ERC20(CRV).balanceOf(address(LOCKER));

        // Claim CRV, within the mint() it calls the user checkpoint
        (bool success,) = LOCKER.execute(CRV_MINTER, 0, abi.encodeWithSignature("mint(address)", gauge));
        if (!success) revert MINT_FAILED();

        // Get the CRV amount claimed
        uint256 crvMinted = ERC20(CRV).balanceOf(address(LOCKER)) - crvBeforeClaim;

        // Send CRV here
        (success,) =
            LOCKER.execute(CRV, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), crvMinted));
        if (!success) revert CALL_FAILED();

        // Distribute CRV to fees recipients and gauges
        uint256 crvNetRewards = _sendFee(gauge, CRV, crvMinted);
        ERC20(CRV).safeApprove(rewardDistributors[gauge], crvNetRewards);
        ILiquidityGauge(rewardDistributors[gauge]).deposit_reward_token(CRV, crvNetRewards);
        emit Claimed(gauge, CRV, crvMinted);

        // Distribute SDT to the related gauge
        ISdtDistributorV2(sdtDistributor).distribute(rewardDistributors[gauge]);

        // Claim rewards only for lg type 0 and if there is at least one reward token added
        if (lGaugeType[gauge] == 0 && ILiquidityGauge(gauge).reward_tokens(0) != address(0)) {
            // Cache the reward tokens and their balance before locker
            address[8] memory rewardTokens;
            uint256[8] memory rewardsBalanceBeforeLocker;

            for (uint8 i; i < 8; ++i) {
                // Get reward token
                address rewardToken_ = ILiquidityGauge(gauge).reward_tokens(i);
                if (rewardToken_ == address(0)) break;

                // Add the reward token address on the array
                rewardTokens[i] = rewardToken_;
                // Add the reward token balance ot the locker on the array
                rewardsBalanceBeforeLocker[i] = ERC20(rewardToken_).balanceOf(address(LOCKER));
            }

            // Do the claim
            (success,) = LOCKER.execute(
                gauge, 0, abi.encodeWithSignature("claim_rewards(address,address)", address(LOCKER), address(this))
            );

            // Claim on behalf of locker if previous call failed
            if (!success) {
                ILiquidityGauge(gauge).claim_rewards(address(LOCKER));
            }

            for (uint8 i = 0; i < 8; ++i) {
                // Get reward token from previous cache
                address rewardToken = rewardTokens[i];

                // Break if the reward token is address(0), no need to continue
                if (rewardToken == address(0)) break;

                // Cache rewards balance
                uint256 rewardsBalance;

                // If locker can claim by itslef and transfer here, reward balance is the current balance
                if (success) {
                    rewardsBalance = ERC20(rewardToken).balanceOf(address(this));
                }
                // Else, need to transfer from the locker the claimed amount
                else {
                    // If the reward token is a gauge token (this can happen thanks to new proposal for permissionless gauge token addition),
                    // it need to check only the freshly received rewards are considered as rewards!
                    rewardsBalance = ERC20(rewardToken).balanceOf(address(LOCKER)) - rewardsBalanceBeforeLocker[i];

                    // Transfer the freshly rewards from the locker to here
                    (success,) = LOCKER.execute(
                        rewardToken,
                        0,
                        abi.encodeWithSignature("transfer(address,uint256)", address(this), rewardsBalance)
                    );
                    if (!success) revert CALL_FAILED();
                }
                ERC20(rewardToken).safeApprove(rewardDistributors[gauge], rewardsBalance);
                ILiquidityGauge(rewardDistributors[gauge]).deposit_reward_token(rewardToken, rewardsBalance);
                emit Claimed(gauge, rewardToken, rewardsBalance);
            }
        }
    }

    function claimFallbacks(address token) public requiresAuth {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Get fallbacks addresses
        address[] memory fallbacks = optimizor.getFallbacks();

        // Cache the fallbacks length
        uint256 len = fallbacks.length;
        for (uint8 i = 0; i < len; ++i) {
            // Skip the locker fallback
            if (fallbacks[i] == address(LOCKER)) continue;

            // Do the claim
            (address[] memory rewardsTokens, uint256[] memory amounts) = BaseFallback(fallbacks[i]).claimRewards(token);

            uint256 len2 = rewardsTokens.length;
            // Check balance after claim
            for (uint8 j; j < len2; ++j) {
                // Skip if no reward obtained
                if (amounts[j] == 0) continue;
                // Approve and deposit the reward to the multi gauge
                ERC20(rewardsTokens[j]).safeApprove(rewardDistributors[gauge], amounts[j]);
                ILiquidityGauge(rewardDistributors[gauge]).deposit_reward_token(rewardsTokens[j], amounts[j]);
            }
        }
    }

    function claim3Crv(bool notify) external requiresAuth {
        // Claim 3crv from the curve fee Distributor, it will send 3crv to the crv locker
        (bool success,) = LOCKER.execute(CRV_FEE_D, 0, abi.encodeWithSignature("claim()"));
        if (!success) revert CLAIM_FAILED();

        // Cache amount to send to accumulator
        uint256 amountToSend = ERC20(CRV3).balanceOf(address(LOCKER));
        if (amountToSend == 0) revert AMOUNT_NULL();

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

    function sendToAccumulator(address token, uint256 amount) external requiresAuth {
        ERC20(token).safeApprove(address(accumulator), amount);
        accumulator.depositToken(token, amount);
    }

    //////////////////////////////////////////////////////
    /// --- MIGRATION
    //////////////////////////////////////////////////////
    function migrateLP(address lpToken) external requiresAuth {
        // Only callable by the vault

        // Get gauge address
        address gauge = gauges[lpToken];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Get the amount of LP token staked in the gauge by the locker
        uint256 amount = ERC20(gauge).balanceOf(address(LOCKER));

        // Locker withdraw all from the gauge
        (bool success,) = LOCKER.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));
        if (!success) revert WITHDRAW_FAILED();

        // Locker transfer the LP token to the vault
        (success,) =
            LOCKER.execute(lpToken, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount));
        if (!success) revert CALL_FAILED();
    }

    //////////////////////////////////////////////////////
    /// --- SETTERS
    //////////////////////////////////////////////////////
    function toggleVault(address vault) external requiresAuth {
        if (vault == address(0)) revert ADDRESS_NULL();
        vaults[vault] = !vaults[vault];
        emit VaultToggled(vault, vaults[vault]);
    }

    function setGauge(address token, address gauge) external requiresAuth {
        if (token == address(0)) revert ADDRESS_NULL();
        gauges[token] = gauge;
        emit GaugeSet(gauge, token);
    }

    function setLGtype(address gauge, uint256 gaugeType) external requiresAuth {
        if (gauge == address(0)) revert ADDRESS_NULL();
        lGaugeType[gauge] = gaugeType;
        emit GaugeTypeSet(gauge, gaugeType);
    }

    function setMultiGauge(address gauge, address multiGauge) external requiresAuth {
        if (gauge == address(0) || multiGauge == address(0)) revert ADDRESS_NULL();
        rewardDistributors[gauge] = multiGauge;
        emit MultiGaugeSet(gauge, multiGauge);
    }

    function setVeSDTProxy(address newVeSDTProxy) external requiresAuth {
        if (newVeSDTProxy == address(0)) revert ADDRESS_NULL();
        veSDTFeeProxy = newVeSDTProxy;
        emit VeSDTProxySet(newVeSDTProxy);
    }

    function setAccumulator(address newAccumulator) external requiresAuth {
        if (newAccumulator == address(0)) revert ADDRESS_NULL();
        accumulator = IAccumulator(newAccumulator);
        emit AccumulatorSet(newAccumulator);
    }

    function setRewardsReceiver(address newRewardsReceiver) external requiresAuth {
        if (newRewardsReceiver == address(0)) revert ADDRESS_NULL();
        rewardsReceiver = newRewardsReceiver;
        emit RewardsReceiverSet(newRewardsReceiver);
    }

    function setOptimizor(address newOptimizor) external requiresAuth {
        if (newOptimizor == address(0)) revert ADDRESS_NULL();
        optimizor = Optimizor(newOptimizor);
        emit OptimizorSet(newOptimizor);
    }

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

    //////////////////////////////////////////////////////
    /// --- EXECUTE
    //////////////////////////////////////////////////////
    function execute(address to, uint256 value, bytes calldata data)
        external
        requiresAuth
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }
}
