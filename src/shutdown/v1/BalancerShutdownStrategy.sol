// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
/*
▄▄▄█████▓ ██░ ██ ▓█████     ██░ ██ ▓█████  ██▀███  ▓█████▄ 
▓  ██▒ ▓▒▓██░ ██▒▓█   ▀    ▓██░ ██▒▓█   ▀ ▓██ ▒ ██▒▒██▀ ██▌
▒ ▓██░ ▒░▒██▀▀██░▒███      ▒██▀▀██░▒███   ▓██ ░▄█ ▒░██   █▌
░ ▓██▓ ░ ░▓█ ░██ ▒▓█  ▄    ░▓█ ░██ ▒▓█  ▄ ▒██▀▀█▄  ░▓█▄   ▌
  ▒██▒ ░ ░▓█▒░██▓░▒████▒   ░▓█▒░██▓░▒████▒░██▓ ▒██▒░▒████▓ 
  ▒ ░░    ▒ ░░▒░▒░░ ▒░ ░    ▒ ░░▒░▒░░ ▒░ ░░ ▒▓ ░▒▓░ ▒▒▓  ▒ 
    ░     ▒ ░▒░ ░ ░ ░  ░    ▒ ░▒░ ░ ░ ░  ░  ░▒ ░ ▒░ ░ ▒  ▒ 
  ░       ░  ░░ ░   ░       ░  ░░ ░   ░     ░░   ░  ░ ░  ░ 
          ░  ░  ░   ░  ░    ░  ░  ░   ░  ░   ░        ░    
                                                    ░      
              .,;>>%%%%%>>;,.
           .>%%%%%%%%%%%%%%%%%%%%>,.
         .>%%%%%%%%%%%%%%%%%%>>,%%%%%%;,.
       .>>>>%%%%%%%%%%%%%>>,%%%%%%%%%%%%,>>%%,.
     .>>%>>>>%%%%%%%%%>>,%%%%%%%%%%%%%%%%%,>>%%%%%,.
   .>>%%%%%>>%%%%>>,%%>>%%%%%%%%%%%%%%%%%%%%,>>%%%%%%%,
  .>>%%%%%%%%%%>>,%%%%%%>>%%%%%%%%%%%%%%%%%%,>>%%%%%%%%%%.
  .>>%%%%%%%%%%>>,>>>>%%%%%%%%%%'..`%%%%%%%%,;>>%%%%%%%%%>%%.
.>>%%%>>>%%%%%>,%%%%%%%%%%%%%%.%%%,`%%%%%%,;>>%%%%%%%%>>>%%%%.
>>%%>%>>>%>%%%>,%%%%%>>%%%%%%%%%%%%%`%%%%%%,>%%%%%%%>>>>%%%%%%%.
>>%>>>%%>>>%%%%>,%>>>%%%%%%%%%%%%%%%%`%%%%%%%%%%%%%%%%%%%%%%%%%%.
>>%%%%%%%%%%%%%%,>%%%%%%%%%%%%%%%%%%%'%%%,>>%%%%%%%%%%%%%%%%%%%%%.
>>%%%%%%%%%%%%%%%,>%%%>>>%%%%%%%%%%%%%%%,>>%%%%%%%%>>>>%%%%%%%%%%%.
>>%%%%%%%%;%;%;%%;,%>>>>%%%%%%%%%%%%%%%,>>>%%%%%%>>;";>>%%%%%%%%%%%%.
`>%%%%%%%%%;%;;;%;%,>%%%%%%%%%>>%%%%%%%%,>>>%%%%%%%%%%%%%%%%%%%%%%%%%%.
 >>%%%%%%%%%,;;;;;%%>,%%%%%%%%>>>>%%%%%%%%,>>%%%%%%%%%%%%%%%%%%%%%%%%%%%.
 `>>%%%%%%%%%,%;;;;%%%>,%%%%%%%%>>>>%%%%%%%%,>%%%%%%'%%%%%%%%%%%%%%%%%%%>>.
  `>>%%%%%%%%%%>,;;%%%%%>>,%%%%%%%%>>%%%%%%';;;>%%%%%,`%%%%%%%%%%%%%%%>>%%>.
   >>>%%%%%%%%%%>> %%%%%%%%>>,%%%%>>>%%%%%';;;;;;>>,%%%,`%     `;>%%%%%%>>%%
   `>>%%%%%%%%%%>> %%%%%%%%%>>>>>>>>;;;;'.;;;;;>>%%'  `%%'          ;>%%%%%>
    >>%%%%%%%%%>>; %%%%%%%%>>;;;;;;''    ;;;;;>>%%%                   ;>%%%%
    `>>%%%%%%%>>>, %%%%%%%%%>>;;'        ;;;;>>%%%'                    ;>%%%
     >>%%%%%%>>>':.%%%%%%%%%%>>;        .;;;>>%%%%                    ;>%%%'
     `>>%%%%%>>> ::`%%%%%%%%%%>>;.      ;;;>>%%%%'                   ;>%%%'
      `>>%%%%>>> `:::`%%%%%%%%%%>;.     ;;>>%%%%%                   ;>%%'
       `>>%%%%>>, `::::`%%%%%%%%%%>,   .;>>%%%%%'                   ;>%'
        `>>%%%%>>, `:::::`%%%%%%%%%>>. ;;>%%%%%%                    ;>%,
         `>>%%%%>>, :::::::`>>>%%%%>>> ;;>%%%%%'                     ;>%,
          `>>%%%%>>,::::::,>>>>>>>>>>' ;;>%%%%%                       ;%%,
            >>%%%%>>,:::,%%>>>>>>>>'   ;>%%%%%.                        ;%%
             >>%%%%>>``%%%%%>>>>>'     `>%%%%%%.
             >>%%%%>> `@@a%%%%%%'     .%%%%%%%%%.
             `a@@a%@'    `%a@@'       `a@@a%a@@a
 */

import "src/shutdown/v1/BaseShutdownStrategy.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

/// @notice Strategy contract, supporting Shutdown.
contract BalancerShutdownStrategy is Ownable2Step, BaseShutdownStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Address of the strategy.
    /// @dev It contains most of the storage of the strategy.
    address public constant STRATEGY = 0x873b031Ea6E4236E44d933Aae5a66AF6d4DA419d;

    /// @notice Address of the BAL token
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    /// @notice Address of the BAL minter
    address public constant BAL_MINTER = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;

    /// @notice Error when the BAL mint failed
    error MINT_FAILED();

    /// @notice Error when the BAL transfer failed
    error TRANSFER_FAILED();

    /// @notice Error when the caller is not the vault
    error ONLY_VAULT();

    /// @notice Event when BAL is claimed
    event Claimed(address indexed gauge, address indexed token, uint256 amount);

    /// @notice Event when a token is withdrawn
    event Withdrawn(address indexed gauge, address indexed token, uint256 amount);

    modifier onlyVault() {
        if (!IStrategy(STRATEGY).vaults(msg.sender)) revert ONLY_VAULT();
        _;
    }

    constructor(address _locker, address _gateway, address _governance)
        BaseShutdownStrategy(_locker, _gateway, _governance)
    {}

    /// @dev Reproduces the claim function of the STRATEGY contract and shuts down the gauge.
    function claim(address _token) external nonReentrant {
        address gauge = IStrategy(STRATEGY).gauges(_token);
        if (gauge == address(0)) revert ADDRESS_ZERO();
        if (isShutdown[gauge]) revert SHUTDOWN();

        /// 1. Snapshot the BAL balance.
        uint256 snapshot = IERC20(BAL).balanceOf(address(LOCKER));

        /// 2. Claim BAL through the BAL minter contract.
        if (!_executeTransaction(BAL_MINTER, abi.encodeWithSignature("mint(address)", gauge))) revert MINT_FAILED();

        /// 3. Calculate the minted BAL.
        uint256 minted = IERC20(BAL).balanceOf(address(LOCKER)) - snapshot;

        /// 4. Transfer the minted BAL to the strategy.
        if (!_executeTransaction(BAL, abi.encodeWithSignature("transfer(address,uint256)", address(this), minted))) {
            revert TRANSFER_FAILED();
        }

        /// 5. Distribute BAL.
        uint256 net = _chargeProtocolFees(BAL, minted);

        /// 6. Approve the reward distributor.
        address rewardDistributor = IStrategy(STRATEGY).multiGauges(gauge);

        /// 7. Approve the reward distributor.
        IERC20(BAL).safeApprove(rewardDistributor, net);

        /// 8. Deposit the BAL to the gauge.
        ILiquidityGauge(rewardDistributor).deposit_reward_token(BAL, net);

        /// 10. Extra Rewards.
        if (ILiquidityGauge(gauge).reward_tokens(0) != address(0)) {
            /// 10.1 Claim the rewards.
            _executeTransaction(
                gauge, abi.encodeWithSignature("claim_rewards(address,address)", address(LOCKER), address(this))
            );

            address rewardToken;
            uint256 rewardsBalance;
            for (uint8 i = 0; i < 8; i++) {
                rewardToken = ILiquidityGauge(gauge).reward_tokens(i);
                if (rewardToken == address(0)) {
                    break;
                }

                /// 10.2 Approve the reward token.
                rewardsBalance = IERC20(rewardToken).balanceOf(address(this));
                IERC20(rewardToken).approve(rewardDistributor, rewardsBalance);

                /// 10.3 Deposit the reward token.
                ILiquidityGauge(rewardDistributor).deposit_reward_token(rewardToken, rewardsBalance);

                /// 10.4 Emit the event.
                emit Claimed(gauge, rewardToken, rewardsBalance);
            }
        }

        /// Don't withdraw protected gauges.
        if (protectedGauges[rewardDistributor]) {
            return;
        }

        /// 11. Withdraw the funds from the gauge and send them back to the vault.
        address vault = ILiquidityGauge(rewardDistributor).staking_token();

        uint256 balance = IERC20(vault).totalSupply();
        _withdraw(_token, balance, vault);

        /// 12. Mark the gauge as shutdown.
        isShutdown[gauge] = true;

        emit Claimed(gauge, BAL, minted);
    }

    function deposit(address, uint256) external pure {
        revert SHUTDOWN();
    }

    function withdraw(address _token, uint256 _amount) external onlyVault {
        _withdraw(_token, _amount, msg.sender);
    }

    function claimProtocolFees() external {
        _claimProtocolFees(BAL);
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT & WITHDRAWAL REWRITES
    //////////////////////////////////////////////////////

    /// @notice function to withdraw from a gauge
    /// @param _token token address
    /// @param _amount amount to withdraw
    function _withdraw(address _token, uint256 _amount, address _receiver) internal {
        address gauge = IStrategy(STRATEGY).gauges(_token);
        if (gauge == address(0)) revert ADDRESS_ZERO();
        if (isShutdown[gauge]) revert SHUTDOWN();

        uint256 snapshot = IERC20(_token).balanceOf(LOCKER);

        if (!_executeTransaction(gauge, abi.encodeWithSignature("withdraw(uint256)", _amount))) {
            revert TRANSFER_FAILED();
        }

        uint256 net = IERC20(_token).balanceOf(LOCKER) - snapshot;
        if (!_executeTransaction(_token, abi.encodeWithSignature("transfer(address,uint256)", _receiver, net))) {
            revert TRANSFER_FAILED();
        }

        emit Withdrawn(gauge, _token, _amount);
    }
}
