// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IArbitrumBranchPort, IBranchPort} from "./interfaces/IArbitrumBranchPort.sol";
import {IRootPort} from "./interfaces/IRootPort.sol";

import {BranchPort} from "./BranchPort.sol";

/// @title Arbitrum Branch Port Contract
contract ArbitrumBranchPort is BranchPort, IArbitrumBranchPort {
    using SafeTransferLib for address;

    /// @notice Local Network Identifier.
    uint24 public localChainId;

    /// @notice Address for Local Port Address where funds deposited from this chain are kept, managed and supplied to different Port Strategies.
    address public rootPortAddress;

    /**
     * @notice Constructor for Arbitrum Branch Port.
     * @param _owner owner of the contract.
     * @param _localChainId local chain id.
     * @param _rootPortAddress address of the Root Port.
     */
    constructor(uint24 _localChainId, address _rootPortAddress, address _owner) BranchPort(_owner) {
        require(_rootPortAddress != address(0), "Root Port Address cannot be 0");

        localChainId = _localChainId;
        rootPortAddress = _rootPortAddress;
    }

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    ///@inheritdoc IArbitrumBranchPort
    function depositToPort(address _depositor, address _recipient, address _underlyingAddress, uint256 _deposit)
        external
        lock
        requiresBridgeAgent
    {
        //Save root port address to memory
        address _rootPortAddress = rootPortAddress;

        //Get global token address from root port
        address _globalToken = IRootPort(_rootPortAddress).getLocalTokenFromUnderlying(_underlyingAddress, localChainId);

        //Check if global token exists
        if (_globalToken == address(0)) revert UnknownUnderlyingToken();

        //Deposit Assets to Port
        _underlyingAddress.safeTransferFrom(_depositor, address(this), _deposit);

        //Request Minting of Global Token
        IRootPort(_rootPortAddress).mintToLocalBranch(_recipient, _globalToken, _deposit);
    }

    ///@inheritdoc IArbitrumBranchPort
    function withdrawFromPort(address _depositor, address _recipient, address _globalAddress, uint256 _deposit)
        external
        lock
        requiresBridgeAgent
    {
        //Save root port address to memory
        address _rootPortAddress = rootPortAddress;

        //Check if global token exists
        if (!IRootPort(_rootPortAddress).isGlobalToken(_globalAddress, localChainId)) {
            revert UnknownToken();
        }

        //Get underlying token address from root port
        address underlyingAddress =
            IRootPort(_rootPortAddress).getUnderlyingTokenFromLocal(_globalAddress, localChainId);

        //Check if underlying token exists
        if (underlyingAddress == address(0)) revert UnknownUnderlyingToken();

        //Burn Global Token
        IRootPort(_rootPortAddress).burnFromLocalBranch(_depositor, _globalAddress, _deposit);

        //Withdraw Assets from Port
        underlyingAddress.safeTransfer(_recipient, _denormalizeDecimals(_deposit, ERC20(underlyingAddress).decimals()));
    }

    /// @inheritdoc IBranchPort
    function withdraw(address _recipient, address _underlyingAddress, uint256 _deposit)
        public
        override(IBranchPort, BranchPort)
        lock
        requiresBridgeAgent
    {
        _underlyingAddress.safeTransfer(
            _recipient, _denormalizeDecimals(_deposit, ERC20(_underlyingAddress).decimals())
        );
    }

    function _bridgeIn(address _recipient, address _localAddress, uint256 _amount) internal override {
        IRootPort(rootPortAddress).bridgeToLocalBranchFromRoot(_recipient, _localAddress, _amount);
    }

    function _bridgeOut(
        address _depositor,
        address _localAddress,
        address _underlyingAddress,
        uint256 _amount,
        uint256 _deposit
    ) internal override {
        if (_deposit > 0) {
            _underlyingAddress.safeTransferFrom(
                _depositor, address(this), _denormalizeDecimals(_deposit, ERC20(_underlyingAddress).decimals())
            );
        }
        if (_amount - _deposit > 0) {
            IRootPort(rootPortAddress).bridgeToRootFromLocalBranch(_depositor, _localAddress, _amount - _deposit);
        }
    }
}
