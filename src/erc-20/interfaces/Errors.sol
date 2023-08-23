// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.20;

/**
 * @title Shared Errors
 */
interface Errors {
    /// @notice thrown when attempting to approve an EOA that must be a contract
    error NonContractError();
}
