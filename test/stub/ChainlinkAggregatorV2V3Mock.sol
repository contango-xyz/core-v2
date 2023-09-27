//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "../dependencies/chainlink/AggregatorV2V3Interface.sol";

contract ChainlinkAggregatorV2V3Mock is AggregatorV2V3Interface {

    uint8 public override decimals;
    int256 public price;
    uint256 public timestamp;
    uint256 private _roundId;

    function setDecimals(uint8 _decimals) external returns (ChainlinkAggregatorV2V3Mock) {
        decimals = _decimals;
        return ChainlinkAggregatorV2V3Mock(address(this));
    }

    function set(int256 _price) external returns (ChainlinkAggregatorV2V3Mock) {
        price = _price;
        timestamp = block.timestamp;

        emit AnswerUpdated(price, ++_roundId, timestamp);

        return ChainlinkAggregatorV2V3Mock(address(this));
    }

    // V3

    function aggregator() external view override returns (address) {
        return address(this);
    }

    function description() external pure override returns (string memory) {
        return "ChainlinkAggregatorV2V3Mock";
    }

    function version() external pure override returns (uint256) {
        return 3;
    }

    function getRoundData(uint80 roundId)
        external
        view
        override
        returns (uint80 roundId_, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (roundId, price, 0, timestamp, 0);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, price, 0, timestamp, 0);
    }

    // V2

    function latestAnswer() external view override returns (int256) {
        return price;
    }

    function latestTimestamp() external view override returns (uint256) {
        return timestamp;
    }

    function latestRound() external view override returns (uint256) {
        return _roundId;
    }

    function getAnswer(uint256) external view override returns (int256) {
        return price;
    }

    function getTimestamp(uint256) external view override returns (uint256) {
        return timestamp;
    }

}
