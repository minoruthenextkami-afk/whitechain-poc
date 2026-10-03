// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import { ECDSAChecks } from "../../../../main/libraries/ECDSAChecks.sol";

/**
 * @title ECDSAChecksWrapper
 * @author Whitechain
 * @notice A simple wrapper contract that exposes ECDSA signature validation via the ECDSAChecks library.
 * Uses the ECDSAChecks library to validate signatures passed in through the ECDSAParams struct.
 */
contract ECDSAChecksWrapper {
    /**
     * @notice Attach the ECDSAChecks library to the ECDSAParams type for extended functionality.
     */
    using ECDSAChecks for ECDSAChecks.ECDSAParams;

    /**
     * @notice Recovers the signer address from an ECDSA signature.
     * @param params A struct containing the signature parameters.
     * @return signer The address of the signer.
     */
    function recoverSignerWrapper(ECDSAChecks.ECDSAParams calldata params) external pure returns (address signer) {
        return ECDSAChecks.recoverSigner(params);
    }
}
