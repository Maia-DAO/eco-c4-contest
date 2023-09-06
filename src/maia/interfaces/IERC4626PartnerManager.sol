// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BurntHermes} from "@hermes/BurntHermes.sol";

import {PartnerManagerFactory} from "../factories/PartnerManagerFactory.sol";

/**
 * @title Yield bearing, boosting, voting, and gauge enabled Partner Token
 * @author Maia DAO (https://github.com/Maia-DAO)
 * @notice Partner Manager is an ERC-4626 compliant Partner token which:
 *          distributes BurntHermes utility tokens (Weight, Boost, Governance)
 *          in exchange for staking Partner tokens.
 */
interface IERC4626PartnerManager {
    /*//////////////////////////////////////////////////////////////
                         PARTNER MANAGER STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The partner manager factory.
    function factory() external view returns (PartnerManagerFactory);

    /// @notice The BurntHermes token.
    function bHermes() external view returns (BurntHermes);

    /// @notice The BurntHermes rate is used to determine how much hermes
    ///         can be claimed by one share.
    function bHermesRate() external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                            UTILITY MANAGER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the BurntHermes underlying balance.
    /// @dev Claims all outstanding underlying BurntHermes utility tokens for this contract.
    function updateUnderlyingBalance() external;

    /// @notice Claims all outstanding underlying BurntHermes utility tokens for msg.sender.
    function claimOutstanding() external;

    /*///////////////////////////////////////////////////////////////
                             MIGRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Migrates assets to new Partner Vault.
     * @dev Must be a Vault recognized by PartnerManagerFactory.
     * @param newPartnerVault destination Partner Vault.
     */
    function migratePartnerVault(address newPartnerVault) external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows owner to raise the conversion rate used for deposit.
     *         Conversion rate can only be raised. Sets the ratio
     *         between pbHermes<>BurntHermes. If the ratio is 1 it means that
     *         1 $pbHermes has 1 $BurntHermes worth of voting power.
     * @param newRate new BurntHermes to pbHermes conversion rate. represents
     *                   the value that correlates partnerToken with BurntHermes voting power.
     * @dev Maximum increase of conversion rate up to:
     *         `bHermesToken.balanceOf(address(this)).divWad(_totalSupply)`.
     */
    function increaseConversionRate(uint256 newRate) external;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a user's rewards accrue to a given strategy.
     *   @param user the user of the rewards
     *   @param rewardsDelta how many new rewards accrued to the user
     *   @param rewardsIndex market index for rewards per token accrued
     */
    event AccrueRewards(address indexed user, uint256 indexed rewardsDelta, uint256 indexed rewardsIndex);

    /**
     *   @notice Emitted when a user claims accrued rewards.
     *   @param user the user of the rewards
     *   @param amount the amount of rewards claimed
     */
    event ClaimRewards(address indexed user, uint256 indexed amount);

    /**
     *   @notice Emitted when a partner vault is migrated.
     *   @param oldPartnerVault the old partner vault
     *   @param newPartnerVault the new partner vault
     */
    event MigratePartnerVault(address indexed oldPartnerVault, address indexed newPartnerVault);

    /*///////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev throws when trying to migrate to an invalid partner vault.
    error UnrecognizedVault();

    /// @dev throws when trying to migrate to a new vault with funds still in the old vault.
    error UserFundsExistInOldVault();

    /// @dev throws when trying to new bHermesRate is smaller than the last one.
    error InvalidRate();

    /// @dev throws when trying to increase bHermesRate to an invalid value.
    error InsufficientBacking();

    /// @dev throws when a user does not have not enough claimed balance for transfer.
    error InsufficientUnderlying();

    /// @dev throws when trying to mint more than the contract can support.
    error ExceedsMaxDeposit();
}
