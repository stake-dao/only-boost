// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "solady/src/utils/LibClone.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import "src/YearnShutdownStrategy.sol";
import "src/interfaces/IVault.sol";

import {SafeTransferLib as SafeTransfer} from "solady/src/utils/SafeTransferLib.sol";

contract YearnShutdownTest is Test {
    using SafeTransfer for ERC20;

    YearnShutdownStrategy public strategy;

    /// @notice The ERC1967 implementation slot.
    bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Current strategy address.
    address public constant STRATEGY = 0x1be150a35bb8233d092747eBFDc75FB357c35168;

    /// @notice Vault V2 address.
    address public constant VAULT = address(0x4551285DF024dc71D7d1CdB95906B305f1922383);

    address public governance;

    function setUp() public virtual {
        vm.createSelectFork("mainnet");

        governance = YearnShutdownStrategy(payable(STRATEGY)).governance();

        address locker = address(YearnShutdownStrategy(payable(STRATEGY)).locker());
        address veToken = YearnShutdownStrategy(payable(STRATEGY)).veToken();
        address rewardToken = YearnShutdownStrategy(payable(STRATEGY)).rewardToken();
        address minter = YearnShutdownStrategy(payable(STRATEGY)).minter();

        /// 1. Deploy the strategy implementation.
        strategy = new YearnShutdownStrategy(governance, locker, veToken, rewardToken, minter);
    }

    function test_upgrade() public {
        /// 1. Expect the upgrade to revert.
        vm.expectRevert(Strategy.GOVERNANCE.selector);
        YearnShutdownStrategy(payable(STRATEGY)).upgradeToAndCall(address(strategy), "");

        /// 2. Expect the upgrade to revert for the new implementation.
        vm.expectRevert(UUPSUpgradeable.UnauthorizedCallContext.selector);
        strategy.upgradeToAndCall(address(1), "");

        /// 3. Upgrade the strategy.
        _upgrade(address(strategy));

        /// 4. Expect the upgrade to succeed.
        bytes32 v = vm.load(address(STRATEGY), _ERC1967_IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(v))), address(strategy));
    }

    function test_shutdown() public {
        /// Upgrade the strategy.
        _upgrade(address(strategy));

        /// V1 vault token.
        _shutdown(VAULT);
    }

    function _shutdown(address _vault) internal {
        /// V1 vault token.
        address asset = IVault(_vault).token();
        address liquidityGauge = IVault(_vault).liquidityGauge();
        address gauge = YearnShutdownStrategy(payable(STRATEGY)).gauges(asset);

        /// Deposit some assets.
        deal(asset, address(this), 1000e18);
        SafeTransfer.safeApprove(asset, _vault, type(uint256).max);
        IVault(_vault).deposit(address(this), 1000e18, true);

        assertEq(_balanceOf(asset, STRATEGY), 0);
        assertEq(_balanceOf(asset, _vault), 0);
        assertEq(_balanceOf(liquidityGauge, address(this)), 1000e18);

        uint256 balance = YearnShutdownStrategy(payable(STRATEGY)).balanceOf(asset);
        assertGt(balance, 1000e18);

        assertEq(YearnShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), false);

        address[] memory protectedGauges = new address[](1);
        protectedGauges[0] = gauge;

        vm.prank(governance);
        YearnShutdownStrategy(payable(STRATEGY)).setProtectedGauges(protectedGauges);

        YearnShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false);

        assertEq(YearnShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), false);
        assertEq(_balanceOf(asset, _vault), 0);

        skip(1 days);

        vm.prank(governance);
        YearnShutdownStrategy(payable(STRATEGY)).unsetProtectedGauges(protectedGauges);

        YearnShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false);

        assertEq(YearnShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), true);

        assertEq(_balanceOf(asset, STRATEGY), 0);
        assertEq(_balanceOf(asset, _vault), balance);

        /// Make sure you can't harvest again.
        vm.expectRevert(YearnShutdownStrategy.SHUTDOWN.selector);
        YearnShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false);

        /// Make sure you can't call regular harvest.
        vm.expectRevert(YearnShutdownStrategy.SHUTDOWN.selector);
        YearnShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false);

        /// Make sure you can withdraw.
        IVault(_vault).withdraw(1000e18);

        assertEq(_balanceOf(asset, address(this)), 1000e18);
        assertEq(_balanceOf(liquidityGauge, address(this)), 0);

        /// Make sure you can't deposit again.
        vm.expectRevert(YearnShutdownStrategy.SHUTDOWN.selector);
        IVault(_vault).deposit(address(this), 1000e18, true);
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return ERC20(_token).balanceOf(account);
    }

    function _upgrade(address _newImplementation) internal {
        vm.prank(governance);
        YearnShutdownStrategy(payable(STRATEGY)).upgradeToAndCall(address(_newImplementation), "");
    }
}
