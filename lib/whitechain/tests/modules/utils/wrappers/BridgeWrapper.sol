// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import { IBridge } from "./../../../../main/modules/bridge/interfaces/IBridge.sol";

/**
 * @title BridgeWrapper
 * @author Whitechain
 * @notice Wrapper for calling bridge functions in tests or integrations.
 * Useful for interacting with the IBridge interface from external contracts.
 */
contract BridgeWrapper {
    /**
     * @notice Calls the withdrawGasAccumulated function from a given bridge contract.
     * This function assumes the bridgeAddress is a contract implementing IBridge.
     * @param bridgeAddress The address of the bridge contract.
     */
    function withdrawGasAccumulatedWrapper(address bridgeAddress) external {
        IBridge(bridgeAddress).withdrawGasAccumulated();
    }
}
