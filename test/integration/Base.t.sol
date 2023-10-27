// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {IConvexToken} from "test/interfaces/IConvexToken.sol";
import {ICVXLocker, Optimizer} from "src/optimizer/Optimizer.sol";

import {SafeTransferLib as SafeTransfer} from "solady/utils/SafeTransferLib.sol";
import {IBaseRewardPool, ConvexImplementation} from "src/fallbacks/ConvexImplementation.sol";
import {IBooster, ConvexMinimalProxyFactory} from "src/fallbacks/ConvexMinimalProxyFactory.sol";

abstract contract Base_Test is Test {
    using SafeTransfer for ERC20;
    using FixedPointMathLib for uint256;

    ILocker public locker;
    Optimizer public optimizer;

    CRVStrategy public strategy;
    CRVStrategy public stratImplementation;

    ConvexMinimalProxyFactory public factory;

    /// @notice Implementation contract to clone.
    ConvexImplementation public implementation;

    /// @notice Convex Depositor.
    ConvexImplementation public proxy;

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

    function setUp() public virtual {
        vm.rollFork({blockNumber: 18_383_019});

        /// Initialize Locker
        locker = ILocker(SD_VOTER_PROXY);

        stratImplementation = new CRVStrategy(
            address(this),
            SD_VOTER_PROXY,
            VE_CRV,
            REWARD_TOKEN,
            MINTER
        );

        address _proxy = LibClone.deployERC1967(address(stratImplementation));
        strategy = CRVStrategy(payable(_proxy));
        strategy.initialize(address(this));

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        implementation = new ConvexImplementation();
        factory =
        new ConvexMinimalProxyFactory(BOOSTER, address(strategy), REWARD_TOKEN, FALLBACK_REWARD_TOKEN, address(implementation));

        optimizer = new Optimizer(address(strategy), address(factory));
        strategy.setOptimizer(address(optimizer));

        /// Act as a vault.
        strategy.toggleVault(address(this));

        proxy = ConvexImplementation(factory.create(address(token), pid));

        token.approve(address(strategy), type(uint256).max);

        /// Initialize token config.
        strategy.setGauge(address(token), address(gauge));
        strategy.setRewardDistributor(address(gauge), address(rewardDistributor));

        vm.prank(ILiquidityGauge(address(rewardDistributor)).admin());
        /// Transfer Ownership of the gauge to the strategy.
        ILiquidityGauge(address(rewardDistributor)).commit_transfer_ownership(address(strategy));

        /// Accept ownership of the gauge.
        strategy.execute(address(rewardDistributor), 0, abi.encodeWithSignature("accept_transfer_ownership()"));

        /// Add the extra reward token.
        _addExtraRewardToken();

        /// We need to overwrite the locker balance.
        deal(address(gauge), address(locker), 0);

        /// Label the contract.
        vm.label(address(locker), "locker");
        vm.label(address(strategy), "strategy");
        vm.label(address(proxy), "convex");
        vm.label(address(optimizer), "optimizer");
        vm.label(address(factory), "factory");
        vm.label(address(implementation), "implementation");
        vm.label(address(this), "owner");
    }

    function _addExtraRewardToken() internal {
        /// Reset Balance of the rewardDistributor for each reward token.
        deal(REWARD_TOKEN, address(rewardDistributor), 0);
        deal(FALLBACK_REWARD_TOKEN, address(rewardDistributor), 0);

        /// Add the reward token to the rewardDistributor.
        strategy.addRewardToken(gauge, FALLBACK_REWARD_TOKEN);

        /// Update the rewardToken distributor to the strategy.
        strategy.execute(
            address(rewardDistributor),
            0,
            abi.encodeWithSignature("set_reward_distributor(address,address)", REWARD_TOKEN, address(strategy))
        );

        extraRewardTokens = proxy.getRewardTokens();
        uint256 _extraRewardTokenLength = extraRewardTokens.length;

        if (_extraRewardTokenLength > 0) {
            if (_extraRewardTokenLength == 1) {
                address virtualPool = IBaseRewardPool(proxy.baseRewardPool()).extraRewards(0);

                /// There's a special case for the susd pool we don't want to compromise on.
                if (IBaseRewardPool(virtualPool).rewardRate() == 0 || pid == 4) {
                    strategy.setLGtype(gauge, 1);
                }
            }

            for (uint256 i; i < _extraRewardTokenLength; i++) {
                address _extraRewardToken = extraRewardTokens[i];

                // If not already added in the rewardDistributor.
                address distributor = ILiquidityGauge(rewardDistributor).reward_data(_extraRewardToken).distributor;
                if (distributor == address(0)) {
                    address virtualPool = IBaseRewardPool(proxy.baseRewardPool()).extraRewards(i);

                    if (IBaseRewardPool(virtualPool).rewardRate() > 0) {
                        strategy.addRewardToken(gauge, _extraRewardToken);
                    }
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
                        abi.encodeWithSignature(
                            "approve(address,uint256)", address(rewardDistributor), type(uint256).max
                        )
                    );
                }

                /// Reset Balance of the rewardDistributor for each reward token.
                /// We use transfer because deal doesn't support tokens that perform compute on balanceOf.
                uint256 _balance = ERC20(_extraRewardToken).balanceOf(address(rewardDistributor));

                vm.prank(address(rewardDistributor));
                ERC20(_extraRewardToken).transfer(address(0xCACA), _balance);
            }
        } else {
            strategy.setLGtype(gauge, 1);
        }
    }

    function _hasMaxBoost() internal returns (bool, uint256 optimalSD) {
        uint256 id = vm.snapshot();

        strategy.withdraw(address(token), strategy.balanceOf(address(token)));

        /// Check if Convex has maxboost.
        uint256 balance = ILiquidityGauge(gauge).balanceOf(CONVEX_VOTER_PROXY);
        uint256 workingBalance = ILiquidityGauge(gauge).working_balances(CONVEX_VOTER_PROXY);

        optimalSD = optimizer.computeOptimalDepositAmount(gauge);

        vm.revertTo(id);

        return (balance == workingBalance, optimalSD);
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

    function _getFallbackRewardMinted() internal view returns (uint256 _fallbackRewardAmount) {
        uint256 rewardTokenEarned = proxy.baseRewardPool().earned(address(proxy));

        IConvexToken _fallbackToken = IConvexToken(FALLBACK_REWARD_TOKEN);

        uint256 _supply = _fallbackToken.totalSupply();
        uint256 _maxSupply = _fallbackToken.maxSupply();
        uint256 _totalCliffs = _fallbackToken.totalCliffs();
        uint256 _reductionPerCliff = _fallbackToken.reductionPerCliff();

        //use current supply to gauge cliff
        //this will cause a bit of overflow into the next cliff range
        //but should be within reasonable levels.
        //requires a max supply check though
        uint256 cliff = _supply / _reductionPerCliff;
        //mint if below total cliffs
        if (cliff < _totalCliffs) {
            //for reduction% take inverse of current cliff
            uint256 reduction = _totalCliffs - cliff;
            //reduce
            _fallbackRewardAmount = rewardTokenEarned * reduction / _totalCliffs;

            uint256 amtTillMax = _maxSupply - _supply;
            if (_fallbackRewardAmount > amtTillMax) {
                _fallbackRewardAmount = amtTillMax;
            }
        }
    }

    function _checkFees(
        uint256 totalRewardTokenAmount,
        uint256 totalProtocolFeesAccrued,
        uint256 claimerFee,
        uint256 _expectedLockerRewardTokenAmount,
        uint256 _earned,
        bool _setFallbackFees
    ) internal returns (uint256, uint256, uint256) {
        uint256 protocolFeeForThisHarvest = _expectedLockerRewardTokenAmount.mulDiv(17, 100);

        if (_setFallbackFees && _earned > 0) {
            protocolFeeForThisHarvest += _earned.mulDiv(17, 100);
        }

        totalProtocolFeesAccrued += protocolFeeForThisHarvest;
        uint256 _totalRewardTokenAmount = _expectedLockerRewardTokenAmount + _earned - protocolFeeForThisHarvest;

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

    function _checkForDuplicatesExtraRewards(
        uint256 _totalRewardTokenAmount,
        uint256 _expectedFallbackRewardTokenAmount,
        uint256[] memory _SDExtraRewardsEarned
    ) internal view returns (uint256, uint256, uint256[] memory _extraRewardsEarned) {
        _extraRewardsEarned = new uint256[](extraRewardTokens.length);

        for (uint256 i = 0; i < extraRewardTokens.length; i++) {
            address virtualPool = proxy.baseRewardPool().extraRewards(i);
            _extraRewardsEarned[i] = IBaseRewardPool(virtualPool).earned(address(proxy));

            if (extraRewardTokens[i] == REWARD_TOKEN) {
                _totalRewardTokenAmount += _extraRewardsEarned[i] + _SDExtraRewardsEarned[i];
            }

            if (extraRewardTokens[i] == FALLBACK_REWARD_TOKEN) {
                _expectedFallbackRewardTokenAmount += _extraRewardsEarned[i] + _SDExtraRewardsEarned[i];
            }
        }

        return (_totalRewardTokenAmount, _expectedFallbackRewardTokenAmount, _extraRewardsEarned);
    }

    function _checkCorrectFeeCompute(
        bool _setFallbackFees,
        bool _claimFallbacks,
        uint256 _earned,
        uint256 _expectedLockerRewardTokenAmount,
        uint256 _totalRewardTokenAmount,
        uint256 _balanceRewardToken
    ) internal {
        uint256 _claimerFee;
        uint256 _protocolFee;

        /// Compute the fees.
        if (_setFallbackFees && _claimFallbacks) {
            _protocolFee = _expectedLockerRewardTokenAmount.mulDiv(17, 100);
            _protocolFee += _earned.mulDiv(17, 100);
        } else {
            _protocolFee = _expectedLockerRewardTokenAmount.mulDiv(17, 100);
        }
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
        uint256[] memory _SDExtraRewardsEarned,
        bool _claimFallbacks
    ) internal {
        /// Loop through the extra reward tokens.
        for (uint256 i = 0; i < extraRewardTokens.length; i++) {
            assertEq(_balanceOf(extraRewardTokens[i], address(this)), 0);
            assertEq(_balanceOf(extraRewardTokens[i], address(proxy)), 0);
            assertEq(_balanceOf(extraRewardTokens[i], address(strategy)), 0);

            /// Only if there's reward flowing, we assert that there's some balance.
            if (_extraRewardsEarned[i] > 0) {
                uint256 _balanceRewardToken = ERC20(extraRewardTokens[i]).balanceOf(address(rewardDistributor));

                if (extraRewardTokens[i] == REWARD_TOKEN) continue;
                if (extraRewardTokens[i] == FALLBACK_REWARD_TOKEN) continue;

                if (_claimFallbacks) {
                    assertEq(_balanceRewardToken, _extraRewardsEarned[i] + _SDExtraRewardsEarned[i]);
                } else {
                    assertEq(_balanceRewardToken, _SDExtraRewardsEarned[i]);
                }
            }
        }
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return ERC20(_token).balanceOf(account);
    }
}
