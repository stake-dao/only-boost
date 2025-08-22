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

import "src/CRVStrategy.sol";

/// @notice Strategy contract, supporting Shutdown.
contract CurveShutdownStrategy is CRVStrategy {
    enum ShutdownMode {
        NORMAL, // No automatic shutdown
        AUTO_SHUTDOWN, // Current behavior - each harvest shuts down gauge
        SELECTIVE_SHUTDOWN // Only owner can shutdown by harvesting

    }

    ShutdownMode public shutdownMode; // Will be initialized in constructor or via setter

    /// @notice Mapping of shutdown gauges.
    mapping(address => bool) public isShutdown;

    /// @notice Mapping of protected gauges.
    mapping(address => bool) public protectedGauges;

    /// @notice Event emitted when shutdown mode is changed.
    event ShutdownModeChanged(ShutdownMode newMode);

    /// @notice Error thrown when a shutdown gauge is harvested.
    error SHUTDOWN();

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        CRVStrategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    /// @dev Disable regular locker harvest.
    function harvest(address, bool, bool) public pure override {
        revert SHUTDOWN();
    }

    /// @notice Harvest the asset with flexible shutdown logic based on mode.
    /// @param asset The asset to harvest.
    function harvest(address asset, bool, bool, bool) public override {
        address gauge = gauges[asset];
        if (isShutdown[gauge]) revert SHUTDOWN();

        /// Harvest as usual.
        super.harvest(asset, false, true, true);

        /// Determine if we should shutdown based on mode
        bool shouldShutdown = false;

        if (shutdownMode == ShutdownMode.NORMAL) {
            shouldShutdown = false; // Never auto-shutdown
        } else if (shutdownMode == ShutdownMode.AUTO_SHUTDOWN) {
            shouldShutdown = !protectedGauges[gauge]; // Current behavior
        } else if (shutdownMode == ShutdownMode.SELECTIVE_SHUTDOWN) {
            shouldShutdown = (msg.sender == governance); // Only owner can shutdown
        }

        if (shouldShutdown) {
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
    }

    function rebalance(address asset) public override {
        address gauge = gauges[asset];
        if (isShutdown[gauge]) revert SHUTDOWN();

        super.rebalance(asset);
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

    /// @notice Set the shutdown mode.
    /// @param _mode The new shutdown mode.
    function setShutdownMode(ShutdownMode _mode) external onlyGovernance {
        shutdownMode = _mode;
        emit ShutdownModeChanged(_mode);
    }
}
