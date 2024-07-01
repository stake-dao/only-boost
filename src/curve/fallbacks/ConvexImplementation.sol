// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Clone} from "solady/utils/Clone.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {IBooster} from "src/base/interfaces/IBooster.sol";
import {IConvexFactory} from "src/base/interfaces/IConvexFactory.sol";
import {IBaseRewardPool} from "src/base/interfaces/IBaseRewardPool.sol";
import {IStashTokenWrapper} from "src/base/interfaces/IStashTokenWrapper.sol";

/// @notice Implementation per PID for Convex.
/// @dev For each PID, a minimal proxy is deployed using this contract as implementation.
contract ConvexImplementation is Clone {
    using FixedPointMathLib for uint256;

    /// @notice Denominator for percentage calculation
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Error emitted when contract is not initialized
    error FACTORY();

    /// @notice Error emitted when caller is not strategy
    error STRATEGY();

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the Minimal Proxy Factory.
    /// @dev The protocol fee value is stored in the factory in order to easily update it for all the pools.
    function factory() public pure returns (IConvexFactory _factory) {
        return IConvexFactory(_getArgAddress(0));
    }

    /// @notice Staking token address.
    function token() public pure returns (address _token) {
        return _getArgAddress(20);
    }

    /// @notice Reward token address.
    function rewardToken() public pure returns (address _rewardToken) {
        return _getArgAddress(40);
    }

    /// @notice Convex Reward Token address.
    function fallbackRewardToken() public pure returns (address _fallbackRewardToken) {
        return _getArgAddress(60);
    }

    /// @notice Strategy address.
    function strategy() public pure returns (address _strategy) {
        return _getArgAddress(80);
    }

    /// @notice Convex Entry point contract.
    function booster() public pure returns (IBooster _booster) {
        return IBooster(_getArgAddress(100));
    }

    /// @notice Staking Convex LP contract address.
    function baseRewardPool() public pure returns (IBaseRewardPool _baseRewardPool) {
        return IBaseRewardPool(_getArgAddress(120));
    }

    /// @notice Identifier of the pool on Convex.
    function pid() public pure returns (uint256 _pid) {
        return _getArgUint256(140);
    }

    //////////////////////////////////////////////////////
    /// --- MODIFIERS & INITIALIZATION
    //////////////////////////////////////////////////////

    modifier onlyStrategy() {
        if (msg.sender != strategy()) revert STRATEGY();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != address(factory())) revert FACTORY();
        _;
    }

    /// @notice Initialize the contract by approving the ConvexCurve booster to spend the LP token.
    function initialize() external onlyFactory {
        SafeTransferLib.safeApproveWithRetry(token(), address(booster()), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT/WITHDRAW/CLAIM
    //////////////////////////////////////////////////////

    /// @notice Deposit LP token into Convex.
    /// @param amount Amount of LP token to deposit.
    /// @dev The reason there's an empty address parameter is to keep flexibility for future implementations.
    /// Not all fallbacks will be minimal proxies, so we need to keep the same function signature.
    /// Only callable by the strategy.
    function deposit(address, uint256 amount) external onlyStrategy {
        /// Deposit the LP token into Convex and stake it (true) to receive rewards.
        booster().deposit(pid(), amount, true);
    }

    /// @notice Withdraw LP token from Convex.
    /// @param amount Amount of LP token to withdraw.
    /// Only callable by the strategy.
    function withdraw(address, uint256 amount) external onlyStrategy {
        /// Withdraw from Convex gauge without claiming rewards (false).
        baseRewardPool().withdrawAndUnwrap(amount, false);

        /// Send the LP token to the strategy.
        SafeTransferLib.safeTransfer(token(), msg.sender, amount);
    }

    /// @notice Claim rewards from Convex.
    /// @param _claimExtraRewards If true, claim extra rewards.
    /// @return rewardTokenAmount Amount of reward token claimed.
    /// @return fallbackRewardTokenAmount Amount of fallback reward token claimed.
    /// @return protocolFees Amount of protocol fees charged.
    /// @dev These amounts are used by the strategy to keep track of the rewards, and fees.
    function claim(bool _claimExtraRewards, bool _earmarkRewards, address _receiver)
        external
        onlyStrategy
        returns (uint256 rewardTokenAmount, uint256 fallbackRewardTokenAmount, uint256 protocolFees)
    {
        address[] memory extraRewardTokens;

        /// Earmark rewards if needed.
        if (_earmarkRewards) {
            booster().earmarkRewards(pid());
        }

        /// We can save gas by not claiming extra rewards if we don't need them, there's no extra rewards, or not enough rewards worth to claim.
        if (_claimExtraRewards) {
            extraRewardTokens = getRewardTokens();
        }

        /// Claim rewardToken, fallbackRewardToken and _extraRewardTokens if _claimExtraRewards is true.
        baseRewardPool().getReward(address(this), _claimExtraRewards);

        rewardTokenAmount = ERC20(rewardToken()).balanceOf(address(this));
        fallbackRewardTokenAmount = ERC20(fallbackRewardToken()).balanceOf(address(this));

        /// Charge Fees.
        protocolFees = _chargeProtocolFees(rewardTokenAmount);

        /// Send the reward token to the strategy.
        SafeTransferLib.safeTransfer(rewardToken(), msg.sender, rewardTokenAmount);
        /// Send the fallback reward token to the _receiver.
        SafeTransferLib.safeTransfer(fallbackRewardToken(), _receiver, fallbackRewardTokenAmount);

        /// Handle the extra reward tokens.
        for (uint256 i = 0; i < extraRewardTokens.length;) {
            uint256 _balance = ERC20(extraRewardTokens[i]).balanceOf(address(this));
            if (_balance > 0) {
                /// Send the whole balance to the strategy.
                SafeTransferLib.safeTransfer(extraRewardTokens[i], _receiver, _balance);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the reward tokens from the base reward pool.
    /// @return Array of all extra reward tokens.
    function getRewardTokens() public view returns (address[] memory) {
        // Check if there is extra rewards
        uint256 extraRewardsLength = baseRewardPool().extraRewardsLength();

        address[] memory tokens = new address[](extraRewardsLength);

        address _token;
        for (uint256 i; i < extraRewardsLength;) {
            /// Get the address of the virtual balance pool.
            _token = baseRewardPool().extraRewards(i);

            /// For PIDs greater than 150, the virtual balance pool also has a wrapper.
            /// So we need to get the token from the wrapper.
            /// More: https://docs.convexfinance.com/convexfinanceintegration/baserewardpool
            if (pid() >= 151) {
                address wrapper = IBaseRewardPool(_token).rewardToken();
                tokens[i] = IStashTokenWrapper(wrapper).token();
            } else {
                tokens[i] = IBaseRewardPool(_token).rewardToken();
            }

            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    function _chargeProtocolFees(uint256 _amount) internal view returns (uint256 _feeAccrued) {
        if (_amount == 0) return 0;

        uint256 protocolFeesPercent = factory().protocolFeesPercent();
        if (protocolFeesPercent == 0) return 0;

        _feeAccrued = _amount.mulDiv(protocolFeesPercent, DENOMINATOR);
    }

    /// @notice Get the balance of the LP token on Convex held by this contract.
    function balanceOf(address) public view returns (uint256) {
        return baseRewardPool().balanceOf(address(this));
    }
}
