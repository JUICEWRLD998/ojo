// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OjoParty} from "../src/OjoParty.sol";

/// EIP-712 and ERC-3009 signing helpers shared by every test file.
abstract contract Helpers is Test {
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant RWA_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    struct AuthReq {
        uint256 key;
        bytes32 tokenDomain;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
    }

    function _domain(string memory name, string memory version, address verifying) internal view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, verifying)
        );
    }

    function _digest(bytes32 domainSep, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
    }

    function _sig(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// The nonce OjoParty demands: it binds party, recipient and label into the guest's own signature.
    function _nonce(bytes32 id, uint8 idx, bytes32 label, uint256 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, idx, label, salt));
    }

    function _auth(AuthReq memory q) internal pure returns (OjoParty.Auth memory a) {
        address from = vm.addr(q.key);
        bytes32 structHash =
            keccak256(abi.encode(RWA_TYPEHASH, from, q.to, q.value, q.validAfter, q.validBefore, q.nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(q.key, _digest(q.tokenDomain, structHash));
        a = OjoParty.Auth({
            from: from, value: q.value, validAfter: q.validAfter, validBefore: q.validBefore, v: v, r: r, s: s
        });
    }
}
