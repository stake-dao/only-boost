// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "src/CRV_Strategy.sol";
import "solady/utils/LibClone.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {ISDLiquidityGauge} from "src/interfaces/ISDLiquidityGauge.sol";
import {SafeTransferLib as SafeTransfer} from "solady/utils/SafeTransferLib.sol";

abstract contract Strategy_Test is Test {
    using FixedPointMathLib for uint256;

    ILocker public locker;

    CRV_Strategy public strategy;
    CRV_Strategy public stratImplementation;

    //////////////////////////////////////////////////////
    /// --- CONVEX ADDRESSES
    //////////////////////////////////////////////////////

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    //////////////////////////////////////////////////////
    /// --- VOTER PROXY ADDRESSES
    //////////////////////////////////////////////////////

    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address public constant CONVEX_VOTER_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    //////////////////////////////////////////////////////
    /// --- CURVE ADDRESSES
    //////////////////////////////////////////////////////

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    uint256 public pid;
    ERC20 public token;
    address public gauge;
    address public rewardDistributor;

    address[] public extraRewardTokens;

    constructor(uint256 _pid, address _rewardDistributor) {
        /// Check if the LP token is valid
        (address lpToken,, address _gauge,,,) = IBooster(BOOSTER).poolInfo(_pid);

        pid = _pid;
        gauge = _gauge;
        token = ERC20(lpToken);
        rewardDistributor = _rewardDistributor;
    }

    function setUp() public {
        vm.rollFork({blockNumber: 18_383_019});

        /// Initialize Locker
        locker = ILocker(SD_VOTER_PROXY);

        stratImplementation = new CRV_Strategy(
            address(this),
            SD_VOTER_PROXY,
            VE_CRV,
            REWARD_TOKEN,
            MINTER
        );

        address _proxy = LibClone.deployERC1967(address(stratImplementation));
        strategy = CRV_Strategy(payable(_proxy));
        strategy.initialize(address(this));

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        /// Act as a vault.
        strategy.toggleVault(address(this));

        token.approve(address(strategy), type(uint256).max);

        /// Initialize token config.
        strategy.setGauge(address(token), address(gauge));
        strategy.setRewardDistributor(address(gauge), address(rewardDistributor));

        address _admin = ILiquidityGauge(address(rewardDistributor)).admin();

        vm.prank(_admin);
        /// Transfer Ownership of the gauge to the strategy.
        ILiquidityGauge(address(rewardDistributor)).commit_transfer_ownership(address(strategy));

        /// Accept ownership of the gauge.
        strategy.acceptRewardDistributorOwnership(address(rewardDistributor));

        /// Update the rewardToken distributor to the strategy.
        strategy.execute(
            address(rewardDistributor),
            0,
            abi.encodeWithSignature("set_reward_distributor(address,address)", REWARD_TOKEN, address(strategy))
        );

        /// Add the extra reward token.
        _addExtraRewards();

        /// We need to overwrite the locker balance.
        deal(address(gauge), address(locker), 0);
    }

    function test_deposit(uint128 _amount) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);

        deal(address(token), address(this), amount);

        assertEq(ILiquidityGauge(gauge).balanceOf(SD_VOTER_PROXY), 0);

        strategy.deposit(address(token), amount);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(SD_VOTER_PROXY)), 0);

        assertEq(strategy.balanceOf(address(token)), amount);
        assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), amount);
    }

    function test_withdraw(uint128 _amount, uint128 _toWithdraw) public {
        uint256 amount = uint256(_amount);
        uint256 toWithdraw = uint256(_toWithdraw);

        vm.assume(amount != 0);
        vm.assume(toWithdraw != 0);
        vm.assume(amount >= toWithdraw);

        deal(address(token), address(this), amount);

        strategy.deposit(address(token), amount);
        strategy.withdraw(address(token), toWithdraw);

        assertEq(token.balanceOf(address(this)), toWithdraw);
        assertEq(token.balanceOf(address(SD_VOTER_PROXY)), 0);
        assertEq(ILiquidityGauge(gauge).balanceOf(address(SD_VOTER_PROXY)), amount - toWithdraw);
    }

    function test_harvest(
        uint128 _amount,
        uint256 _weeksToSkip,
        bool _distributeSDT,
        bool _claimExtraRewards,
        bool _setFees
    ) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);
        vm.assume(_weeksToSkip < 10);

        deal(address(token), address(this), amount);
        strategy.deposit(address(token), amount);

        if (_setFees) {
            strategy.updateProtocolFee(1_700); // 17%
            strategy.updateClaimIncentiveFee(100); // 1%
            /// Total: 18%
        }

        /// Then skip weeks to harvest SD.
        skip(_weeksToSkip * 1 weeks);

        uint256 _expectedLockerRewardTokenAmount = _getSdRewardTokenMinted();

        uint256 _totalRewardTokenAmount = _expectedLockerRewardTokenAmount;

        uint256[] memory _extraRewardsEarned = new uint256[](extraRewardTokens.length);
        uint256[] memory _SDExtraRewardsEarned = new uint256[](extraRewardTokens.length);

        if (_claimExtraRewards && extraRewardTokens.length > 0) {
            _SDExtraRewardsEarned = _getSDExtraRewardsEarned();
        }

        vm.prank(address(0xBEEC));
        strategy.harvest(address(token), _distributeSDT, _claimExtraRewards);

        uint256 _balanceRewardToken = ERC20(REWARD_TOKEN).balanceOf(address(rewardDistributor));

        if (_setFees) {
            _checkCorrectFeeCompute(_expectedLockerRewardTokenAmount, _totalRewardTokenAmount, _balanceRewardToken);
        } else {
            assertEq(strategy.feesAccrued(), 0);

            assertEq(_balanceOf(REWARD_TOKEN, address(this)), 0);
            assertEq(_balanceOf(REWARD_TOKEN, address(0xBEEC)), 0);
            assertEq(_balanceOf(REWARD_TOKEN, address(strategy)), 0);

            assertEq(_balanceRewardToken, _totalRewardTokenAmount);
        }

        if (_claimExtraRewards) {
            _checkExtraRewardsDistribution(_extraRewardsEarned, _SDExtraRewardsEarned);
        }
    }

    function test_fee_computation(uint128 _amount, uint256 _weeksToSkip) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);
        vm.assume(_weeksToSkip != 0);
        vm.assume(_weeksToSkip < 10);

        // Deposit
        deal(address(token), address(this), amount);
        strategy.deposit(address(token), amount);

        // Set Fees
        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        uint256 claimerFee;
        uint256 totalRewardTokenAmount;
        uint256 totalProtocolFeesAccrued;

        // Harvest and Check Fees Twice
        for (uint256 i = 0; i < 2; i++) {
            // Skip weeks for the harvest
            skip(_weeksToSkip * 1 weeks);

            // Calculate and check fees
            uint256 expectedLockerRewardTokenAmount = _getSdRewardTokenMinted();

            vm.prank(address(0xBEEC));
            strategy.harvest(address(token), false, true);

            (totalProtocolFeesAccrued, claimerFee, totalRewardTokenAmount) = _checkFees(
                totalRewardTokenAmount, totalProtocolFeesAccrued, claimerFee, expectedLockerRewardTokenAmount
            );
        }
    }

    function _checkCorrectFeeCompute(
        uint256 _expectedLockerRewardTokenAmount,
        uint256 _totalRewardTokenAmount,
        uint256 _balanceRewardToken
    ) internal {
        uint256 _claimerFee;
        uint256 _protocolFee;

        /// Compute the fees.
        _protocolFee = _expectedLockerRewardTokenAmount.mulDiv(17, 100);
        _totalRewardTokenAmount -= _protocolFee;

        _claimerFee = _totalRewardTokenAmount.mulDiv(1, 100);
        _totalRewardTokenAmount -= _claimerFee;

        assertEq(_balanceOf(REWARD_TOKEN, address(0xBEEC)), _claimerFee);

        assertEq(strategy.feesAccrued(), _protocolFee);
        assertEq(_balanceOf(REWARD_TOKEN, address(strategy)), _protocolFee);

        assertEq(_balanceRewardToken, _totalRewardTokenAmount);
    }

    function _checkExtraRewardsDistribution(
        uint256[] memory _extraRewardsEarned,
        uint256[] memory _SDExtraRewardsEarned
    ) internal {
        /// Loop through the extra reward tokens.
        for (uint256 i = 0; i < extraRewardTokens.length; i++) {
            assertEq(_balanceOf(extraRewardTokens[i], address(this)), 0);
            assertEq(_balanceOf(extraRewardTokens[i], address(strategy)), 0);

            /// Only if there's reward flowing, we assert that there's some balance.
            if (_extraRewardsEarned[i] > 0) {
                uint256 _balanceRewardToken = ERC20(extraRewardTokens[i]).balanceOf(address(rewardDistributor));

                if (extraRewardTokens[i] == REWARD_TOKEN) continue;
                assertEq(_balanceRewardToken, _SDExtraRewardsEarned[i]);
            }
        }
    }

    function _checkFees(
        uint256 totalRewardTokenAmount,
        uint256 totalProtocolFeesAccrued,
        uint256 claimerFee,
        uint256 _expectedLockerRewardTokenAmount
    ) internal virtual returns (uint256, uint256, uint256) {
        uint256 protocolFeeForThisHarvest = _expectedLockerRewardTokenAmount.mulDiv(17, 100);

        totalProtocolFeesAccrued += protocolFeeForThisHarvest;
        uint256 _totalRewardTokenAmount = _expectedLockerRewardTokenAmount - protocolFeeForThisHarvest;

        uint256 _claimerFee = _totalRewardTokenAmount.mulDiv(1, 100);
        claimerFee += _claimerFee;

        _totalRewardTokenAmount -= _claimerFee;

        totalRewardTokenAmount += _totalRewardTokenAmount;

        assertEq(strategy.feesAccrued(), totalProtocolFeesAccrued);
        assertEq(_balanceOf(REWARD_TOKEN, address(0xBEEC)), claimerFee);
        assertEq(_balanceOf(REWARD_TOKEN, address(strategy)), totalProtocolFeesAccrued);
        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(rewardDistributor)), totalRewardTokenAmount);

        return (totalProtocolFeesAccrued, claimerFee, totalRewardTokenAmount);
    }

    function _getSdRewardTokenMinted() internal returns (uint256 _rewardTokenAmount) {
        uint256 id = vm.snapshot();
        /// Snapshot before claim.
        uint256 _snapshotBalance = ERC20(REWARD_TOKEN).balanceOf(address(locker));

        /// Claim.
        address _minter = strategy.minter();

        vm.prank(locker.governance());
        locker.execute(_minter, 0, abi.encodeWithSignature("mint(address)", gauge));

        /// Snapshot after claim.
        _rewardTokenAmount = ERC20(REWARD_TOKEN).balanceOf(address(locker)) - _snapshotBalance;

        vm.revertTo(id);
    }

    function _getSDExtraRewardsEarned() internal returns (uint256[] memory _sdExtraRewardsEarned) {
        /// We need to snapshot the state of the strategy.
        /// Because there's no way to get the extra rewards earned from the strategy directly without claiming them.
        uint256 id = vm.snapshot();
        _sdExtraRewardsEarned = new uint256[](extraRewardTokens.length);

        uint256[] memory _snapshotBalances = new uint[](extraRewardTokens.length);
        for (uint256 i = 0; i < extraRewardTokens.length; i++) {
            _snapshotBalances[i] = ERC20(extraRewardTokens[i]).balanceOf(address(locker));
        }

        ILiquidityGauge(gauge).claim_rewards(address(locker));

        for (uint256 i = 0; i < extraRewardTokens.length; i++) {
            _sdExtraRewardsEarned[i] = ERC20(extraRewardTokens[i]).balanceOf(address(locker)) - _snapshotBalances[i];
        }

        vm.revertTo(id);
    }

    function _addExtraRewards() internal virtual {
        // view function called only to recognize the gauge type

        /// Reset Balance of the rewardDistributor for each reward token.
        deal(REWARD_TOKEN, address(rewardDistributor), 0);

        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);
        (bool success,) = gauge.call(data);
        if (!success) {
            /// Means that the gauge doesn't support extra rewards.
            strategy.setLGtype(gauge, 1);

            return;
        }

        for (uint8 i = 0; i < 8; i++) {
            // Get reward token
            address _extraRewardToken = ISDLiquidityGauge(gauge).reward_tokens(i);
            if (_extraRewardToken == address(0)) break;
            if (_extraRewardToken == REWARD_TOKEN) continue;

            extraRewardTokens.push(_extraRewardToken);

            // If not already added in the rewardDistributor.
            address distributor = ILiquidityGauge(rewardDistributor).reward_data(_extraRewardToken).distributor;
            if (distributor == address(0)) {
                strategy.addRewardToken(gauge, _extraRewardToken);
            } else if (distributor != address(strategy)) {
                /// Update the rewardToken distributor to the strategy.
                strategy.execute(
                    address(rewardDistributor),
                    0,
                    abi.encodeWithSignature(
                        "set_reward_distributor(address,address)", _extraRewardToken, address(strategy)
                    )
                );

                /// Approve the strategy to spend the extra reward token.
                strategy.execute(
                    address(_extraRewardToken),
                    0,
                    abi.encodeWithSignature("approve(address,uint256)", address(rewardDistributor), 0)
                );
                strategy.execute(
                    address(_extraRewardToken),
                    0,
                    abi.encodeWithSignature("approve(address,uint256)", address(rewardDistributor), type(uint256).max)
                );
            }

            /// Reset Balance of the rewardDistributor for each reward token.
            /// We use transfer because deal doesn't support tokens that perform compute on balanceOf.
            uint256 _balance = ERC20(_extraRewardToken).balanceOf(address(rewardDistributor));

            vm.prank(address(rewardDistributor));
            ERC20(_extraRewardToken).transfer(address(0xCACA), _balance);
        }
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return ERC20(_token).balanceOf(account);
    }
}
