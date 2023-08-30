// SPDX-License-Identifier: MIT
// Rewards logic inspired by Tribe DAO Contracts (flywheel-v2/src/rewards/IFlywheelBooster.sol)
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BribesFactory} from "@gauges/factories/BribesFactory.sol";

import {bHermesGauges} from "@hermes/tokens/bHermesGauges.sol";

import {FlywheelCore} from "@rewards/FlywheelCoreStrategy.sol";

import {IFlywheelBooster} from "../interfaces/IFlywheelBooster.sol";

/**
 * @title Balance Booster Module for Flywheel
 *  @notice Flywheel is a general framework for managing token incentives.
 *          It takes reward streams to various *strategies* such as staking LP tokens and divides them among *users* of those strategies.
 *
 *          The Booster module is an optional module for virtually boosting or otherwise transforming user balances.
 *          If a booster is not configured, the strategies ERC-20 balanceOf/totalSupply will be used instead.
 *
 *          Boosting logic can be associated with referrals, vote-escrow, or other strategies.
 *
 *          SECURITY NOTE: similar to how Core needs to be notified any time the strategy user composition changes, the booster would need to be notified of any conditions which change the boosted balances atomically.
 *          This prevents gaming of the reward calculation function by using manipulated balances when accruing.
 *
 *          NOTE: Gets total and user voting power allocated to each strategy.
 *
 * ⣿⡇⣿⣿⣿⠛⠁⣴⣿⡿⠿⠧⠹⠿⠘⣿⣿⣿⡇⢸⡻⣿⣿⣿⣿⣿⣿⣿
 * ⢹⡇⣿⣿⣿⠄⣞⣯⣷⣾⣿⣿⣧⡹⡆⡀⠉⢹⡌⠐⢿⣿⣿⣿⡞⣿⣿⣿
 * ⣾⡇⣿⣿⡇⣾⣿⣿⣿⣿⣿⣿⣿⣿⣄⢻⣦⡀⠁⢸⡌⠻⣿⣿⣿⡽⣿⣿
 * ⡇⣿⠹⣿⡇⡟⠛⣉⠁⠉⠉⠻⡿⣿⣿⣿⣿⣿⣦⣄⡉⠂⠈⠙⢿⣿⣝⣿
 * ⠤⢿⡄⠹⣧⣷⣸⡇⠄⠄⠲⢰⣌⣾⣿⣿⣿⣿⣿⣿⣶⣤⣤⡀⠄⠈⠻⢮
 * ⠄⢸⣧⠄⢘⢻⣿⡇⢀⣀⠄⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⡀⠄⢀
 * ⠄⠈⣿⡆⢸⣿⣿⣿⣬⣭⣴⣿⣿⣿⣿⣿⣿⣿⣯⠝⠛⠛⠙⢿⡿⠃⠄⢸
 * ⠄⠄⢿⣿⡀⣿⣿⣿⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣿⣿⣿⣿⡾⠁⢠⡇⢀
 * ⠄⠄⢸⣿⡇⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣏⣫⣻⡟⢀⠄⣿⣷⣾
 * ⠄⠄⢸⣿⡇⠄⠈⠙⠿⣿⣿⣿⣮⣿⣿⣿⣿⣿⣿⣿⣿⡿⢠⠊⢀⡇⣿⣿
 * ⠒⠤⠄⣿⡇⢀⡲⠄⠄⠈⠙⠻⢿⣿⣿⠿⠿⠟⠛⠋⠁⣰⠇⠄⢸⣿⣿⣿
 * ⠄⠄⠄⣿⡇⢬⡻⡇⡄⠄⠄⠄⡰⢖⠔⠉⠄⠄⠄⠄⣼⠏⠄⠄⢸⣿⣿⣿
 * ⠄⠄⠄⣿⡇⠄⠙⢌⢷⣆⡀⡾⡣⠃⠄⠄⠄⠄⠄⣼⡟⠄⠄⠄⠄⢿⣿⣿
 */
contract FlywheelBoosterGaugeWeight is Ownable, IFlywheelBooster {
    /*///////////////////////////////////////////////////////////////
                        FLYWHEEL BOOSTER STATE
    ///////////////////////////////////////////////////////////////*/

    BribesFactory public immutable bribesFactory;

    /// @inheritdoc IFlywheelBooster
    mapping(address user => mapping(ERC20 strategy => FlywheelCore[] flywheel)) public userGaugeFlywheels;

    /// @inheritdoc IFlywheelBooster
    mapping(address user => mapping(ERC20 strategy => mapping(FlywheelCore flywheel => uint256 id))) public
        userGaugeflywheelId;

    /// @inheritdoc IFlywheelBooster
    mapping(ERC20 strategy => mapping(FlywheelCore flywheel => uint256 gaugeWeight)) public flywheelStrategyGaugeWeight;

    constructor(uint256 _rewardsCycleLength) {
        // Must transfer ownership to bHermesGauges contract after its depolyment.
        _initializeOwner(msg.sender);

        bribesFactory = new BribesFactory(_rewardsCycleLength, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW HELPERS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlywheelBooster
    function getUserGaugeFlywheels(address user, ERC20 strategy) external view returns (FlywheelCore[] memory) {
        return userGaugeFlywheels[user][strategy];
    }

    /// @inheritdoc IFlywheelBooster
    /// @dev Total opt in gauge weight allocated to the strategy
    function boostedTotalSupply(ERC20 strategy) external view returns (uint256) {
        return flywheelStrategyGaugeWeight[strategy][FlywheelCore(msg.sender)];
    }

    /// @inheritdoc IFlywheelBooster
    /// @dev User's opt in gauge weight allocated to the strategy
    function boostedBalanceOf(ERC20 strategy, address user) external view returns (uint256) {
        return userGaugeflywheelId[user][strategy][FlywheelCore(msg.sender)] == 0
            ? 0
            : bHermesGauges(owner()).getUserGaugeWeight(user, address(strategy));
    }

    /*///////////////////////////////////////////////////////////////
                        USER BRIBE OPT-IN/OPT-OUT
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlywheelBooster
    function optIn(ERC20 strategy, FlywheelCore flywheel) external {
        if (userGaugeflywheelId[msg.sender][strategy][flywheel] != 0) revert AlreadyOptedIn();
        if (!bHermesGauges(owner()).isGauge(address(strategy))) revert InvalidGauge();
        if (bribesFactory.bribeFlywheelIds(flywheel) == 0) revert InvalidFlywheel();

        flywheel.accrue(strategy, msg.sender);

        flywheelStrategyGaugeWeight[strategy][flywheel] = flywheelStrategyGaugeWeight[strategy][flywheel]
            + bHermesGauges(owner()).getUserGaugeWeight(msg.sender, address(strategy));

        userGaugeFlywheels[msg.sender][strategy].push(flywheel);
        userGaugeflywheelId[msg.sender][strategy][flywheel] = userGaugeFlywheels[msg.sender][strategy].length;
    }

    /// @inheritdoc IFlywheelBooster
    function optOut(ERC20 strategy, FlywheelCore flywheel) external {
        FlywheelCore[] storage bribeFlywheels = userGaugeFlywheels[msg.sender][strategy];

        uint256 userFlywheelId = userGaugeflywheelId[msg.sender][strategy][flywheel];

        if (userFlywheelId == 0) revert NotOptedIn();

        flywheel.accrue(strategy, msg.sender);

        flywheelStrategyGaugeWeight[strategy][flywheel] = flywheelStrategyGaugeWeight[strategy][flywheel]
            - bHermesGauges(owner()).getUserGaugeWeight(msg.sender, address(strategy));

        uint256 length = bribeFlywheels.length;
        if (length != userFlywheelId) {
            FlywheelCore lastFlywheel = bribeFlywheels[length - 1];

            bribeFlywheels[userFlywheelId - 1] = lastFlywheel;
            userGaugeflywheelId[msg.sender][strategy][lastFlywheel] = userFlywheelId;
        }

        bribeFlywheels.pop();
        userGaugeflywheelId[msg.sender][strategy][flywheel] = 0;
    }

    /*///////////////////////////////////////////////////////////////
                       bHERMES GAUGE WEIGHT ACCRUAL
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlywheelBooster
    function accrueBribesPositiveDelta(address user, ERC20 strategy, uint256 delta) external onlyOwner {
        _accrueBribes(user, strategy, delta, _add);
    }

    /// @inheritdoc IFlywheelBooster
    function accrueBribesNegativeDelta(address user, ERC20 strategy, uint256 delta) external onlyOwner {
        _accrueBribes(user, strategy, delta, _subtract);
    }

    /**
     * @notice Accrues bribes for a given user per strategy.
     *   @param user the user to accrue bribes for
     *   @param strategy the strategy to accrue bribes for
     *   @param delta the delta to accrue bribes for
     *   @param op the operation to perform on the gauge weight
     */
    function _accrueBribes(
        address user,
        ERC20 strategy,
        uint256 delta,
        function(uint256, uint256) view returns (uint256) op
    ) private {
        FlywheelCore[] storage bribeFlywheels = userGaugeFlywheels[user][strategy];
        uint256 length = bribeFlywheels.length;
        for (uint256 i = 0; i < length;) {
            FlywheelCore flywheel = bribeFlywheels[i];
            flywheel.accrue(strategy, user);

            flywheelStrategyGaugeWeight[strategy][flywheel] = op(flywheelStrategyGaugeWeight[strategy][flywheel], delta);
            unchecked {
                i++;
            }
        }
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }
}
