// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {IAccumulator} from "src/interfaces/IAccumulator.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ISdtDistributorV2} from "src/interfaces/ISdtDistributorV2.sol";

contract CurveStrategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct Fees {
        uint256 perfFee;
        uint256 accumulatorFee;
        uint256 veSDTFee;
        uint256 claimerRewardFee;
    }

    //////////////////////////////// Constants ////////////////////////////////
    ILocker public constant LOCKER_STAKEDAO = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker
    IAccumulator public constant accumulator = IAccumulator(0xa44bFD194Fd7185ebecEcE4F7fA87a47DaA01c6A); // Stake DAO CRV Accumulator
    address public constant CRV_MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
    address public constant CRV_FEE_D = 0xA464e6DCda8AC41e03616F95f4BC98a13b8922Dc;
    address public constant CRV3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    uint256 public constant BASE_FEE = 10000; // 100% fees

    //////////////////////////////// Contracts ////////////////////////////////
    Optimizor public optimizor; // Optimizor contract

    //////////////////////////////// Variables ////////////////////////////////
    address public rewardsReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public sdtDistributor = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;
    address public veSDTFeeProxy = 0x9592Ec0605CE232A4ce873C650d2Aa01c79cb69E;

    //////////////////////////////// Mappings /////////////////////////////////
    mapping(address => address) public gauges; // lp token from curve -> curve gauge

    // Following mappings need to be initialized on the deployment to match with the previous contract
    mapping(address => Fees) public feesInfos; // gauge -> fees
    mapping(address => address) public multiGauges;
    mapping(address => uint256) public lGaugeType;

    //////////////////////////////// Errors ////////////////////////////////
    error AMOUNT_NULL();
    error ADDRESS_NULL();
    error CLAIM_FAILED();
    error MINT_FAILED();
    error CALL_FAILED();

    constructor() {
        optimizor = new Optimizor();
    }

    //////////////////////////////// Deposit ////////////////////////////////
    function deposit(address token, uint256 amount) external {
        // Transfer the token to this contract
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Do the deposit process
        _deposit(token, amount);
    }

    function depositForOptimizor(address token, uint256 amount) external {
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
            if (recipients[i] == address(LOCKER_STAKEDAO)) {
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
        ERC20(token).safeTransfer(address(LOCKER_STAKEDAO), amount);

        // Approve LOCKER_STAKEDAO to spend token
        LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
        LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, amount));

        // Locker deposit token
        (bool success,) = LOCKER_STAKEDAO.execute(gauge, 0, abi.encodeWithSignature("deposit(uint256)", amount));
        require(success, "Deposit failed!");
    }

    //////////////////////////////// Withdraw ////////////////////////////////
    function withdraw(address token, uint256 amount) external {
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
            if (recipients[i] == address(LOCKER_STAKEDAO)) {
                _withdrawFromLiquidLocker(token, gauge, optimizedAmounts[i]);
            }
            // Deposit into other fallback
            else {
                BaseFallback(recipients[i]).withdraw(token, optimizedAmounts[i]);
            }
        }
    }

    function _withdrawFromLiquidLocker(address token, address gauge, uint256 amount) internal {
        uint256 _before = ERC20(token).balanceOf(address(LOCKER_STAKEDAO));

        (bool success,) = LOCKER_STAKEDAO.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));
        require(success, "Transfer failed!");
        uint256 _after = ERC20(token).balanceOf(address(LOCKER_STAKEDAO));

        uint256 _net = _after - _before;
        (success,) =
            LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), _net));
        require(success, "Transfer failed!");
    }

    //////////////////////////////// Claim ////////////////////////////////
    function claim(address token) external {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Get the CRV amount before claim
        uint256 crvBeforeClaim = ERC20(CRV).balanceOf(address(LOCKER_STAKEDAO));

        // Claim CRV, within the mint() it calls the user checkpoint
        (bool success,) = LOCKER_STAKEDAO.execute(CRV_MINTER, 0, abi.encodeWithSignature("mint(address)", gauge));
        if (!success) revert MINT_FAILED();

        // Get the CRV amount claimed
        uint256 crvMinted = ERC20(CRV).balanceOf(address(LOCKER_STAKEDAO)) - crvBeforeClaim;

        // Send CRV here
        (success,) = LOCKER_STAKEDAO.execute(
            CRV, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), crvMinted)
        );
        if (!success) revert CALL_FAILED();

        // Distribute CRV to fees recipients and gauges
        uint256 crvNetRewards = sendFee(gauge, CRV, crvMinted);
        ERC20(CRV).approve(multiGauges[gauge], crvNetRewards);
        ILiquidityGauge(multiGauges[gauge]).deposit_reward_token(CRV, crvNetRewards);
        //emit Claimed(gauge, CRV, crvMinted);

        // Distribute SDT to the related gauge
        ISdtDistributorV2(sdtDistributor).distribute(multiGauges[gauge]);

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
                rewardsBalanceBeforeLocker[i] = ERC20(rewardToken_).balanceOf(address(LOCKER_STAKEDAO));
            }

            // Do the claim
            (success,) = LOCKER_STAKEDAO.execute(
                gauge,
                0,
                abi.encodeWithSignature("claim_rewards(address,address)", address(LOCKER_STAKEDAO), address(this))
            );

            // Claim on behalf of locker if previous call failed
            if (!success) ILiquidityGauge(gauge).claim_rewards(address(LOCKER_STAKEDAO));

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
                    rewardsBalance =
                        ERC20(rewardToken).balanceOf(address(LOCKER_STAKEDAO)) - rewardsBalanceBeforeLocker[i];

                    // Transfer the freshly rewards from the locker to here
                    (success,) = LOCKER_STAKEDAO.execute(
                        rewardToken,
                        0,
                        abi.encodeWithSignature("transfer(address,uint256)", address(this), rewardsBalance)
                    );
                    if (!success) revert CALL_FAILED();
                }
                ERC20(rewardToken).approve(multiGauges[gauge], rewardsBalance);
                ILiquidityGauge(multiGauges[gauge]).deposit_reward_token(rewardToken, rewardsBalance);
                //emit Claimed(gauge, rewardToken, rewardsBalance);
            }
        }
    }

    function claim3Crv(bool notify) external {
        // Claim 3crv from the curve fee Distributor, it will send 3crv to the crv locker
        (bool success,) = LOCKER_STAKEDAO.execute(CRV_FEE_D, 0, abi.encodeWithSignature("claim()"));
        if (!success) revert CLAIM_FAILED();

        // Cache amount to send to accumulator
        uint256 amountToSend = ERC20(CRV3).balanceOf(address(LOCKER_STAKEDAO));
        if (amountToSend == 0) revert AMOUNT_NULL();

        // Send 3crv from the LOCKER_STAKEDAO to the accumulator
        (success,) = LOCKER_STAKEDAO.execute(
            CRV3, 0, abi.encodeWithSignature("transfer(address,uint256)", address(accumulator), amountToSend)
        );
        if (!success) revert CALL_FAILED();

        if (notify) {
            accumulator.notifyAll();
        }
        //emit Crv3Claimed(amountToSend, notify);
    }

    function sendFee(address gauge, address rewardToken, uint256 rewardsBalance) internal returns (uint256) {
        Fees memory fee = feesInfos[gauge];
        // calculate the amount for each fee recipient
        uint256 multisigFee = rewardsBalance.mulDivDown(fee.perfFee, BASE_FEE);
        uint256 accumulatorPart = rewardsBalance.mulDivDown(fee.accumulatorFee, BASE_FEE);
        uint256 veSDTPart = rewardsBalance.mulDivDown(fee.veSDTFee, BASE_FEE);
        uint256 claimerPart = rewardsBalance.mulDivDown(fee.claimerRewardFee, BASE_FEE);
        // send
        ERC20(rewardToken).approve(address(accumulator), accumulatorPart);
        accumulator.depositToken(rewardToken, accumulatorPart);
        ERC20(rewardToken).transfer(rewardsReceiver, multisigFee);
        ERC20(rewardToken).transfer(veSDTFeeProxy, veSDTPart);
        ERC20(rewardToken).transfer(msg.sender, claimerPart);
        return rewardsBalance - multisigFee - accumulatorPart - veSDTPart - claimerPart;
    }

    //////////////////////////////// Setters ////////////////////////////////
    function setGauge(address token, address gauge) external {
        gauges[token] = gauge;
    }

    //////////////////////////////// Execute ////////////////////////////////
    function execute(address to, uint256 value, bytes calldata data) external returns (bool, bytes memory) {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }
}