// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {MockERC20Gauges} from "../erc-20/mocks/MockERC20Gauges.t.sol";
import {MockRewardsStream} from "../rewards/mocks/MockRewardsStream.sol";

import {BurntHermes} from "@hermes/BurntHermes.sol";
import {FlywheelBoosterGaugeWeight} from "@rewards/booster/FlywheelBoosterGaugeWeight.sol";
import {MultiRewardsDepot} from "@rewards/depots/MultiRewardsDepot.sol";
import {FlywheelCore, ERC20} from "@rewards/FlywheelCoreStrategy.sol";
import {FlywheelBribeRewards} from "@rewards/rewards/FlywheelBribeRewards.sol";
import {FlywheelGaugeRewards} from "@rewards/rewards/FlywheelGaugeRewards.sol";

import {UniswapV3Gauge} from "@gauges/UniswapV3Gauge.sol";

contract UniswapV3GaugeTest is DSTestPlus {
    MockERC20 public strategy;
    MockERC20 public rewardToken;
    MockERC20 public hermes;
    BurntHermes public bhermesToken;
    MockRewardsStream public rewardsStream;
    MultiRewardsDepot public depot;
    FlywheelBoosterGaugeWeight public booster;

    UniswapV3Gauge public gauge;

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

        bhermesToken = new BurntHermes(hermes, address(this), address(booster), 604800, 604800 / 7);
        bhermesToken.gaugeWeight().setMaxGauges(10);

        booster.transferOwnership(address(bhermesToken.gaugeWeight()));
        booster.bribesFactory().transferOwnership(address(bhermesToken.gaugeWeight()));

        hevm.mockCall(address(this), abi.encodeWithSignature("rewardToken()"), abi.encode(address(rewardToken)));
        hevm.mockCall(
            address(this), abi.encodeWithSignature("bribesFactory()"), abi.encode(address(booster.bribesFactory()))
        );
        hevm.mockCall(
            address(this), abi.encodeWithSignature("bHermesBoostToken()"), abi.encode(bhermesToken.gaugeBoost())
        );

        gauge = new UniswapV3Gauge(
            FlywheelGaugeRewards(address(this)),
            address(this),
            address(this),
            10,
            address(this)
        );

        depot = gauge.multiRewardsDepot();

        bhermesToken.gaugeWeight().addGauge(address(gauge));
    }

    function createFlywheel(MockERC20 token) private returns (FlywheelCore flywheel) {
        flywheel = booster.bribesFactory().addGaugetoFlywheel(address(gauge), address(token));
    }

    function createFlywheel() private returns (FlywheelCore flywheel) {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        flywheel = createFlywheel(token);
    }

    function setMinimumWidth() public {
        require(gauge.minimumWidth() == 10);
        gauge.setMinimumWidth(100);
        require(gauge.minimumWidth() == 100);
    }

    function testNewEpochFail() external {
        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(0));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", 0), "");

        uint256 epoch = gauge.epoch();
        gauge.newEpoch();
        assertEq(epoch, gauge.epoch());
    }

    function testNewEpochWorkThenFail() external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(0));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", 0), "");

        hevm.expectEmit(true, true, true, true);
        emit Distribute(0, WEEK);

        gauge.newEpoch();
        uint256 epoch = gauge.epoch();
        gauge.newEpoch();
        assertEq(epoch, gauge.epoch());
    }

    function testNewEpochEmpty() external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(0));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", 0), "");

        hevm.expectEmit(true, true, true, true);
        emit Distribute(0, WEEK);

        gauge.newEpoch();
    }

    function testNewEpoch() external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(100e18));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", 100e18), "");

        hevm.expectEmit(true, true, true, true);
        emit Distribute(100e18, WEEK);

        gauge.newEpoch();
    }

    function testNewEpoch(uint256 amount) external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(amount));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", amount), "");

        hevm.expectEmit(true, true, true, true);
        emit Distribute(amount, WEEK);

        gauge.newEpoch();
    }

    function testNewEpochTwice(uint256 amount) external {
        hevm.warp(WEEK); // skip to cycle 1

        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(amount));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", amount), "");

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

        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(amount));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", amount), "");

        hevm.expectEmit(true, true, true, true);
        emit Distribute(amount, WEEK);

        gauge.newEpoch();

        hevm.warp(2 * WEEK); // skip to cycle 2

        hevm.mockCall(address(this), abi.encodeWithSignature("getAccruedRewards()"), abi.encode(0));
        hevm.mockCall(address(this), abi.encodeWithSignature("createIncentiveFromGauge(uint256)", 0), "");

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

        require(token.balanceOf(address(bribeRewards)) == 0);

        hevm.warp(block.timestamp + 604800); // skip to next cycle

        flywheel.accrue(ERC20(address(gauge)), address(this));

        require(token.balanceOf(address(bribeRewards)) == 100 ether);
    }

    function testAccrueBribes(uint256 amount) external {
        MockERC20 token = new MockERC20("test token", "TKN", 18);
        FlywheelCore flywheel = createFlywheel(token);
        FlywheelBribeRewards bribeRewards = FlywheelBribeRewards(address(flywheel.flywheelRewards()));
        amount %= type(uint128).max;

        token.mint(address(depot), amount);

        booster.optIn(ERC20(address(gauge)), flywheel);

        require(token.balanceOf(address(bribeRewards)) == 0);

        hevm.warp(block.timestamp + 604800); // skip to next cycle

        flywheel.accrue(ERC20(address(gauge)), address(this));

        require(token.balanceOf(address(bribeRewards)) == amount);
    }
}
