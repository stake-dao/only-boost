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

import "src/YearnStrategy.sol";

/// @notice Strategy contract, supporting Shutdown.
contract YearnShutdownStrategy is YearnStrategy {
    /// @notice Mapping of shutdown gauges.
    mapping(address => bool) public isShutdown;

    /// @notice Mapping of protected gauges.
    mapping(address => bool) public protectedGauges;

    /// @notice Error thrown when a shutdown gauge is harvested.
    error SHUTDOWN();

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        YearnStrategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    /// @notice Harvest the asset and shutdown the gauge.
    /// @param asset The asset to harvest.
    function harvest(address asset, bool, bool) public override {
        address gauge = gauges[asset];
        if (isShutdown[gauge]) revert SHUTDOWN();

        /// Harvest as usual.
        super.harvest(asset, false, true);

        /// Don't shutdown protected gauges.
        if (protectedGauges[gauge]) {
            return;
        }

        /// 1. Get the vault address.
        address rewardDistributor = rewardDistributors[gauge];
        address vault = ILiquidityGauge(rewardDistributor).staking_token();

        /// 2. Withdraw all the funds from the gauge.
        uint256 balance = balanceOf(asset);
        _withdraw(asset, balance);

        /// 3. Send the funds back to the vault.
        SafeTransferLib.safeTransfer(asset, vault, balance);

        /// 4. Mark the gauge as shutdown.
        isShutdown[gauge] = true;
    }

    function _deposit(address asset, uint256 amount) internal override {
        address gauge = gauges[asset];
        if (isShutdown[gauge]) revert SHUTDOWN();

        super._deposit(asset, amount);
    }

    function _withdraw(address asset, uint256 amount) internal override {
        address gauge = gauges[asset];
        if (isShutdown[gauge]) revert SHUTDOWN();

        super._withdraw(asset, amount);
    }

    /// @notice Set the protected gauges.
    /// @param _gauges The gauges to set as protected.
    function setProtectedGauges(address[] calldata _gauges) external onlyGovernance {
        for (uint256 i = 0; i < _gauges.length; i++) {
            protectedGauges[_gauges[i]] = true;
        }
    }

    /// @notice Unset the protected gauges.
    /// @param _gauges The gauges to unset as protected.
    function unsetProtectedGauges(address[] calldata _gauges) external onlyGovernance {
        for (uint256 i = 0; i < _gauges.length; i++) {
            protectedGauges[_gauges[i]] = false;
        }
    }
}