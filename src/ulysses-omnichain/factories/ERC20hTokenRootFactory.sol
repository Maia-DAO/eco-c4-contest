// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IERC20hTokenRootFactory, ERC20hTokenRoot} from "../interfaces/IERC20hTokenRootFactory.sol";

/// @title ERC20 hToken Root Factory Contract
contract ERC20hTokenRootFactory is Ownable, IERC20hTokenRootFactory {
    using SafeTransferLib for address;

    /// @notice Local Network Identifier.
    uint16 public immutable localChainId;

    /// @notice Root Port Address.
    address public immutable rootPortAddress;

    /// @notice Root Core Router Address, in charge of the addition of new tokens to the system.
    address public coreRootRouterAddress;

    /// @notice Array of all hTokens created.
    ERC20hTokenRoot[] public hTokens;

    /**
     * @notice Constructor for ERC20 hToken Contract
     *     @param _localChainId Local Network Identifier.
     *     @param _rootPortAddress Root Port Address
     */
    constructor(uint16 _localChainId, address _rootPortAddress) {
        require(_rootPortAddress != address(0), "Root Port Address cannot be 0");
        localChainId = _localChainId;
        rootPortAddress = _rootPortAddress;
        _initializeOwner(msg.sender);
    }

    function initialize(address _coreRouter) external onlyOwner {
        require(_coreRouter != address(0), "CoreRouter address cannot be 0");
        coreRootRouterAddress = _coreRouter;
        renounceOwnership();
    }

    /*///////////////////////////////////////////////////////////////
                            hTOKEN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Function to create a new hToken.
     * @param _name Name of the Token.
     * @param _symbol Symbol of the Token.
     */
    function createToken(string memory _name, string memory _symbol)
        external
        requiresCoreRouterOrPort
        returns (ERC20hTokenRoot newToken)
    {
        newToken = new ERC20hTokenRoot(
            localChainId,
            address(this),
            rootPortAddress,
            _name,
            _symbol
        );
        hTokens.push(newToken);
    }

    /*///////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @notice Modifier that verifies msg sender is the RootInterface Contract from Root Chain.
    modifier requiresCoreRouterOrPort() {
        if (msg.sender != coreRootRouterAddress) {
            if (msg.sender != rootPortAddress) {
                revert UnrecognizedCoreRouterOrPort();
            }
        }
        _;
    }
}
