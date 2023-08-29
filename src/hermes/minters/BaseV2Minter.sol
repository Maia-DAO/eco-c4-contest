// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {ERC4626} from "@ERC4626/ERC4626.sol";

import {HERMES} from "@hermes/tokens/HERMES.sol";

import {FlywheelGaugeRewards} from "@rewards/rewards/FlywheelGaugeRewards.sol";

import {IBaseV2Minter} from "../interfaces/IBaseV2Minter.sol";

/// @title Base V2 Minter - Mints HERMES tokens for the B(3,3) system
contract BaseV2Minter is Ownable, IBaseV2Minter {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                         MINTER STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev 2% per week target emission
    uint256 internal constant BASE = 1000;

    uint256 internal constant MAX_TAIL_EMISSION = 100;
    uint256 internal constant MAX_DAO_SHARE = 300;

    /// @inheritdoc IBaseV2Minter
    address public immutable override underlying;
    /// @inheritdoc IBaseV2Minter
    ERC4626 public immutable override vault;

    /// @inheritdoc IBaseV2Minter
    FlywheelGaugeRewards public override flywheelGaugeRewards;
    /// @inheritdoc IBaseV2Minter
    address public override dao;

    /// @inheritdoc IBaseV2Minter
    uint256 public override daoShare = 100;
    uint256 public override tailEmission = 20;
    /// @inheritdoc IBaseV2Minter

    /// @inheritdoc IBaseV2Minter
    uint256 public override weekly;
    /// @inheritdoc IBaseV2Minter
    uint256 public override activePeriod;

    address internal initializer;

    constructor(
        address _vault, // the B(3,3) system that will be locked into
        address _dao,
        address _owner
    ) {
        _initializeOwner(_owner);
        initializer = msg.sender;
        dao = _dao;
        underlying = address(ERC4626(_vault).asset());
        vault = ERC4626(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK LOGIC
    //////////////////////////////////////////////////////////////*/

    fallback() external {
        updatePeriod();
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseV2Minter
    function initialize(FlywheelGaugeRewards _flywheelGaugeRewards) external {
        if (initializer != msg.sender) revert NotInitializer();
        flywheelGaugeRewards = _flywheelGaugeRewards;
        initializer = address(0);
        activePeriod = (block.timestamp / 1 weeks) * 1 weeks;
    }

    /// @inheritdoc IBaseV2Minter
    function setDao(address _dao) external onlyOwner {
        /// @dev DAO can be set to address(0) to disable DAO rewards.
        dao = _dao;
        if (_dao == address(0)) daoShare = 0;

        emit ChangedDao(_dao);
    }

    /// @inheritdoc IBaseV2Minter
    function setDaoShare(uint256 _daoShare) external onlyOwner {
        if (_daoShare > MAX_DAO_SHARE) revert DaoShareTooHigh();
        if (dao == address(0)) revert DaoRewardsAreDisabled();
        daoShare = _daoShare;

        emit ChangedDaoShare(_daoShare);
    }

    /// @inheritdoc IBaseV2Minter
    function setTailEmission(uint256 _tailEmission) external onlyOwner {
        if (_tailEmission > MAX_TAIL_EMISSION) revert TailEmissionTooHigh();
        tailEmission = _tailEmission;

        emit ChangedTailEmission(_tailEmission);
    }

    /*//////////////////////////////////////////////////////////////
                         EMISSION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseV2Minter
    function circulatingSupply() public view returns (uint256) {
        return HERMES(underlying).totalSupply() - vault.totalAssets();
    }

    /// @inheritdoc IBaseV2Minter
    function weeklyEmission() public view returns (uint256) {
        return (circulatingSupply() * tailEmission) / BASE;
    }

    /// @inheritdoc IBaseV2Minter
    function calculateGrowth(uint256 _minted) public view returns (uint256) {
        return (vault.totalAssets() * _minted) / HERMES(underlying).totalSupply();
    }

    /// @inheritdoc IBaseV2Minter
    function updatePeriod() public returns (uint256) {
        uint256 _period = activePeriod;
        // only trigger if new week
        if (block.timestamp >= _period + 1 weeks && initializer == address(0)) {
            _period = (block.timestamp / 1 weeks) * 1 weeks;
            activePeriod = _period;
            uint256 newWeeklyEmission = weeklyEmission();
            weekly += newWeeklyEmission;
            uint256 _circulatingSupply = circulatingSupply();

            uint256 _growth = calculateGrowth(newWeeklyEmission);
            /// @dev share of newWeeklyEmission emissions sent to DAO.
            uint256 share = (newWeeklyEmission * daoShare) / BASE;

            uint256 _required = weekly + _growth + share;
            uint256 _balanceOf = underlying.balanceOf(address(this));
            if (_balanceOf < _required) {
                HERMES(underlying).mint(address(this), _required - _balanceOf);
            }

            underlying.safeTransfer(address(vault), _growth);

            if (dao != address(0)) underlying.safeTransfer(dao, share);

            emit Mint(msg.sender, newWeeklyEmission, _circulatingSupply, _growth, share);

            /// @dev queue rewards for the cycle, anyone can call if fails
            ///      queueRewardsForCycle will call this function but won't enter
            ///      here because activePeriod was updated
            try flywheelGaugeRewards.queueRewardsForCycle() {} catch {}
        }
        return _period;
    }

    /*//////////////////////////////////////////////////////////////
                         REWARDS STREAM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseV2Minter
    function getRewards() external returns (uint256 totalQueuedForCycle) {
        if (address(flywheelGaugeRewards) != msg.sender) revert NotFlywheelGaugeRewards();
        totalQueuedForCycle = weekly;
        weekly = 0;
        underlying.safeTransfer(msg.sender, totalQueuedForCycle);
    }
}
