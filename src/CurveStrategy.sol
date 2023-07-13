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

/// @title CurveStrategy
/// @author Stake DAO
/// @notice Strategy for Curve LP tokens
/// @dev Inherits from Solmate `Auth` implementatio
contract CurveStrategy is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////
    /// --- STRUCTS & ENUMS
    //////////////////////////////////////////////////////

    // --- Structs
    /// @notice Struct to store fees
    /// @param perfFee Fee collected as performance fee
    /// @param accumulatorFee Fee collected for accumulator
    /// @param veSDTFee Fee collected for veSDT holders
    /// @param claimerRewardFee Fee collected for reward claimer
    struct Fees {
        uint256 perfFee;
        uint256 accumulatorFee;
        uint256 veSDTFee;
        uint256 claimerRewardFee;
    }

    // --- Enums
    /// @notice Enum to store fee types
    /// @param PERFFEE Performance fee
    /// @param VESDTFEE veSDT fee
    /// @param ACCUMULATORFEE Accumulator fee
    /// @param CLAIMERREWARD Claimer reward fee
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
    /// @notice Interface for Stake DAO CRV Locker
    ILocker public constant LOCKER = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6);

    // --- Addresses
    /// @notice Curve DAO CRV Minter
    address public constant CRV_MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    /// @notice Curve DAO CRV Fee Distributor
    address public constant CRV_FEE_D = 0xA464e6DCda8AC41e03616F95f4BC98a13b8922Dc;

    /// @notice Curve DAO 3Pool LP Token
    address public constant CRV3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;

    /// @notice Curve DAO ERC20 CRV Token
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    // --- Uints
    /// @notice Base for fees calculation, represents 100% in base fee
    uint256 public constant BASE_FEE = 10000;

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////

    // --- Contracts and Interfaces
    /// @notice Optimizor contract
    Optimizor public optimizor;

    /// @notice Interface for Stake DAO CRV Accumulator
    IAccumulator public accumulator = IAccumulator(0xa44bFD194Fd7185ebecEcE4F7fA87a47DaA01c6A);

    // --- Addresses
    /// @notice Stake DAO Rewards Receiver
    address public rewardsReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    /// @notice Stake DAO SDT Distributor
    address public sdtDistributor = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;

    /// @notice Stake DAO veSDT Proxy
    address public veSDTFeeProxy = 0x9592Ec0605CE232A4ce873C650d2Aa01c79cb69E;

    // --- Bools
    /// @notice Flag for claiming rewards from fallbacks on `claim()`
    bool public claimAll = true;

    // --- Mappings
    // Following mappings need to be initialized on the deployment to match with the previous strategy contract
    /// @notice Map vaults address -> is vault active
    mapping(address => bool) public vaults;

    /// @notice Map LP token from curve -> curve gauge
    mapping(address => address) public gauges;

    /// @notice Map liquidity gauge address -> gauge type (0,1,2,3)
    mapping(address => uint256) public lGaugeType;

    /// @notice Map Stake DAO liquidity gauge -> Fees struct
    mapping(address => Fees) public feesInfos;

    /// @notice Map Curve liquidity gauge -> Stake DAO Reward Distributor
    mapping(address => address) public rewardDistributors;

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////$

    /// @notice Emitted when a new Optimizor contract is set
    /// @param _optimizor Address of the new Optimizor contract
    event OptimizorSet(address _optimizor);

    /// @notice Emitted when a new veSDT Proxy contract is set
    /// @param _veSDTProxy Address of the new veSDT Proxy contract
    event VeSDTProxySet(address _veSDTProxy);

    /// @notice Emitted when a new Stake DAO CRV Accumulator is set
    /// @param _accumulator Address of the new Stake DAO CRV Accumulator
    event AccumulatorSet(address _accumulator);

    /// @notice Emitted when a new Curve liquidity gauge is set
    /// @param _gauge Address of the new Curve liquidity gauge
    /// @param _token Address of the LP token
    event GaugeSet(address _gauge, address _token);

    /// @notice Emitted when CRV3 is claimed
    /// @param amount Amount of CRV3 claimed
    /// @param notified Flag for notifying Stake DAO CRV Accumulator
    event Crv3Claimed(uint256 amount, bool notified);

    /// @notice Emitted when a Stake DAO vault is toggled
    /// @param _vault Address of the Stake DAO vault
    /// @param _newState New state of the vault
    event VaultToggled(address _vault, bool _newState);

    /// @notice Emitted when a reward receiver is set
    /// @param _rewardsReceiver Address of the new rewards receiver
    event RewardsReceiverSet(address _rewardsReceiver);

    /// @notice Emitted when a liquidity gauge type is set
    /// @param _gauge Address of the liquidity gauge
    /// @param _gaugeType Type of the liquidity gauge
    event GaugeTypeSet(address _gauge, uint256 _gaugeType);

    /// @notice Emitted when a Stake DAO liquidity gauge is set
    /// @param _gauge Address of the Curve DAO liquidity gauge
    /// @param _multiGauge Address of the Stake DAO reward distributor
    event MultiGaugeSet(address _gauge, address _multiGauge);

    /// @notice Emitted when a rewards are claimed
    /// @param _gauge Address of the Curve DAO liquidity gauge
    /// @param _token Address of the LP token
    /// @param _amount Amount of rewards claimed
    event Claimed(address _gauge, address _token, uint256 _amount);

    /// @notice Emitted when a token is deposited
    /// @param _gauge Address of the Curve DAO liquidity gauge
    /// @param _token Address of the LP token
    /// @param _amount Amount of tokens deposited
    event Deposited(address _gauge, address _token, uint256 _amount);

    /// @notice Emitted when a token is withdrawn
    /// @param _gauge Address of the Curve DAO liquidity gauge
    /// @param _token Address of the LP token
    /// @param _amount Amount of tokens withdrawn
    event Withdrawn(address _gauge, address _token, uint256 _amount);

    /// @notice Emitted when fee are updated
    /// @param _manageFee New management fee
    /// @param _gauge Address of the Curve DAO liquidity gauge
    /// @param _fee New performance fee
    event FeeManaged(uint256 _manageFee, address _gauge, uint256 _fee);

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error emitted when input amount is null
    error AMOUNT_NULL();

    /// @notice Error emitted when amount minted is null
    error MINT_FAILED();

    /// @notice Error emitted when external call failed
    error CALL_FAILED();

    /// @notice Error emitted when input address is null
    error ADDRESS_NULL();

    /// @notice Error emitted when external claim failed
    error CLAIM_FAILED();

    /// @notice Error emitted when sum of fees is above 100%
    error FEE_TOO_HIGH();

    /// @notice Error emitted when withdraw from locker failed
    error WITHDRAW_FAILED();

    /// @notice Error emitted when transfer from locker failed
    error TRANSFER_FROM_LOCKER_FAILED();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address owner, Authority authority) Auth(owner, authority) {}

    //////////////////////////////////////////////////////
    /// --- DEPOSIT
    //////////////////////////////////////////////////////

    /// @notice Main gateway to deposit LP token into this strategy
    /// @dev Only callable by the `vault` or the governance
    /// @param token Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function deposit(address token, uint256 amount) external requiresAuth {
        // Transfer the token to this contract
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Do the deposit process
        _deposit(token, amount);
    }

    /// @notice Optimizor gateway to deposit LP token into this strategy
    /// @dev Only callable by the `optimizor` or the governance, should be used only when migration
    /// @param token Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function depositForOptimizor(address token, uint256 amount) external requiresAuth {
        // Should be better named after
        // Do the deposit process
        _deposit(token, amount);
    }

    /// @notice Internal gateway to deposit LP into this strategy
    /// @dev First check the optimal split, then send it to respective recipients
    /// @param token Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function _deposit(address token, uint256 amount) internal {
        // Get the gauge address
        address gauge = gauges[token];
        // Revert if the gauge is not set
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Initiate the recipients and amounts arrays
        address[] memory recipients;
        uint256[] memory optimizedAmounts;

        if (address(optimizor) != address(0)) {
            // Call the Optimizor contract
            (recipients, optimizedAmounts) = optimizor.optimizeDeposit(token, gauge, amount);
        } else {
            // Shortcut if no Optimizor contract, deposit all on Stake DAO
            _depositIntoLiquidLocker(token, gauge, amount);

            // No need to go futher on the function
            return;
        }

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

    /// @notice Internal gateway to deposit LP token using Stake DAO Liquid Locker
    /// @param token Address of LP token to deposit
    /// @param gauge Address of Liqudity gauge corresponding to LP token
    /// @param amount Amount of LP token to deposit
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

    /// @notice Main gateway to withdraw LP token from this strategy
    /// @dev Only callable by `vault` or governance
    /// @param token Address of LP token to withdraw
    /// @param amount Amount of LP token to withdraw
    function withdraw(address token, uint256 amount) external requiresAuth {
        // Do the withdraw process
        _withdraw(token, amount);

        // Transfer the token to the user
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice Internal gateway to withdraw LP token from this strategy
    /// @dev First check where to remove liquidity, then remove liquidity accordingly
    /// @param token Address of LP token to withdraw
    /// @param amount Amount of LP token to withdraw
    function _withdraw(address token, uint256 amount) internal {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Initiate the recipients and amounts arrays
        address[] memory recipients;
        uint256[] memory optimizedAmounts;

        // Call the Optimizor contract
        if (address(optimizor) != address(0)) {
            (recipients, optimizedAmounts) = optimizor.optimizeWithdraw(token, gauge, amount);
        } else {
            // Shortcut if no Optimizor contract, withdraw all from Stake DAO
            _withdrawFromLiquidLocker(token, gauge, amount);

            // No need to go futher on the function
            return;
        }

        // Cache length
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

    /// @notice Internal gateway to withdraw LP token from Stake DAO Liquid Locker
    /// @param token Address of LP token to withdraw
    /// @param gauge Address of Liqudity gauge corresponding to LP token
    /// @param amount Amount of LP token to withdraw
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

    /// @notice Main gateway to claim all reward obtained from this strategy
    /// @notice Claim both reward from Liquid Locker position and fallback positions
    /// @param token Address of LP token to claim reward from
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

    /// @notice Claim rewards from all fallbacks
    /// @param token Address of LP token to claim reward from
    function claimFallbacks(address token) public requiresAuth {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Get fallbacks addresses
        // If no optimizor setted, this will revert
        address[] memory fallbacks = optimizor.getFallbacks();

        // Cache the fallbacks length
        uint256 len = fallbacks.length;
        for (uint8 i = 0; i < len; ++i) {
            // Skip the locker fallback
            if (fallbacks[i] == address(LOCKER)) continue;

            // Do the claim
            (address[] memory rewardsTokens, uint256[] memory amounts) =
                BaseFallback(fallbacks[i]).claimRewards(token, msg.sender);

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

    /// @notice Claim 3crv from the curve fee Distributor and send it to the accumulator
    /// @param notify If true, notify the accumulator
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

    /// @notice Internal process to send fees from rewards
    /// @param gauge Address of Liqudity gauge corresponding to LP token
    /// @param rewardToken Address of reward token
    /// @param rewardsBalance Amount of reward token
    /// @return Amount of reward token remaining
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

    /// @notice Send `token` to the accumulator
    /// @dev Only callable by the governance
    /// @param token Address of token to send to the accumulator
    /// @param amount Amount of token to send to the accumulator
    function sendToAccumulator(address token, uint256 amount) external requiresAuth {
        ERC20(token).safeApprove(address(accumulator), amount);
        accumulator.depositToken(token, amount);
    }

    //////////////////////////////////////////////////////
    /// --- LOCKER MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Increase CRV amount locked
    /// @param value Amount of CRV to lock
    function increaseAmount(uint256 value) external requiresAuth {
        LOCKER.increaseAmount(value);
    }

    /// @notice Release all CRV locked
    function release() external requiresAuth {
        LOCKER.release();
    }

    /// @notice Set the governance address
    /// @param _governance Address of the new governance
    function setGovernance(address _governance) external requiresAuth {
        LOCKER.setGovernance(_governance);
    }

    /// @notice Set the strategy address
    /// @param _strategy Address of the new strategy
    function setStrategy(address _strategy) external requiresAuth {
        LOCKER.setStrategy(_strategy);
    }

    //////////////////////////////////////////////////////
    /// --- MIGRATION
    //////////////////////////////////////////////////////

    /// @notice Migrate LP token from the locker to the vault
    /// @dev Only callable by the governance
    /// @param token Address of LP token to migrate
    function migrateLP(address token) external requiresAuth {
        // Get gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Get the amount of LP token staked in the gauge by the locker
        uint256 amount = ERC20(gauge).balanceOf(address(LOCKER));

        // Locker withdraw all from the gauge
        (bool success,) = LOCKER.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));
        if (!success) revert WITHDRAW_FAILED();

        // Locker transfer the LP token to the vault
        (success,) = LOCKER.execute(token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount));
        if (!success) revert CALL_FAILED();
    }

    //////////////////////////////////////////////////////
    /// --- SETTERS
    //////////////////////////////////////////////////////

    /// @notice Toogle vault status
    /// @param vault Address of the vault to toggle
    function toggleVault(address vault) external requiresAuth {
        if (vault == address(0)) revert ADDRESS_NULL();
        vaults[vault] = !vaults[vault];
        emit VaultToggled(vault, vaults[vault]);
    }

    /// @notice Toggle claim all flag
    function toggleClaimAll() external requiresAuth {
        claimAll = !claimAll;
    }

    /// @notice Set gauge address for a LP token
    /// @param token Address of LP token corresponding to `gauge`
    /// @param gauge Address of liquidity gauge corresponding to `token`
    function setGauge(address token, address gauge) external requiresAuth {
        if (token == address(0)) revert ADDRESS_NULL();
        gauges[token] = gauge;
        emit GaugeSet(gauge, token);
    }

    /// @notice Set type for a Liquidity gauge
    /// @param gauge Address of Liquidity gauge
    /// @param gaugeType Type of Liquidity gauge
    function setLGtype(address gauge, uint256 gaugeType) external requiresAuth {
        if (gauge == address(0)) revert ADDRESS_NULL();
        lGaugeType[gauge] = gaugeType;
        emit GaugeTypeSet(gauge, gaugeType);
    }

    /// @notice Set rewardDistributor for a Liquidity gauge
    /// @param gauge Address of Liquidity gauge
    /// @param multiGauge Address of rewardDistributor
    function setMultiGauge(address gauge, address multiGauge) external requiresAuth {
        if (gauge == address(0) || multiGauge == address(0)) revert ADDRESS_NULL();
        rewardDistributors[gauge] = multiGauge;
        emit MultiGaugeSet(gauge, multiGauge);
    }

    /// @notice Set VeSDTFeeProxy new address
    /// @param newVeSDTProxy Address of new VeSDTFeeProxy
    function setVeSDTProxy(address newVeSDTProxy) external requiresAuth {
        if (newVeSDTProxy == address(0)) revert ADDRESS_NULL();
        veSDTFeeProxy = newVeSDTProxy;
        emit VeSDTProxySet(newVeSDTProxy);
    }

    /// @notice Set Accumulator new address
    /// @param newAccumulator Address of new Accumulator
    function setAccumulator(address newAccumulator) external requiresAuth {
        if (newAccumulator == address(0)) revert ADDRESS_NULL();
        accumulator = IAccumulator(newAccumulator);
        emit AccumulatorSet(newAccumulator);
    }

    /// @notice Set RewardsReceiver new address
    /// @param newRewardsReceiver Address of new RewardsReceiver
    function setRewardsReceiver(address newRewardsReceiver) external requiresAuth {
        if (newRewardsReceiver == address(0)) revert ADDRESS_NULL();
        rewardsReceiver = newRewardsReceiver;
        emit RewardsReceiverSet(newRewardsReceiver);
    }

    /// @notice Set Optimizor new address
    /// @param newOptimizor Address of new Optimizor
    function setOptimizor(address newOptimizor) external requiresAuth {
        // Optimizor can be set to address(0) to disable it
        optimizor = Optimizor(newOptimizor);
        emit OptimizorSet(newOptimizor);
    }

    /// @notice Set SdtDistributor new address
    /// @param newSdtDistributor Address of new SdtDistributor
    function setSdtDistributor(address newSdtDistributor) external requiresAuth {
        if (newSdtDistributor == address(0)) revert ADDRESS_NULL();
        sdtDistributor = newSdtDistributor;
    }

    /// @notice Set fees for a Liquidity gauge
    /// @param manageFee_ Enum for the fee to set
    /// @param gauge Address of Liquidity gauge
    /// @param newFee New fee to set
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

    /// @notice Execute a function
    /// @dev Only callable by the owner
    /// @param to Address of the contract to execute
    /// @param value Value to send to the contract
    /// @param data Data to send to the contract
    /// @return success_ Boolean indicating if the execution was successful
    /// @return result_ Bytes containing the result of the execution
    function execute(address to, uint256 value, bytes calldata data)
        external
        requiresAuth
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }

    //////////////////////////////////////////////////////
    /// --- VIEW
    //////////////////////////////////////////////////////

    /// @notice Get the fees and receiver for a Liquidity gauge
    /// @param gauge Address of Liquidity gauge
    /// @return fees_ Struct containing the fees
    /// @return rewardsReceiver_ Address of the rewards receiver
    /// @return veSDTFeeProxy_ Address of the VeSDTFeeProxy
    function getFeesAndReceiver(address gauge) public view returns (Fees memory, address, address, address) {
        return (feesInfos[gauge], address(accumulator), rewardsReceiver, veSDTFeeProxy);
    }
}
