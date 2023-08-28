// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {vMaia, PartnerManagerFactory, ERC20} from "@maia/vMaia.sol";
import {IBaseVault} from "@maia/interfaces/IBaseVault.sol";
import {IERC4626PartnerManager} from "@maia/interfaces/IERC4626PartnerManager.sol";
import {MockVault} from "./mock/MockVault.t.sol";

import {bHermes} from "@hermes/bHermes.sol";
import {IUtilityManager} from "@hermes/interfaces/IUtilityManager.sol";

import {DateTimeLib} from "solady/utils/DateTimeLib.sol";

import {console2} from "forge-std/console2.sol";

contract vMaiaTest is DSTestPlus {
    MockVault vault;

    MockERC20 public hermes;

    MockERC20 public maia;

    vMaia public vmaia;

    uint256 bHermesRate;

    bHermes public bhermes;

    function setUp() public {
        //1 jan 2023
        hevm.warp(1672531200);

        hermes = new MockERC20("test hermes", "RTKN", 18);
        maia = new MockERC20("test maia", "tMAIA", 18);

        bhermes = new bHermes(hermes, address(this), address(this), 1 weeks, 1 days / 2);

        bHermesRate = 1 ether;

        vmaia = new vMaia(
            PartnerManagerFactory(address(this)),
            bHermesRate,
            maia,
            "vote Maia",
            "vMAIA",
            address(bhermes),
            address(vault),
            address(this) // set owner to allow call to 'increaseConversionRate'
        );
    }

    function getFirstDayOfNextMonthUnix() private view returns (uint256) {
        (uint256 currentYear, uint256 currentMonth,) = DateTimeLib.epochDayToDate(block.timestamp / 86400);

        uint256 nextMonth = currentMonth + 1;

        if (nextMonth > 12) {
            nextMonth = 1;
            currentYear++;
        }

        console2.log(currentYear, nextMonth);

        return DateTimeLib.nthWeekdayInMonthOfYearTimestamp(currentYear, nextMonth, 1, 1) + 1 days + 1;
    }

    function testDepositMaia() public {
        assertEq(vmaia.bHermesRate(), bHermesRate);

        uint256 amount = 100 ether;

        hermes.mint(address(this), 1000 ether);
        hermes.approve(address(bhermes), 1000 ether);
        bhermes.deposit(1000 ether, address(this));

        bhermes.transfer(address(vmaia), 1000 ether);

        maia.mint(address(this), amount);
        maia.approve(address(vmaia), amount);

        vmaia.deposit(amount, address(this));

        assertEq(maia.balanceOf(address(vmaia)), amount);
        assertEq(vmaia.balanceOf(address(this)), amount);
    }

    function testDepositMaiaPartnerGovernanceSupply() public {
        testDepositMaia();
        uint256 amount = vmaia.balanceOf(address(this));
        maia.approve(address(vmaia), type(uint256).max);

        // fast-forward to withdrawal Tuesday
        hevm.warp(getFirstDayOfNextMonthUnix());

        for (uint256 i = 0; i < 10; i++) {
            // Assert that the partner governance supply is equal to vMaia total supply
            assertEq(vmaia.totalSupply(), vmaia.partnerGovernance().totalSupply());

            // dilute pbHermes by withdraw & deposit cycle
            vmaia.withdraw(amount, address(this), address(this));
            vmaia.deposit(amount, address(this));
        }
    }

    function testDepositMaiaAmountFail() public {
        assertEq(vmaia.bHermesRate(), bHermesRate);

        uint256 amount = 100 ether;

        maia.mint(address(this), amount);
        maia.approve(address(vmaia), amount);

        hevm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        vmaia.deposit(101 ether, address(this));
    }

    function testWithdrawMaia() public {
        testDepositMaia();

        uint256 amount = 100 ether;

        hevm.warp(getFirstDayOfNextMonthUnix());

        vmaia.withdraw(amount, address(this), address(this));

        assertEq(maia.balanceOf(address(vmaia)), 0);
        assertEq(vmaia.balanceOf(address(this)), 0);
    }

    function testWithdrawMaiaPeriodFail() public {
        testDepositMaia();

        uint256 amount = 100 ether;

        hevm.expectRevert(abi.encodeWithSignature("UnstakePeriodNotLive()"));
        vmaia.withdraw(amount, address(this), address(this));
    }

    function testWithdrawMaiaOverPeriodFail() public {
        testDepositMaia();

        uint256 amount = 100 ether;

        hevm.warp(getFirstDayOfNextMonthUnix() + 1 days);

        hevm.expectRevert(abi.encodeWithSignature("UnstakePeriodNotLive()"));
        vmaia.withdraw(amount, address(this), address(this));
    }

    function increaseConversionRate(uint256 newRate, bool deposit) private {
        if (deposit) testDepositMaia();

        bool shouldPass = true;
        if (newRate <= vmaia.bHermesRate()) {
            shouldPass = false;
            hevm.expectRevert(IERC4626PartnerManager.InvalidRate.selector);
        } else if (
            vmaia.totalSupply() > 0 && newRate > (bhermes.balanceOf(address(vmaia)) / vmaia.totalSupply()) * 1 ether
        ) {
            shouldPass = false;
            hevm.expectRevert(IERC4626PartnerManager.InsufficientBacking.selector);
        }

        vmaia.increaseConversionRate(newRate);

        if (shouldPass) {
            assertEq(vmaia.bHermesRate(), newRate);
            bHermesRate = newRate;
        }
    }

    function testIncreaseConversionRate(uint256 newRate) public {
        // totalSupply can't be zero
        increaseConversionRate(newRate, true);
    }

    function testClaimAfterIncreaseConversionRate() public {
        increaseConversionRate(1.2 ether, true);

        vmaia.totalSupply();

        vmaia.gaugeWeight().approve(address(vmaia), type(uint256).max);
        vmaia.governance().approve(address(vmaia), type(uint256).max);
        vmaia.partnerGovernance().approve(address(vmaia), type(uint256).max);

        uint256 amount = 100 ether;
        uint256 expect = amount * bHermesRate / 1 ether;

        // claim Weight
        vmaia.claimWeight(expect);
        assertEq(expect, ERC20(vmaia.gaugeWeight()).balanceOf(address(this)));

        // claim Governance
        vmaia.claimGovernance(expect);
        assertEq(expect, ERC20(vmaia.governance()).balanceOf(address(this)));

        // claim PartnerGovernance
        vmaia.claimPartnerGovernance(expect);
        assertEq(expect, ERC20(vmaia.partnerGovernance()).balanceOf(address(this)));
    }

    function testDepositMaiaClaim() public {
        increaseConversionRate(2, true);

        vmaia.claimOutstanding();

        // got utility tokens as expected
        assertGt(vmaia.bHermesToken().gaugeWeight().balanceOf(address(this)), 0);
        assertGt(vmaia.bHermesToken().governance().balanceOf(address(this)), 0);
        assertGt(vmaia.partnerGovernance().balanceOf(address(this)), 0);

        vmaia.gaugeWeight().approve(address(vmaia), type(uint256).max);
        vmaia.governance().approve(address(vmaia), type(uint256).max);
        vmaia.partnerGovernance().approve(address(vmaia), type(uint256).max);

        vmaia.forfeitOutstanding();

        assertEq(vmaia.bHermesToken().gaugeWeight().balanceOf(address(this)), 0);
        assertEq(vmaia.bHermesToken().governance().balanceOf(address(this)), 0);
        assertEq(vmaia.partnerGovernance().balanceOf(address(this)), 0);
    }
}
