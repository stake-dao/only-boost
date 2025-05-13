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

import {IVault} from "src/interfaces/IVault.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IPendleMarket} from "src/interfaces/IPendleMarket.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

/// @notice Strategy contract, supporting Shutdown for Pendle markets.
contract PendleShutdownStrategy is Ownable2Step, BaseShutdownStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Address of the strategy.
    /// @dev It contains most of the storage of the strategy.
    address public constant STRATEGY = 0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54;

    /// @notice Address of the PENDLE token
    address public constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;

    /// @notice Error when the PENDLE mint failed
    error MINT_FAILED();

    /// @notice Error when the PENDLE transfer failed
    error TRANSFER_FAILED();

    /// @notice Error when the caller is not the vault
    error ONLY_VAULT();

    /// @notice Event when PENDLE is claimed
    event Claimed(address indexed token, uint256 amount);

    /// @notice Event when a token is withdrawn
    event Withdrawn(address indexed token, uint256 amount);

    /// @notice Modifier to ensure only the vault can call certain functions
    modifier onlyVault() {
        if (!IStrategy(STRATEGY).vaults(msg.sender)) revert ONLY_VAULT();
        _;
    }

    /// @notice Constructor to initialize the shutdown strategy
    /// @param _locker Address of the locker contract
    /// @param _gateway Address of the gateway contract
    /// @param _governance Address of the governance contract
    constructor(address _locker, address _gateway, address _governance)
        BaseShutdownStrategy(_locker, _gateway, _governance)
    {}

    /// @dev Reproduces the claim function of the STRATEGY contract and shuts down the gauge.
    /// @param _token Address of the Pendle market token
    function claim(address _token) external nonReentrant {
        if (isShutdown[_token]) revert SHUTDOWN();

        /// 1. Get reward tokens and snapshot balances
        address[] memory rewardTokens = IPendleMarket(_token).getRewardTokens();
        uint256[] memory balancesBefore = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length;) {
            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(LOCKER);
            unchecked {
                ++i;
            }
        }

        /// 2. Redeem rewards from the Pendle market
        IPendleMarket(_token).redeemRewards(LOCKER);

        /// 3. Get the reward distributor (gauge)
        address rewardDistributor = IStrategy(STRATEGY).sdGauges(_token);

        /// 4. Process each reward token
        uint256 rewards;
        for (uint8 i; i < rewardTokens.length; ++i) {
            /// 4.1 Calculate rewards by comparing current balance with snapshot
            rewards = IERC20(rewardTokens[i]).balanceOf(LOCKER) - balancesBefore[i];
            if (rewards == 0) {
                continue;
            }

            /// 4.2 Transfer rewards to this contract
            if (
                !_executeTransaction(
                    rewardTokens[i], abi.encodeWithSignature("transfer(address,uint256)", address(this), rewards)
                )
            ) {
                revert TRANSFER_FAILED();
            }

            /// 4.3 Charge protocol fees if the reward is PENDLE
            uint256 net;
            if (rewardTokens[i] == PENDLE) {
                net = _chargeProtocolFees(PENDLE, rewards);
            } else {
                net = rewards;
            }

            /// 4.4 Approve and deposit rewards to the gauge
            IERC20(rewardTokens[i]).safeApprove(rewardDistributor, net);
            ILiquidityGauge(rewardDistributor).deposit_reward_token(rewardTokens[i], net);

            emit Claimed(rewardTokens[i], rewards);
        }

        /// Don't withdraw protected gauges.
        if (protectedGauges[rewardDistributor]) {
            return;
        }

        /// 5. Withdraw all funds from the gauge
        address vault = ILiquidityGauge(rewardDistributor).staking_token();
        uint256 balance = IERC20(vault).totalSupply();
        _withdrawAll(_token, balance);

        /// 6. Mark the market as shutdown
        isShutdown[_token] = true;

        emit Withdrawn(_token, IERC20(_token).balanceOf(address(this)));
    }

    /// @notice Withdraws tokens from the strategy to a specified receiver
    /// @param _token Address of the token to withdraw
    /// @param _amount Amount of tokens to withdraw
    /// @param _receiver Address to receive the withdrawn tokens
    function withdraw(address _token, uint256 _amount, address _receiver) external onlyVault {
        _withdraw(_token, _amount, _receiver);
    }

    /// @notice Claims protocol fees in PENDLE tokens
    function claimProtocolFees() external {
        _claimProtocolFees(PENDLE);
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT & WITHDRAWAL REWRITES
    //////////////////////////////////////////////////////

    /// @notice Internal function to withdraw tokens to a specific receiver
    /// @param _token Address of the token to withdraw
    /// @param _amount Amount of tokens to withdraw
    /// @param _receiver Address to receive the withdrawn tokens
    function _withdraw(address _token, uint256 _amount, address _receiver) internal {
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    /// @notice Internal function to withdraw all tokens from a gauge
    /// @param _token Address of the token to withdraw
    /// @param _amount Amount of tokens to withdraw
    function _withdrawAll(address _token, uint256 _amount) internal {
        if (!_executeTransaction(_token, abi.encodeWithSignature("transfer(address,uint256)", address(this), _amount)))
        {
            revert TRANSFER_FAILED();
        }
    }
}
