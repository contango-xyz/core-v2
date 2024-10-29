// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IVotingEscrow {

    event ApplyOwnership(address admin);
    event CommitOwnership(address admin);
    event Deposit(address indexed provider, uint256 value, uint256 indexed locktime, int128 _type, uint256 ts);
    event EarlyUnlock(bool status);
    event PenaltySpeed(uint256 penalty_k);
    event PenaltyTreasury(address penalty_treasury);
    event RewardReceiver(address newReceiver);
    event Supply(uint256 prevSupply, uint256 supply);
    event TotalUnlock(bool status);
    event Withdraw(address indexed provider, uint256 value, uint256 ts);
    event WithdrawEarly(address indexed provider, uint256 penalty, uint256 time_left);

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    function MAXTIME() external view returns (uint256);
    function TOKEN() external view returns (address);
    function admin() external view returns (address);
    function admin_early_unlock() external view returns (address);
    function admin_unlock_all() external view returns (address);
    function all_unlock() external view returns (bool);
    function apply_smart_wallet_checker() external;
    function apply_transfer_ownership() external;
    function balMinter() external view returns (address);
    function balToken() external view returns (address);
    function balanceOf(address addr) external view returns (uint256);
    function balanceOf(address addr, uint256 _t) external view returns (uint256);
    function balanceOfAt(address addr, uint256 _block) external view returns (uint256);
    function changeRewardReceiver(address newReceiver) external;
    function checkpoint() external;
    function claimExternalRewards() external;
    function commit_smart_wallet_checker(address addr) external;
    function commit_transfer_ownership(address addr) external;
    function create_lock(uint256 _value, uint256 _unlock_time) external;
    function decimals() external view returns (uint256);
    function deposit_for(address _addr, uint256 _value) external;
    function early_unlock() external view returns (bool);
    function epoch() external view returns (uint256);
    function future_admin() external view returns (address);
    function future_smart_wallet_checker() external view returns (address);
    function get_last_user_slope(address addr) external view returns (int128);
    function increase_amount(uint256 _value) external;
    function increase_unlock_time(uint256 _unlock_time) external;
    function initialize(
        address _token_addr,
        string memory _name,
        string memory _symbol,
        address _admin_addr,
        address _admin_unlock_all,
        address _admin_early_unlock,
        uint256 _max_time,
        address _balToken,
        address _balMinter,
        address _rewardReceiver,
        bool _rewardReceiverChangeable,
        address _rewardDistributor
    ) external;
    function is_initialized() external view returns (bool);
    function locked(address arg0) external view returns (LockedBalance memory);
    function locked__end(address _addr) external view returns (uint256);
    function name() external view returns (string memory);
    function penalty_k() external view returns (uint256);
    function penalty_treasury() external view returns (address);
    function penalty_upd_ts() external view returns (uint256);
    function point_history(uint256 arg0) external view returns (Point memory);
    function prev_penalty_k() external view returns (uint256);
    function rewardDistributor() external view returns (address);
    function rewardReceiver() external view returns (address);
    function rewardReceiverChangeable() external view returns (bool);
    function set_all_unlock() external;
    function set_early_unlock(bool _early_unlock) external;
    function set_early_unlock_penalty_speed(uint256 _penalty_k) external;
    function set_penalty_treasury(address _penalty_treasury) external;
    function slope_changes(uint256 arg0) external view returns (int128);
    function smart_wallet_checker() external view returns (address);
    function supply() external view returns (uint256);
    function symbol() external view returns (string memory);
    function token() external view returns (address);
    function totalSupply() external view returns (uint256);
    function totalSupply(uint256 t) external view returns (uint256);
    function totalSupplyAt(uint256 _block) external view returns (uint256);
    function user_point_epoch(address arg0) external view returns (uint256);
    function user_point_history(address arg0, uint256 arg1) external view returns (Point memory);
    function user_point_history__ts(address _addr, uint256 _idx) external view returns (uint256);
    function withdraw() external;
    function withdraw_early() external;

}
