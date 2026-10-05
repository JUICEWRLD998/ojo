// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// The one ERC-3009 function Òjò uses. `receiveWithAuthorization` (not `transferWithAuthorization`)
/// requires msg.sender == to, so a signed authorization cannot be front-run straight into the token.
interface IERC3009 {
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
