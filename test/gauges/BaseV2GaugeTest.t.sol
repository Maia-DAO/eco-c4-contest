// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {MockERC20Gauges} from "../erc-20/mocks/MockERC20Gauges.t.sol";

import {MockRewardsStream} from "../mocks/MockRewardsStream.sol";
import {MockBaseV2Gauge, MultiRewardsDepot} from "./mocks/MockBaseV2Gauge.sol";

import {FlywheelBoosterGaugeWeight, bHermesGauges} from "@rewards/booster/FlywheelBoosterGaugeWeight.sol";
import {FlywheelCore, ERC20} from "@rewards/FlywheelCoreStrategy.sol";
import {FlywheelBribeRewards} from "@rewards/rewards/FlywheelBribeRewards.sol";
import {FlywheelGaugeRewards, IBaseV2Minter} from "@rewards/rewards/FlywheelGaugeRewards.sol";

contract BaseV2GaugeTest is DSTestPlus {
    MockERC20 public strategy;
    MockERC20 public rewardToken;
    MockERC20 public hermes;
    MockERC20Gauges public gaugeToken;
    MockRewardsStream public rewardsStream;
    FlywheelGaugeRewards public rewards;
    MultiRewardsDepot public depot;
    FlywheelBoosterGaugeWeight public booster;

    MockBaseV2Gauge public gauge;

    uint256 constant WEEK = 604800;

    event Distribute(uint256 indexed amount, uint256 indexed epoch);

    event AddedBribeFlywheel(FlywheelCore indexed bribeFlywheel);

    event RemoveBribeFlywheel(FlywheelCore indexed bribeFlywheel);

    function setUp() public {
        hermes = new MockERC20("hermes", "HERMES", 18);

        rewardToken = new MockERC20("test token", "TKN", 18);
        strategy = new MockERC20("test strategy", "TKN", 18);

        rewardsStream = new MockRewardsStream(rewardToken, 100e18);
        rewardToken.mint(address(rewardsStream), 100e25);

        booster = new FlywheelBoosterGaugeWeight(1 weeks);

        gaugeToken = new MockERC20Gauges(address(this), address(booster), 604800, 604800 / 7);
        gaugeToken.setMaxGauges(10);

        booster.transferOwnership(address(gaugeToken));
        booster.bribesFactory().transferOwnership(address(gaugeToken));

        rewards = new FlywheelGaugeRewards(
            address(hermes),
            address(this),
            gaugeToken,
            IBaseV2Minter(address(rewardsStream))
        );

        hevm.mockCall(address(this), abi.encodeWithSignature("bHermesBoostToken()"), abi.encode(address(0)));
        hevm.mockCall(address(this), abi.encodeWithSignature("bribesFactory()"), abi.encode(address(booster.bribesFactory())));
        hevm.mockCall(address(0), abi.encodeWithSignature("gaugeBoost()"), abi.encode(gaugeToken));
        hevm.mockCall(address(rewardsStream), abi.encodeWithSignature("updatePeriod()"), abi.encode(0));

        gauge = new MockBaseV2Gauge(rewards, address(strategy));

        depot = gauge.multiRewardsDepot();

        gaugeToken.addGauge(address(gauge));
    }

    function createFlywheel(MockERC20 token) private returns (FlywheelCore flywheel) {
        flywheel = booster.bribesFactory().addGaugetoFlywheel(address(gauge), address(token));
    }

    function createFlywheel() private returns (FlywheelCore flywheel) {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        flywheel = createFlywheel(token);
    }

    function testNewEpochFail() external {
        uint256 epoch = gauge.epoch();
        gauge.newEpoch();
        assertEq(epoch, gauge.epoch());
    }

    function testNewEpochWorkThenFail() external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.expectEmit(true, true, true, true);
        emit Distribute(0, WEEK);

        gauge.newEpoch();
        uint256 epoch = gauge.epoch();
        gauge.newEpoch();
        assertEq(epoch, gauge.epoch());
    }

    function testNewEpochEmpty() external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.expectEmit(true, true, true, true);
        emit Distribute(0, WEEK);

        gauge.newEpoch();
    }

    function testNewEpoch() external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(rewards), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(100e18));

        hevm.expectEmit(true, true, true, true);
        emit Distribute(100e18, WEEK);

        gauge.newEpoch();
    }

    function testNewEpoch(uint256 amount) external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(rewards), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(amount));

        hevm.expectEmit(true, true, true, true);
        emit Distribute(amount, WEEK);

        gauge.newEpoch();
    }

    function testNewEpochTwice(uint256 amount) external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(rewards), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(amount));

        hevm.expectEmit(true, true, true, true);
        emit Distribute(amount, WEEK);

        gauge.newEpoch();

        hevm.warp(2 * WEEK); // skip to cycle 2

        hevm.expectEmit(true, true, true, true);
        emit Distribute(amount, 2 * WEEK);

        gauge.newEpoch();
    }

    function testNewEpochTwiceSecondHasNothing(uint256 amount) external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(rewards), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(amount));

        hevm.expectEmit(true, true, true, true);
        emit Distribute(amount, WEEK);

        gauge.newEpoch();

        hevm.warp(2 * WEEK); // skip to cycle 2

        hevm.mockCall(address(rewards), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(0));

        hevm.expectEmit(true, true, true, true);
        emit Distribute(0, 2 * WEEK);

        gauge.newEpoch();
    }

    function testAccrueBribes() external {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        FlywheelCore flywheel = createFlywheel(token);
        FlywheelBribeRewards bribeRewards = FlywheelBribeRewards(address(flywheel.flywheelRewards()));

        token.mint(address(depot), 100 ether);

        booster.optIn(ERC20(address(gauge)), flywheel);

        require(token.balanceOf(address(bribeRewards)) == 100 ether);
    }

    function testAccrueBribes(uint256 amount) external {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        FlywheelCore flywheel = createFlywheel(token);
        FlywheelBribeRewards bribeRewards = FlywheelBribeRewards(address(flywheel.flywheelRewards()));
        amount %= type(uint128).max;

        token.mint(address(depot), amount);

        booster.optIn(ERC20(address(gauge)), flywheel);

        require(token.balanceOf(address(bribeRewards)) == amount);
    }

    function testAccrueAndClaimBribes() external {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        FlywheelCore flywheel = createFlywheel(token);
        FlywheelBribeRewards bribeRewards = FlywheelBribeRewards(address(flywheel.flywheelRewards()));

        booster.optIn(ERC20(address(gauge)), flywheel);

        gaugeToken.mint(address(this), 100e18);
        gaugeToken.setMaxDelegates(1);
        gaugeToken.delegate(address(this));
        gaugeToken.incrementGauge(address(gauge), 100e18);

        hevm.warp(block.timestamp + WEEK); // skip to cycle 1

        token.mint(address(depot), 100 ether);

        flywheel.accrue(ERC20(address(gauge)), address(this));

        require(token.balanceOf(address(bribeRewards)) == 100 ether);

        flywheel.claimRewards(address(this));

        require(token.balanceOf(address(bribeRewards)) == 0);
        require(token.balanceOf(address(this)) == 100 ether);
    }

    function testAccrueAndClaimBribes(uint256 amount) external {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        FlywheelCore flywheel = createFlywheel(token);
        FlywheelBribeRewards bribeRewards = FlywheelBribeRewards(address(flywheel.flywheelRewards()));
        amount %= type(uint128).max;

        booster.optIn(ERC20(address(gauge)), flywheel);

        gaugeToken.mint(address(this), 100e18);
        gaugeToken.setMaxDelegates(1);
        gaugeToken.delegate(address(this));
        gaugeToken.incrementGauge(address(gauge), 100e18);

        hevm.warp(block.timestamp + WEEK); // skip to cycle 1

        token.mint(address(depot), amount);

        flywheel.accrue(ERC20(address(gauge)), address(this));

        require(token.balanceOf(address(bribeRewards)) == amount);

        flywheel.claimRewards(address(this));

        require(token.balanceOf(address(bribeRewards)) / 100 == 0);
        require(token.balanceOf(address(this)) / 100 == amount / 100);
        require(token.balanceOf(address(bribeRewards)) + token.balanceOf(address(this)) == amount);
    }

    function testAccrueAndClaimBribesTwoCycles() external {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        FlywheelCore flywheel = createFlywheel(token);
        FlywheelBribeRewards bribeRewards = FlywheelBribeRewards(address(flywheel.flywheelRewards()));

        booster.optIn(ERC20(address(gauge)), flywheel);

        gaugeToken.mint(address(this), 100e18);
        gaugeToken.setMaxDelegates(1);
        gaugeToken.delegate(address(this));
        gaugeToken.incrementGauge(address(gauge), 100e18);

        hevm.warp(block.timestamp + WEEK); // skip to cycle 1

        flywheel.accrue(ERC20(address(gauge)), address(this));
        token.mint(address(depot), 100 ether);

        require(token.balanceOf(address(bribeRewards)) == 0);

        hevm.warp(block.timestamp + WEEK); // skip to cycle 2

        flywheel.accrue(ERC20(address(gauge)), address(this));

        require(token.balanceOf(address(bribeRewards)) == 100 ether);

        flywheel.claimRewards(address(this));

        require(token.balanceOf(address(bribeRewards)) == 0);
        require(token.balanceOf(address(this)) == 100 ether);
    }

    function testAccrueAndClaimBribesTwoCycles(uint256 amount) external {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        FlywheelCore flywheel = createFlywheel(token);
        FlywheelBribeRewards bribeRewards = FlywheelBribeRewards(address(flywheel.flywheelRewards()));
        amount %= type(uint128).max;

        booster.optIn(ERC20(address(gauge)), flywheel);

        gaugeToken.mint(address(this), 100e18);
        gaugeToken.setMaxDelegates(1);
        gaugeToken.delegate(address(this));
        gaugeToken.incrementGauge(address(gauge), 100e18);

        hevm.warp(block.timestamp + WEEK); // skip to cycle 1

        flywheel.accrue(ERC20(address(gauge)), address(this));
        token.mint(address(depot), amount);

        require(token.balanceOf(address(bribeRewards)) == 0);

        hevm.warp(block.timestamp + WEEK); // skip to cycle 2

        flywheel.accrue(ERC20(address(gauge)), address(this));

        require(token.balanceOf(address(bribeRewards)) == amount);

        flywheel.claimRewards(address(this));

        require(token.balanceOf(address(bribeRewards)) / 100 == 0);
        require(token.balanceOf(address(this)) / 100 == amount / 100);
        require(token.balanceOf(address(bribeRewards)) + token.balanceOf(address(this)) == amount);
    }
}
