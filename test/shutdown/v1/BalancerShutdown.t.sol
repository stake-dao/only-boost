// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "src/interfaces/IVault.sol";
import "src/interfaces/ILocker.sol";
import "src/libraries/SafeLibrary.sol";
import "src/shutdown/v1/BalancerShutdownStrategy.sol";

import {SafeTransferLib as SafeTransfer} from "solady/src/utils/SafeTransferLib.sol";

contract BalancerShutdownTest is Test {
    using SafeTransfer for IERC20;

    BalancerShutdownStrategy public strategy;

    /// @notice Current strategy address.
    address public constant STRATEGY = 0x873b031Ea6E4236E44d933Aae5a66AF6d4DA419d;

    /// @notice BAL address.
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    /// @notice Locker address.
    address public constant LOCKER = 0xea79d1A83Da6DB43a85942767C389fE0ACf336A5;

    /// @notice Vault V2 address.
    address public constant VAULT = address(0x7ca0a95C96Cd34013d619EFfcb02f200A031210d);

    /// @notice Random holder address.
    /// @dev We'll use it as it contains some vault funds.
    address public constant RANDOM_HOLDER = 0xb0e83C2D71A991017e0116d58c5765Abc57384af;

    /// @notice Treasury address.
    address public constant TREASURY = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public governance;

    /// @notice The signature for the Safe transaction.
    bytes internal signatures;

    Safe public gateway;

    function setUp() public virtual {
        vm.createSelectFork("mainnet", 22_117_697);

        governance = IStrategy(STRATEGY).governance();
        signatures = abi.encodePacked(uint256(uint160(governance)), uint8(0), uint256(1));

        address[] memory owners = new address[](1);
        owners[0] = governance;

        /// 1. Deploy Gateway.
        gateway = SafeLibrary.deploySafe({_owners: owners, _threshold: 1, _saltNonce: 0});

        /// 2. Set Gateway as Governance of the Locker.
        vm.prank(STRATEGY);
        ILocker(LOCKER).setGovernance(address(gateway));

        /// 3. Deploy Strategy.
        strategy = new BalancerShutdownStrategy(LOCKER, address(gateway), governance);

        /// 4. Enable the Strategy module in the Gateway.
        _enableModule(address(strategy));

        /// 5. Set Strategy as Balancer Strategy of the Vault.
        vm.prank(TREASURY);
        IVault(VAULT).setBalancerStrategy(address(strategy));

        address liquidityGauge = IVault(VAULT).liquidityGauge();

        vm.prank(TREASURY);
        ILiquidityGauge(liquidityGauge).set_reward_distributor(BAL, address(strategy));
    }

    function test_shutdown() public {
        address asset = IVault(VAULT).token();
        address liquidityGauge = IVault(VAULT).liquidityGauge();
        address gauge = IStrategy(STRATEGY).gauges(asset);

        deal(asset, address(this), 1000e18);
        SafeTransfer.safeApprove(asset, VAULT, type(uint256).max);

        vm.expectRevert(BaseShutdownStrategy.SHUTDOWN.selector);
        IVault(VAULT).deposit(address(this), 1000e18, true);

        assertEq(strategy.isShutdown(gauge), false);

        address[] memory protectedGauges = new address[](1);
        protectedGauges[0] = gauge;

        vm.prank(governance);
        strategy.setProtectedGauges(protectedGauges);

        strategy.claim(asset);

        assertEq(strategy.isShutdown(gauge), false);
        assertEq(_balanceOf(asset, VAULT), 0);

        skip(1 days);

        vm.prank(governance);
        strategy.unsetProtectedGauges(protectedGauges);

        strategy.claim(asset);

        assertEq(strategy.isShutdown(gauge), true);

        assertEq(_balanceOf(asset, STRATEGY), 0);
        assertGt(IERC20(VAULT).totalSupply(), 0);
        assertEq(_balanceOf(asset, VAULT), IERC20(VAULT).totalSupply());

        vm.expectRevert(BaseShutdownStrategy.SHUTDOWN.selector);
        strategy.claim(asset);

        uint256 balance = IERC20(liquidityGauge).balanceOf(RANDOM_HOLDER);
        assertGt(balance, 0);

        vm.prank(RANDOM_HOLDER);
        IVault(VAULT).withdraw(balance);

        assertGe(_balanceOf(asset, RANDOM_HOLDER), balance);
        assertGt(strategy.protocolFeesAccrued(), 0);

        uint256 fees = strategy.protocolFeesAccrued();

        vm.prank(governance);
        strategy.setFeeRecipient(address(0xBEEF));

        strategy.claimProtocolFees();

        assertEq(_balanceOf(BAL, address(0xBEEF)), fees);
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return IERC20(_token).balanceOf(account);
    }

    /// @notice Enable a module in the Gateway.
    function _enableModule(address _module) internal {
        vm.prank(governance);
        gateway.execTransaction(
            address(gateway),
            0,
            abi.encodeWithSelector(IModuleManager.enableModule.selector, _module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signatures
        );
    }
}
