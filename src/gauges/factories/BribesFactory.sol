// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseV2Gauge} from "@gauges/BaseV2Gauge.sol";

import {bHermesGauges} from "@hermes/tokens/bHermesGauges.sol";

import {FlywheelBoosterGaugeWeight} from "@rewards/booster/FlywheelBoosterGaugeWeight.sol";
import {MultiRewardsDepot} from "@rewards/depots/MultiRewardsDepot.sol";
import {FlywheelBribeRewards} from "@rewards/rewards/FlywheelBribeRewards.sol";
import {FlywheelCore} from "@rewards/FlywheelCoreStrategy.sol";

import {IBribesFactory} from "../interfaces/IBribesFactory.sol";

/// @title Gauge Bribes Factory
contract BribesFactory is Ownable, IBribesFactory {
    /*///////////////////////////////////////////////////////////////
                        BRIBES FACTORY STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBribesFactory
    uint256 public immutable rewardsCycleLength;

    FlywheelBoosterGaugeWeight private immutable flywheelGaugeWeightBooster;

    /// @inheritdoc IBribesFactory
    FlywheelCore[] public bribeFlywheels;

    /// @inheritdoc IBribesFactory
    mapping(FlywheelCore bribeflywheel => uint256 id) public bribeFlywheelIds;

    /// @inheritdoc IBribesFactory
    mapping(address tokenAddress => FlywheelCore flywheel) public tokenToFlywheel;

    /**
     * @notice Creates a new bribes factory
     * @param _rewardsCycleLength Rewards Cycle Length
     * @param _owner Owner of this contract, transfer to bHermesGauges contract after deployment
     */
    constructor(uint256 _rewardsCycleLength, address _owner) {
        _initializeOwner(_owner);
        rewardsCycleLength = _rewardsCycleLength;
        flywheelGaugeWeightBooster = FlywheelBoosterGaugeWeight(msg.sender);
    }

    /// @inheritdoc IBribesFactory
    function getBribeFlywheels() external view returns (FlywheelCore[] memory) {
        return bribeFlywheels;
    }

    /*//////////////////////////////////////////////////////////////
                          ADD GAUGE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBribesFactory
    function addGaugetoFlywheel(address gauge, address bribeToken) external returns (FlywheelCore flywheel) {
        if (!bHermesGauges(owner()).isGauge(gauge)) revert InvalidGauge();

        flywheel = tokenToFlywheel[bribeToken];
        if (address(flywheel) == address(0)) flywheel = createBribeFlywheel(bribeToken);

        flywheel.addStrategyForRewards(ERC20(gauge));

        FlywheelBribeRewards flyhweelRewards = FlywheelBribeRewards(flywheel.flywheelRewards());
        MultiRewardsDepot rewardsDepot = BaseV2Gauge(gauge).multiRewardsDepot();

        flyhweelRewards.setRewardsDepot(gauge, rewardsDepot);
        rewardsDepot.addAsset(address(flyhweelRewards), bribeToken);
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE BRIBE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBribesFactory
    function createBribeFlywheel(address bribeToken) public returns (FlywheelCore flywheel) {
        if (address(tokenToFlywheel[bribeToken]) != address(0)) revert BribeFlywheelAlreadyExists();
        if (bribeToken == address(0)) revert InvalidBribeToken();

        bytes32 salt = keccak256(abi.encodePacked(bribeToken));

        flywheel = new FlywheelCore{salt: salt}(
            bribeToken,
            FlywheelBribeRewards(address(0)),
            flywheelGaugeWeightBooster,
            address(this)
        );

        tokenToFlywheel[bribeToken] = flywheel;

        bribeFlywheels.push(flywheel);
        bribeFlywheelIds[flywheel] = bribeFlywheels.length;

        flywheel.setFlywheelRewards(address(new FlywheelBribeRewards{salt: salt}(flywheel, rewardsCycleLength)));

        emit BribeFlywheelCreated(bribeToken, flywheel);
    }
}
