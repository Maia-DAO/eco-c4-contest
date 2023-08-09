// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@gauges/factories/BribesFactory.sol";

contract MockBribesFactory is BribesFactory {

    constructor(
        uint256 _rewardsCycleLength,
        address _owner
    ) BribesFactory(_rewardsCycleLength, _owner) {}
}
