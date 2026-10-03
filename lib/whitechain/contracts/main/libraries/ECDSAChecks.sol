// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import { ECDSAUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

/**
 * @title ECDSAChecks library
 * @author Whitechain
 * @notice Library providing functions for validating ECDSA signatures.
 * Utilizes OpenZeppelin's ECDSAUpgradeable library for signature verification.
 * Use this library to ensure that a given signature was produced by the expected signer
 * and to add additional safety checks for signature-based authorization.
 */
library ECDSAChecks {
    /**
     * Using the ECDSAUpgradeable library for working with digital signatures.
     */
    using ECDSAUpgradeable for bytes32;

    /**
     * @notice Struct for storing parameters of an ECDSA signature.
     * @param hash The message hash that was signed.
     * @param r The r-component of the ECDSA signature.
     * @param s The s-component of the ECDSA signature.
     * @param v The recovery byte of the ECDSA signature.
     */
    struct ECDSAParams {
        bytes32 hash;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /**
     * @notice Recovers the signer address from an ECDSA signature.
     * @param _ECDSAParams A struct containing the signature parameters.
     * @return signer The address of the signer.
     */
    function recoverSigner(ECDSAParams memory _ECDSAParams) internal pure returns (address signer) {
        bytes32 _messageHash = _ECDSAParams.hash.toEthSignedMessageHash();

        signer = _messageHash.recover({ v: _ECDSAParams.v, r: _ECDSAParams.r, s: _ECDSAParams.s });
    }
}
