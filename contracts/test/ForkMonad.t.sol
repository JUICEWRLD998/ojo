// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Helpers} from "./Helpers.sol";
import {OjoParty} from "../src/OjoParty.sol";
import {BundleDesk} from "../src/BundleDesk.sol";

interface IRealToken {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/// Phase 1 fork tests: the real AUSD and USDC on a pinned Monad mainnet fork.
contract ForkMonadTest is Helpers {
    address constant AUSD = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;
    address constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    uint256 constant FORK_BLOCK = 110755048;

    OjoParty party;
    BundleDesk desk;
    bytes32 partyDomain;

    uint256 hostKey = 0xA11CE;
    uint256 guestKey = 0xB0B;
    address host;
    address guest;
    address celebrant = address(0xC0FFEE);
    bytes32 constant ID = keccak256("fork-party");
    bytes32 constant LABEL = bytes32("Tunde Houston");

    function setUp() public {
        vm.createSelectFork("ojo_monad", FORK_BLOCK);
        assertEq(block.chainid, 143, "forked Monad mainnet");
        host = vm.addr(hostKey);
        guest = vm.addr(guestKey);
        party = new OjoParty(AUSD, USDC);
        desk = new BundleDesk(AUSD, USDC);
        partyDomain = _domain("OjoParty", "1", address(party));
    }

    /// `deal` cannot find AUSD's balance slot (namespaced storage), so write the slot balanceOf reads.
    /// AUSD packs the balance above a one-byte field (readback is amount >> 8), so shift left to compensate.
    function _fund(address token, address to, uint256 amount) internal {
        vm.record();
        IRealToken(token).balanceOf(to);
        (bytes32[] memory reads,) = vm.accesses(token);
        vm.store(token, reads[reads.length - 1], bytes32(token == AUSD ? amount << 8 : amount));
        assertEq(IRealToken(token).balanceOf(to), amount, "fund failed");
    }

    function _createParty(address token, uint16 mask) internal {
        address[] memory r = new address[](1);
        r[0] = celebrant;
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        bytes32 sh = keccak256(
            abi.encode(party.CREATE_PARTY_TYPEHASH(), ID, token, keccak256(abi.encodePacked(r)), closesAt, mask)
        );
        party.createParty(ID, host, token, r, closesAt, mask, _sig(hostKey, _digest(partyDomain, sh)));
    }

    function _auth3009(address token, uint8 idx, uint256 salt, uint256 value)
        internal
        view
        returns (OjoParty.Auth memory)
    {
        return _auth(
            AuthReq({
                key: guestKey,
                tokenDomain: IRealToken(token).DOMAIN_SEPARATOR(),
                to: address(party),
                value: value,
                validAfter: 0,
                validBefore: block.timestamp + 60,
                nonce: _nonce(ID, idx, LABEL, salt)
            })
        );
    }

    function _sprayOn(address token, string memory snapName) internal {
        _fund(token, guest, 500e6);
        _createParty(token, 0x7F);

        uint256 c0 = IRealToken(token).balanceOf(celebrant);
        // Setup above warmed these in the same test transaction. A real spray is its own transaction, so cool them:
        // the first-spray figure is what the relayer's gas limit must cover (token proxy implementation stays warm,
        // so keep a margin on top).
        uint256 total;
        uint256[3] memory vals = [uint256(1e6), 5e6, 20e6];
        OjoParty.Auth[3] memory auths; // built first: signing reads the token's domain and would re-warm it
        for (uint256 i = 0; i < 3; i++) {
            auths[i] = _auth3009(token, 0, i, vals[i]);
        }
        vm.cool(address(party));
        vm.cool(token);
        vm.cool(celebrant);
        vm.cool(guest);
        for (uint256 i = 0; i < 3; i++) {
            party.spray(ID, 0, LABEL, i, auths[i]);
            if (i == 0) vm.snapshotGasLastCall(string.concat(snapName, "_cold"));
            if (i == 2) vm.snapshotGasLastCall(string.concat(snapName, "_warm"));
            total += vals[i];
        }

        assertEq(IRealToken(token).balanceOf(celebrant) - c0, total, "celebrant received every note");
        assertEq(IRealToken(token).balanceOf(guest), 500e6 - total, "guest paid exactly");
        assertEq(IRealToken(token).balanceOf(address(party)), 0, "contract holds nothing");
        assertEq(party.getParty(ID).total, total);
    }

    function test_fork_spray_usdc() public {
        _sprayOn(USDC, "spray_usdc");
    }

    function test_fork_spray_ausd() public {
        _sprayOn(AUSD, "spray_ausd");
    }

    function test_fork_replayAndTamperRevertOnRealTokens() public {
        address[2] memory tokens = [USDC, AUSD];
        for (uint256 t = 0; t < 2; t++) {
            // Fresh party id per token so the two runs do not collide.
            _fund(tokens[t], guest, 100e6);
            address[] memory r = new address[](1);
            r[0] = celebrant;
            bytes32 pid = keccak256(abi.encode("p", t));
            uint64 closesAt = uint64(block.timestamp + 1 hours);
            bytes32 sh = keccak256(
                abi.encode(
                    party.CREATE_PARTY_TYPEHASH(),
                    pid,
                    tokens[t],
                    keccak256(abi.encodePacked(r)),
                    closesAt,
                    uint16(0x7F)
                )
            );
            party.createParty(pid, host, tokens[t], r, closesAt, 0x7F, _sig(hostKey, _digest(partyDomain, sh)));

            OjoParty.Auth memory a = _auth(
                AuthReq({
                    key: guestKey,
                    tokenDomain: IRealToken(tokens[t]).DOMAIN_SEPARATOR(),
                    to: address(party),
                    value: 1e6,
                    validAfter: 0,
                    validBefore: block.timestamp + 60,
                    nonce: _nonce(pid, 0, LABEL, 1)
                })
            );
            party.spray(pid, 0, LABEL, 1, a);

            vm.expectRevert(); // replay
            party.spray(pid, 0, LABEL, 1, a);

            vm.expectRevert(); // relayer swaps the label
            party.spray(pid, 0, bytes32("Impostor"), 1, a);

            OjoParty.Auth memory b = a;
            b.s = bytes32(uint256(b.s) ^ 1);
            vm.expectRevert(); // tampered signature on a fresh salt
            party.spray(pid, 0, LABEL, 2, b);
        }
    }

    function test_fork_bundleDesk_depositAndClaim() public {
        address vendor = vm.addr(0x7E4D);
        uint256 voucherKey = 0x70C;
        address voucher = vm.addr(voucherKey);
        address recipient = address(0x6E57);
        address[2] memory tokens = [USDC, AUSD];

        for (uint256 t = 0; t < 2; t++) {
            address token = tokens[t];
            _fund(token, vendor, 100e6);
            vm.startPrank(vendor);
            IRealToken(token).approve(address(desk), type(uint256).max);
            desk.deposit(token, 100e6);
            vm.stopPrank();
            assertEq(desk.balanceOf(vendor, token), 100e6);

            uint256 expiry = block.timestamp + 1 days;
            bytes32 vDigest = _digest(
                _domain("BundleDesk", "1", address(desk)),
                keccak256(abi.encode(desk.VOUCHER_TYPEHASH(), vendor, token, 25e6, voucher, expiry))
            );
            bytes memory vs = _sig(0x7E4D, vDigest);
            bytes memory cs = _sig(
                voucherKey,
                _digest(
                    _domain("BundleDesk", "1", address(desk)),
                    keccak256(abi.encode(desk.CLAIM_TYPEHASH(), vDigest, recipient))
                )
            );

            uint256 r0 = IRealToken(token).balanceOf(recipient);
            desk.claim(vendor, token, 25e6, voucher, expiry, recipient, vs, cs);
            assertEq(IRealToken(token).balanceOf(recipient) - r0, 25e6);
            assertEq(IRealToken(token).balanceOf(address(desk)), desk.balanceOf(vendor, token), "ledger equals tokens");

            vm.expectRevert(BundleDesk.AlreadyClaimed.selector);
            desk.claim(vendor, token, 25e6, voucher, expiry, recipient, vs, cs);

            vm.prank(vendor);
            desk.withdraw(token, 75e6);
            assertEq(IRealToken(token).balanceOf(address(desk)), 0);
        }
    }
}
