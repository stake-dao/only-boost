// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "src/interfaces/IVault.sol";
import "src/interfaces/ILocker.sol";
import "src/libraries/SafeLibrary.sol";

import "src/shutdown/v1/PendleShutdownStrategy.sol";
import "src/shutdown/v1/WithdrawalOnlyLiquidityGauge.sol";

import {SafeTransferLib as SafeTransfer} from "solady/src/utils/SafeTransferLib.sol";

contract PendleShutdownTest is Test {
    using SafeTransfer for IERC20;

    PendleShutdownStrategy public strategy;
    WithdrawalOnlyLiquidityGauge public withdrawalOnlyGauge;

    /// @notice Current strategy address.
    address public constant STRATEGY = 0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54;

    /// @notice BAL address.
    address public constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;

    /// @notice Locker address.
    address public constant LOCKER = 0xD8fa8dC5aDeC503AcC5e026a98F32Ca5C1Fa289A;

    /// @notice Vault V2 address.
    address public constant VAULT = address(0x3Eb095A1889c1f1447d434283fd0a624a6b3b84b);

    /// @notice Random holder address.
    /// @dev We'll use it as it contains some vault funds.
    address public constant RANDOM_HOLDER = 0xD9E8DD798516F32B1fd58c457fe599DB739CFc2c;

    /// @notice Treasury address.
    address public constant TREASURY = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public governance;

    address public rewardDistributor;

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
        strategy = new PendleShutdownStrategy(LOCKER, address(gateway), governance);

        /// 4. Deploy Withdrawal Only Gauge.
        withdrawalOnlyGauge = new WithdrawalOnlyLiquidityGauge();

        /// 4. Enable the Strategy module in the Gateway.
        _enableModule(address(strategy));

        /// 5. Set Strategy as Pendle Strategy of the Vault.
        vm.prank(TREASURY);
        IVault(VAULT).setPendleStrategy(address(strategy));

        rewardDistributor = IVault(VAULT).liquidityGauge();

        vm.prank(TREASURY);
        IVault(VAULT).setLiquidityGauge(address(withdrawalOnlyGauge));

        vm.prank(TREASURY);
        ILiquidityGauge(rewardDistributor).set_reward_distributor(PENDLE, address(strategy));

        vm.prank(TREASURY);
        ILiquidityGauge(rewardDistributor).set_vault(address(withdrawalOnlyGauge));
    }

    function test_shutdown() public {
        address asset = IVault(VAULT).token();

        deal(asset, address(this), 1000e18);
        SafeTransfer.safeApprove(asset, VAULT, type(uint256).max);

        vm.expectRevert(BaseShutdownStrategy.SHUTDOWN.selector);
        IVault(VAULT).deposit(address(this), 1000e18);

        assertEq(strategy.isShutdown(asset), false);

        strategy.claim(asset);

        assertEq(strategy.isShutdown(asset), true);

        assertEq(_balanceOf(asset, VAULT), 0);
        assertEq(_balanceOf(asset, STRATEGY), 0);
        assertGt(IERC20(VAULT).totalSupply(), 0);
        assertEq(_balanceOf(asset, address(strategy)), IERC20(VAULT).totalSupply());

        vm.expectRevert(BaseShutdownStrategy.SHUTDOWN.selector);
        strategy.claim(asset);

        uint256 balance = IERC20(rewardDistributor).balanceOf(RANDOM_HOLDER);
        assertGt(balance, 0);

        vm.prank(RANDOM_HOLDER);
        IVault(VAULT).withdraw(balance);

        assertEq(IERC20(rewardDistributor).balanceOf(address(RANDOM_HOLDER)), 0);
        assertGe(_balanceOf(asset, RANDOM_HOLDER), balance);

        assertGt(strategy.protocolFeesAccrued(), 0);
        uint256 fees = strategy.protocolFeesAccrued();

        vm.prank(governance);
        strategy.setFeeRecipient(address(0xBEEF));

        strategy.claimProtocolFees();

        assertEq(_balanceOf(PENDLE, address(0xBEEF)), fees);
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
