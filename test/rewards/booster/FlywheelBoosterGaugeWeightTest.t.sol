// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Ownable} from "solady/auth/Ownable.sol";

import {
    bHermesGauges,
    FlywheelBoosterGaugeWeight,
    IFlywheelBooster
} from "@rewards/booster/FlywheelBoosterGaugeWeight.sol";
import {MultiRewardsDepot} from "@rewards/depots/MultiRewardsDepot.sol";
import {FlywheelCore, ERC20} from "@rewards/FlywheelCoreStrategy.sol";

contract FlywheelBoosterGaugeWeightTest is DSTestPlus {
    FlywheelBoosterGaugeWeight public booster;
    bHermesGauges public gaugeToken;

    ERC20 gauge1 = ERC20(address(1));
    ERC20 gauge2 = ERC20(address(2));
    ERC20 gauge3 = ERC20(address(3));
    ERC20 gauge4 = ERC20(address(4));
    ERC20 gauge5 = ERC20(address(5));

    MultiRewardsDepot public multiRewardsDepot1;
    MultiRewardsDepot public multiRewardsDepot2;
    MultiRewardsDepot public multiRewardsDepot3;
    MultiRewardsDepot public multiRewardsDepot4;
    MultiRewardsDepot public multiRewardsDepot5;

    function setUp() public {
        booster = new FlywheelBoosterGaugeWeight(1 weeks);

        gaugeToken = new bHermesGauges(address(this), address(booster), 1 weeks, 1 days);
        gaugeToken.setMaxGauges(5);

        booster.transferOwnership(address(gaugeToken));
        booster.bribesFactory().transferOwnership(address(gaugeToken));

        multiRewardsDepot1 = addGauge(address(gauge1));
        multiRewardsDepot2 = addGauge(address(gauge2));
        multiRewardsDepot3 = addGauge(address(gauge3));
        multiRewardsDepot4 = addGauge(address(gauge4));
        multiRewardsDepot5 = addGauge(address(gauge5));
    }

    function addGauge(address gauge) private returns (MultiRewardsDepot depot) {
        gaugeToken.addGauge(gauge);
        depot = new MultiRewardsDepot(address(booster.bribesFactory()));

        hevm.mockCall(address(gauge), abi.encodeWithSignature("multiRewardsDepot()"), abi.encode(depot));
    }

    function createFlywheel(ERC20 gauge) private returns (FlywheelCore flywheel) {
        MockERC20 token = new MockERC20("test_ token", "TKN", 18);
        flywheel = booster.bribesFactory().addGaugetoFlywheel(address(gauge), address(token));
    }

    function test_Owner() public {
        assertEq(booster.owner(), address(gaugeToken));
    }

    function test_OptIn() public returns (FlywheelCore flywheel) {
        flywheel = createFlywheel(gauge1);
        booster.optIn(gauge1, flywheel);

        uint256 id = booster.userGaugeflywheelId(address(this), gauge1, flywheel);
        assertGt(id, 0);
        assertEq(address(booster.userGaugeFlywheels(address(this), gauge1, id - 1)), address(flywheel));
    }

    function test_OptIn_AlreadyOptedIn() public {
        FlywheelCore flywheel = test_OptIn();

        hevm.expectRevert(IFlywheelBooster.AlreadyOptedIn.selector);
        booster.optIn(gauge1, flywheel);
    }

    function test_OptIn_InvalidGauge(ERC20 gauge) public {
        if (gauge <= gauge5) gauge = ERC20(address(0));
        FlywheelCore flywheel = createFlywheel(gauge1);

        hevm.expectRevert(IFlywheelBooster.InvalidGauge.selector);
        booster.optIn(gauge, flywheel);
    }

    function test_OptIn_InvalidFlywheel(FlywheelCore flywheel) public {
        hevm.expectRevert(IFlywheelBooster.InvalidFlywheel.selector);
        booster.optIn(gauge1, flywheel);
    }

    function test_OptOut() public {
        FlywheelCore flywheel = test_OptIn();

        booster.optOut(gauge1, flywheel);
        assertEq(booster.userGaugeflywheelId(address(this), gauge1, flywheel), 0);
    }

    function test_OptOut_NotOptedIn(ERC20 gauge, FlywheelCore flywheel) public {
        hevm.expectRevert(IFlywheelBooster.NotOptedIn.selector);
        booster.optOut(gauge, flywheel);
    }

    function test_accrueBribesPositiveDelta_Unauthorized() public {
        hevm.expectRevert(Ownable.Unauthorized.selector);
        booster.accrueBribesPositiveDelta(address(this), gauge1, 0);
    }

    function test_accrueBribesNegativeDelta_Unauthorized() public {
        hevm.expectRevert(Ownable.Unauthorized.selector);
        booster.accrueBribesNegativeDelta(address(this), gauge1, 0);
    }
}
