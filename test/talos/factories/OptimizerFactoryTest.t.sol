// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import "../mocks/MockOptimizerFactory.sol";

error Unauthorized();

contract OptimizerFactoryTest is DSTestPlus {
    MockOptimizerFactory factory;

    function setUp() public {
        factory = new MockOptimizerFactory();
    }

    function testConstructor() public {
        assertEq(factory.getOptimizers().length, 1);
        assertEq(address(factory.optimizers(0)), address(0));
    }

    function testCreateTalosOptimizer(
        uint32 twapDuration,
        int24 maxTwapDeviation,
        int24 tickRangeMultiplier,
        uint24 priceImpactPercentage,
        uint256 maxTotalSupply,
        address owner,
        bytes32 salt
    ) public {
        hevm.assume(owner != address(0));
        hevm.assume(maxTwapDeviation >= 20);
        hevm.assume(twapDuration >= 100);
        hevm.assume(priceImpactPercentage < 1e6 && priceImpactPercentage != 0);
        hevm.assume(maxTotalSupply != 0);

        factory.createTalosOptimizer(
            twapDuration, maxTwapDeviation, tickRangeMultiplier, priceImpactPercentage, maxTotalSupply, owner, salt
        );

        assertEq(factory.optimizerIds(factory.optimizers(1)), 1);
    }

    function testGetOptimizers(
        uint32 twapDuration,
        int24 maxTwapDeviation,
        int24 tickRangeMultiplier,
        uint24 priceImpactPercentage,
        uint256 maxTotalSupply,
        address owner,
        bytes32 salt
    ) public {
        assertEq(factory.getOptimizers().length, 1);
        testCreateTalosOptimizer(
            twapDuration, maxTwapDeviation, tickRangeMultiplier, priceImpactPercentage, maxTotalSupply, owner, salt
        );
        assertEq(factory.getOptimizers().length, 2);
    }

    function testCreateBoostAggregatorIds(
        uint32 twapDuration,
        int24 maxTwapDeviation,
        int24 tickRangeMultiplier,
        uint24 priceImpactPercentage,
        uint256 maxTotalSupply,
        address owner,
        bytes32 salt,
        bytes32 salt2
    ) public {
        hevm.assume(owner != address(0));
        hevm.assume(salt != salt2);

        testCreateTalosOptimizer(
            twapDuration, maxTwapDeviation, tickRangeMultiplier, priceImpactPercentage, maxTotalSupply, owner, salt
        );
        testCreateTalosOptimizer(
            twapDuration, maxTwapDeviation, tickRangeMultiplier, priceImpactPercentage, maxTotalSupply, owner, salt2
        );

        TalosOptimizer optimizer = factory.optimizers(1);
        assertEq(factory.optimizerIds(optimizer), 1);
        assertEq(optimizer.owner(), owner);
        TalosOptimizer optimizer2 = factory.optimizers(2);
        assertEq(factory.optimizerIds(optimizer2), 2);
        assertEq(optimizer2.owner(), owner);
    }

    function testFailCreateBoostAggregator(
        uint32 twapDuration,
        int24 maxTwapDeviation,
        int24 tickRangeMultiplier,
        uint24 priceImpactPercentage,
        uint256 maxTotalSupply,
        address owner,
        bytes32 salt
    ) public {
        hevm.assume(owner != address(0));

        testCreateTalosOptimizer(
            twapDuration, maxTwapDeviation, tickRangeMultiplier, priceImpactPercentage, maxTotalSupply, owner, salt
        );
        testCreateTalosOptimizer(
            twapDuration, maxTwapDeviation, tickRangeMultiplier, priceImpactPercentage, maxTotalSupply, owner, salt
        );
    }
}
