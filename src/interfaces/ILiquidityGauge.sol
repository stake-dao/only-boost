// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILiquidityGauge {
    struct Reward {
        address token;
        address distributor;
        uint256 period_finish;
        uint256 rate;
        uint256 last_update;
        uint256 integral;
    }

    function deposit_reward_token(address _rewardToken, uint256 _amount) external;

    function claim_rewards_for(address _user, address _recipient) external;

    function working_balances(address _address) external view returns (uint256);

    function deposit(uint256 _value, address _addr) external;

    function reward_tokens(uint256 _i) external view returns (address);

    function reward_data(address _tokenReward) external view returns (Reward memory);

    function balanceOf(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function claimable_reward(address _user, address _reward_token) external view returns (uint256);

    function claimable_tokens(address _user) external returns (uint256);

    function user_checkpoint(address _user) external returns (bool);

    function commit_transfer_ownership(address) external;

    function apply_transfer_ownership() external;

    function claim_rewards(address) external;

    function add_reward(address, address) external;

    function set_claimer(address) external;

    function admin() external view returns (address);

    function set_reward_distributor(address _rewardToken, address _newDistrib) external;

    function lp_token() external view returns (address);
}
