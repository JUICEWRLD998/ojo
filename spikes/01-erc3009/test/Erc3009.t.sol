// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Receiver} from "../src/Receiver.sol";

interface IToken {
    function name() external view returns (string memory);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function RECEIVE_WITH_AUTHORIZATION_TYPEHASH() external view returns (bytes32);
    function balanceOf(address) external view returns (uint256);
    function authorizationState(address, bytes32) external view returns (bool);
}

/// Spike 1: does a real signed ReceiveWithAuthorization move balance on AUSD and USDC?
/// Run: forge test --fork-url https://rpc.monad.xyz --fork-block-number 110755048 -vv
contract Erc3009Spike is Test {
    address constant AUSD = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;
    address constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;

    Receiver receiver;
    uint256 guestKey;
    address guest;

    function setUp() public {
        receiver = new Receiver();
        guestKey = uint256(keccak256("ojo spike guest"));
        guest = vm.addr(guestKey);
    }

    /// `deal` cannot find AUSD's balance slot (namespaced storage). Record the slot balanceOf reads, write it directly.
    function _fund(address token, address to, uint256 amount) internal {
        vm.record();
        IToken(token).balanceOf(to);
        (bytes32[] memory reads,) = vm.accesses(token);
        bytes32 slot = reads[reads.length - 1];
        // AUSD packs the balance above a one-byte field (readback was amount >> 8), so shift left to compensate.
        vm.store(token, slot, bytes32(token == 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a ? amount << 8 : amount));
        assertEq(IToken(token).balanceOf(to), amount, "fund failed");
    }

    function _domainReport(address token, string memory domainName, string memory version) internal view {
        bytes32 typeHash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 local = keccak256(
            abi.encode(typeHash, keccak256(bytes(domainName)), keccak256(bytes(version)), block.chainid, token)
        );
        bytes32 onchain = IToken(token).DOMAIN_SEPARATOR();
        console2.log("  eip712 name   :", domainName);
        console2.log("  eip712 version:", version);
        console2.log("  chainId       :", block.chainid);
        console2.log("  separator     :", vm.toString(onchain));
        console2.log("  matches local recompute:", local == onchain);
    }

    function _run(address token, string memory label, string memory domainName, string memory version) internal {
        console2.log(label);
        console2.log("  token         :", token);
        console2.log("  name()        :", IToken(token).name());
        _domainReport(token, domainName, version);

        uint256 value = 5e6; // 5 units, 6 decimals
        _fund(token, guest, 100e6);

        bytes32 nonce = keccak256(abi.encode(uint256(1), uint256(0), bytes32("Tunde Houston"), uint256(42)));
        uint256 validAfter = 0;
        uint256 validBefore = block.timestamp + 60;

        bytes32 structHash = keccak256(
            abi.encode(
                IToken(token).RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                guest,
                address(receiver),
                value,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IToken(token).DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guestKey, digest);

        uint256 g0 = IToken(token).balanceOf(guest);
        uint256 r0 = IToken(token).balanceOf(address(receiver));
        uint256 gasBefore = gasleft();
        receiver.pull(token, guest, value, validAfter, validBefore, nonce, v, r, s);
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(g0 - IToken(token).balanceOf(guest), value, "guest debited");
        assertEq(IToken(token).balanceOf(address(receiver)) - r0, value, "receiver credited");
        assertTrue(IToken(token).authorizationState(guest, nonce), "nonce consumed");
        console2.log("  pull gas (token call only):", gasUsed);

        // negative controls: replay and tampered signature must both revert
        vm.expectRevert();
        receiver.pull(token, guest, value, validAfter, validBefore, nonce, v, r, s);

        bytes32 nonce2 = keccak256("second");
        vm.expectRevert();
        receiver.pull(token, guest, value, validAfter, validBefore, nonce2, v, r, s); // sig is for nonce, not nonce2
        console2.log("  PASS: balance moved, replay reverts, wrong-nonce reverts");
    }

    function test_ausd() public {
        _run(AUSD, "AUSD", "Agora Dollar", "1");
    }

    function test_usdc() public {
        // USDC: name() is "USDC" but the EIP-712 domain name may differ. Report which candidate matches.
        bytes32 onchain = IToken(USDC).DOMAIN_SEPARATOR();
        bytes32 typeHash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        string[3] memory candidates = ["USDC", "USD Coin", "Circle USD Coin"];
        string memory found = "";
        for (uint256 i = 0; i < 3; i++) {
            bytes32 local = keccak256(
                abi.encode(typeHash, keccak256(bytes(candidates[i])), keccak256(bytes("2")), block.chainid, USDC)
            );
            if (local == onchain) found = candidates[i];
        }
        console2.log("USDC domain name that matches on-chain separator:", found);
        assertTrue(bytes(found).length > 0, "no candidate name matched");
        _run(USDC, "USDC", found, "2");
    }
}
