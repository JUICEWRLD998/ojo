// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Helpers} from "./Helpers.sol";
import {OjoParty} from "../src/OjoParty.sol";
import {MockERC3009} from "./mocks/MockERC3009.sol";

contract OjoPartyTest is Helpers {
    MockERC3009 usdc;
    MockERC3009 ausd;
    OjoParty party;

    uint256 hostKey = 0xA11CE;
    uint256 guestKey = 0xB0B;
    address host;
    address guest;
    address celebrant = address(0xC0FFEE);
    address bride = address(0xB21DE);
    address groom = address(0x620011);

    bytes32 constant ID = keccak256("party-1");
    bytes32 constant ID2 = keccak256("party-2");
    bytes32 constant LABEL = bytes32("Tunde Houston");
    uint16 constant ALL = 0x7F;
    uint256[7] notes = [uint256(1e6), 2e6, 5e6, 10e6, 20e6, 50e6, 100e6];

    bytes32 partyDomain;
    bytes32 usdcDomain;

    event PartyCreated(bytes32 indexed id, address indexed host, address token, address[] recipients, uint64 closesAt);
    event Sprayed(
        bytes32 indexed id, address indexed from, address indexed recipient, uint256 value, bytes32 label, bytes32 nonce
    );
    event PartyClosed(bytes32 indexed id, uint256 total);

    function setUp() public {
        vm.warp(1_000_000);
        host = vm.addr(hostKey);
        guest = vm.addr(guestKey);
        usdc = new MockERC3009("USD Coin");
        ausd = new MockERC3009("Agora Dollar");
        party = new OjoParty(address(ausd), address(usdc));
        partyDomain = _domain("OjoParty", "1", address(party));
        usdcDomain = usdc.DOMAIN_SEPARATOR();
        usdc.mint(guest, 100_000e6);
        ausd.mint(guest, 100_000e6);
    }

    // ---------- helpers ----------

    function _recips(uint256 n) internal view returns (address[] memory r) {
        address[3] memory all = [celebrant, bride, groom];
        r = new address[](n);
        for (uint256 i = 0; i < n; i++) r[i] = all[i];
    }

    function _createSig(bytes32 id, address token, address[] memory recips, uint64 closesAt, uint16 mask, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        bytes32 sh = keccak256(
            abi.encode(
                party.CREATE_PARTY_TYPEHASH(), id, token, keccak256(abi.encodePacked(recips)), closesAt, mask
            )
        );
        return _sig(key, _digest(partyDomain, sh));
    }

    function _create(bytes32 id, address token, address[] memory recips, uint64 closesAt, uint16 mask) internal {
        party.createParty(id, host, token, recips, closesAt, mask, _createSig(id, token, recips, closesAt, mask, hostKey));
    }

    function _defaultParty(bytes32 id, uint256 nRecips) internal returns (uint64 closesAt) {
        closesAt = uint64(block.timestamp + 1 hours);
        _create(id, address(usdc), _recips(nRecips), closesAt, ALL);
    }

    function _mkAuth(bytes32 id, uint8 idx, bytes32 label, uint256 salt, uint256 value)
        internal
        view
        returns (OjoParty.Auth memory)
    {
        return _auth(
            AuthReq({
                key: guestKey,
                tokenDomain: usdcDomain,
                to: address(party),
                value: value,
                validAfter: 0,
                validBefore: block.timestamp + 60,
                nonce: _nonce(id, idx, label, salt)
            })
        );
    }

    function _closeSig(bytes32 id, uint256 key) internal view returns (bytes memory) {
        return _sig(key, _digest(partyDomain, keccak256(abi.encode(party.CLOSE_PARTY_TYPEHASH(), id))));
    }

    // ---------- createParty ----------

    function test_createParty_storesAndEmits() public {
        address[] memory r = _recips(3);
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        vm.expectEmit(true, true, false, true);
        emit PartyCreated(ID, host, address(usdc), r, closesAt);
        _create(ID, address(usdc), r, closesAt, ALL);

        OjoParty.Party memory p = party.getParty(ID);
        assertEq(p.host, host, "host is the signer");
        assertEq(p.token, address(usdc));
        assertEq(p.closesAt, closesAt);
        assertEq(p.noteMask, ALL);
        assertFalse(p.closed);
        assertEq(p.total, 0);
        assertEq(p.recipients.length, 3);
        assertEq(p.recipients[2], groom);
    }

    function test_createParty_duplicateIdReverts() public {
        _defaultParty(ID, 1);
        address[] memory r = _recips(1);
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        bytes memory sig = _createSig(ID, address(usdc), r, closesAt, ALL, hostKey);
        vm.expectRevert(OjoParty.PartyExists.selector);
        party.createParty(ID, host, address(usdc), r, closesAt, ALL, sig);
    }

    function test_createParty_unsupportedTokenReverts() public {
        address[] memory r = _recips(1);
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        address evil = address(0xDEAD);
        bytes memory sig = _createSig(ID, evil, r, closesAt, ALL, hostKey);
        vm.expectRevert(OjoParty.UnsupportedToken.selector);
        party.createParty(ID, host, evil, r, closesAt, ALL, sig);
    }

    function test_createParty_recipientBoundsRevert() public {
        uint64 closesAt = uint64(block.timestamp + 1 hours);

        address[] memory none = new address[](0);
        bytes memory s0 = _createSig(ID, address(usdc), none, closesAt, ALL, hostKey);
        vm.expectRevert(OjoParty.NoRecipients.selector);
        party.createParty(ID, host, address(usdc), none, closesAt, ALL, s0);

        address[] memory nine = new address[](9);
        for (uint256 i = 0; i < 9; i++) nine[i] = address(uint160(0x1000 + i));
        bytes memory s9 = _createSig(ID, address(usdc), nine, closesAt, ALL, hostKey);
        vm.expectRevert(OjoParty.TooManyRecipients.selector);
        party.createParty(ID, host, address(usdc), nine, closesAt, ALL, s9);

        address[] memory withZero = _recips(2);
        withZero[1] = address(0);
        bytes memory sz = _createSig(ID, address(usdc), withZero, closesAt, ALL, hostKey);
        vm.expectRevert(OjoParty.ZeroRecipient.selector);
        party.createParty(ID, host, address(usdc), withZero, closesAt, ALL, sz);
    }

    function test_createParty_badClosesAtReverts() public {
        address[] memory r = _recips(1);
        uint64 now_ = uint64(block.timestamp);
        bytes memory sig = _createSig(ID, address(usdc), r, now_, ALL, hostKey);
        vm.expectRevert(OjoParty.BadClosesAt.selector);
        party.createParty(ID, host, address(usdc), r, now_, ALL, sig);
    }

    function test_createParty_badNoteMaskReverts() public {
        address[] memory r = _recips(1);
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        bytes memory s0 = _createSig(ID, address(usdc), r, closesAt, 0, hostKey);
        vm.expectRevert(OjoParty.BadNoteMask.selector);
        party.createParty(ID, host, address(usdc), r, closesAt, 0, s0);

        bytes memory s1 = _createSig(ID, address(usdc), r, closesAt, 0x80, hostKey);
        vm.expectRevert(OjoParty.BadNoteMask.selector);
        party.createParty(ID, host, address(usdc), r, closesAt, 0x80, s1);
    }

    function test_createParty_sigBindsEveryField() public {
        // A relayer that alters any field after the host signed must fail: the signature no longer recovers to host.
        address[] memory r = _recips(1);
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        bytes memory sig = _createSig(ID, address(usdc), r, closesAt, ALL, hostKey);

        vm.expectRevert(OjoParty.BadHostSig.selector);
        party.createParty(ID, host, address(ausd), r, closesAt, ALL, sig); // token swapped

        vm.expectRevert(OjoParty.BadHostSig.selector);
        party.createParty(ID, host, address(usdc), r, closesAt + 1, ALL, sig); // closesAt moved

        vm.expectRevert(OjoParty.BadHostSig.selector);
        party.createParty(ID, host, address(usdc), r, closesAt, 0x01, sig); // mask narrowed

        vm.expectRevert(OjoParty.BadHostSig.selector);
        party.createParty(ID2, host, address(usdc), r, closesAt, ALL, sig); // id swapped

        address[] memory other = _recips(1);
        other[0] = address(0xBAD); // recipient swapped
        vm.expectRevert(OjoParty.BadHostSig.selector);
        party.createParty(ID, host, address(usdc), other, closesAt, ALL, sig);
    }

    function test_createParty_cannotSquatAnId() public {
        // Attacker front-runs with their own key and the victim's id: rejected, so the id stays free for the host.
        address[] memory r = _recips(1);
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        bytes memory attackerSig = _createSig(ID, address(usdc), r, closesAt, ALL, guestKey);
        vm.expectRevert(OjoParty.BadHostSig.selector);
        party.createParty(ID, host, address(usdc), r, closesAt, ALL, attackerSig);
        _create(ID, address(usdc), r, closesAt, ALL); // honest host still succeeds
        assertEq(party.getParty(ID).host, host);
    }

    function test_createParty_zeroHostReverts() public {
        address[] memory r = _recips(1);
        uint64 closesAt = uint64(block.timestamp + 1 hours);
        bytes memory sig = _createSig(ID, address(usdc), r, closesAt, ALL, hostKey);
        vm.expectRevert(OjoParty.BadHostSig.selector);
        party.createParty(ID, address(0), address(usdc), r, closesAt, ALL, sig);
    }

    // ---------- spray ----------

    function test_spray_movesFundsAndHoldsNothing() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 42, 5e6);
        vm.expectEmit(true, true, true, true);
        emit Sprayed(ID, guest, celebrant, 5e6, LABEL, _nonce(ID, 0, LABEL, 42));
        party.spray(ID, 0, LABEL, 42, a);

        assertEq(usdc.balanceOf(celebrant), 5e6);
        assertEq(usdc.balanceOf(guest), 100_000e6 - 5e6);
        assertEq(usdc.balanceOf(address(party)), 0, "contract never holds funds");
        assertEq(party.getParty(ID).total, 5e6);
    }

    function testFuzz_spray_conservation(uint256 seed) public {
        _defaultParty(ID, 3);
        uint256 n = 1 + (seed % 12);
        uint256 sum;
        for (uint256 i = 0; i < n; i++) {
            uint256 h = uint256(keccak256(abi.encode(seed, i)));
            uint256 value = notes[h % 7];
            uint8 idx = uint8((h >> 8) % 3);
            party.spray(ID, idx, LABEL, i, _mkAuth(ID, idx, LABEL, i, value));
            sum += value;
        }
        assertEq(usdc.balanceOf(celebrant) + usdc.balanceOf(bride) + usdc.balanceOf(groom), sum, "recipients got every note");
        assertEq(usdc.balanceOf(guest), 100_000e6 - sum, "guest paid exactly the notes");
        assertEq(usdc.balanceOf(address(party)), 0, "contract balance stays 0");
        assertEq(party.getParty(ID).total, sum, "total tracks notes");
    }

    function test_spray_replayReverts() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        party.spray(ID, 0, LABEL, 1, a);
        vm.expectRevert(bytes("authorization is used"));
        party.spray(ID, 0, LABEL, 1, a);
    }

    function test_spray_tamperedSignatureReverts() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        a.r = bytes32(uint256(a.r) ^ 1);
        vm.expectRevert(bytes("invalid signature"));
        party.spray(ID, 0, LABEL, 1, a);
    }

    function test_spray_tamperedValueReverts() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        a.value = 100e6; // relayer inflates the note
        vm.expectRevert(bytes("invalid signature"));
        party.spray(ID, 0, LABEL, 1, a);
    }

    function test_spray_relayerCannotChangeId() public {
        _defaultParty(ID, 1);
        _defaultParty(ID2, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        vm.expectRevert(bytes("invalid signature"));
        party.spray(ID2, 0, LABEL, 1, a);
    }

    function test_spray_relayerCannotChangeRecipient() public {
        _defaultParty(ID, 2);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        vm.expectRevert(bytes("invalid signature"));
        party.spray(ID, 1, LABEL, 1, a);
    }

    function test_spray_relayerCannotChangeLabel() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        vm.expectRevert(bytes("invalid signature"));
        party.spray(ID, 0, bytes32("Impostor"), 1, a);
    }

    function test_spray_relayerCannotChangeSalt() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        vm.expectRevert(bytes("invalid signature"));
        party.spray(ID, 0, LABEL, 2, a);
    }

    function test_spray_authorizationMustPayTheParty() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _auth(
            AuthReq({
                key: guestKey,
                tokenDomain: usdcDomain,
                to: address(0xBAD), // guest signed a payment to someone else
                value: 1e6,
                validAfter: 0,
                validBefore: block.timestamp + 60,
                nonce: _nonce(ID, 0, LABEL, 1)
            })
        );
        vm.expectRevert(bytes("invalid signature"));
        party.spray(ID, 0, LABEL, 1, a);
    }

    function test_spray_cannotBeFrontRunIntoToken() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        // receiveWithAuthorization demands msg.sender == to, so an attacker cannot burn the guest's auth directly.
        vm.prank(address(0xA77AC4));
        vm.expectRevert(bytes("caller must be the payee"));
        usdc.receiveWithAuthorization(
            a.from, address(party), a.value, a.validAfter, a.validBefore, _nonce(ID, 0, LABEL, 1), a.v, a.r, a.s
        );
        party.spray(ID, 0, LABEL, 1, a); // the legitimate path still works
        assertEq(usdc.balanceOf(celebrant), 1e6);
    }

    function test_spray_closedPartyReverts() public {
        _defaultParty(ID, 1);
        party.closeParty(ID, _closeSig(ID, hostKey));
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        vm.expectRevert(OjoParty.PartyIsClosed.selector);
        party.spray(ID, 0, LABEL, 1, a);
    }

    function test_spray_expiredPartyReverts() public {
        uint64 closesAt = _defaultParty(ID, 1);
        vm.warp(closesAt - 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6); // signed after the warp so the token window is open
        party.spray(ID, 0, LABEL, 1, a); // last second still works
        vm.warp(closesAt);
        OjoParty.Auth memory b = _mkAuth(ID, 0, LABEL, 2, 1e6);
        vm.expectRevert(OjoParty.PartyExpired.selector);
        party.spray(ID, 0, LABEL, 2, b);
    }

    function test_spray_noteOutsideMaskReverts() public {
        _create(ID, address(usdc), _recips(1), uint64(block.timestamp + 1 hours), 0x01); // only $1 allowed
        party.spray(ID, 0, LABEL, 1, _mkAuth(ID, 0, LABEL, 1, 1e6));
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 2, 5e6);
        vm.expectRevert(OjoParty.NoteNotAllowed.selector);
        party.spray(ID, 0, LABEL, 2, a);
    }

    function test_spray_nonNoteValueReverts() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 3e6); // $3 is not a note
        vm.expectRevert(OjoParty.BadNote.selector);
        party.spray(ID, 0, LABEL, 1, a);
    }

    function test_spray_recipientOutOfRangeReverts() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory a = _mkAuth(ID, 1, LABEL, 1, 1e6);
        vm.expectRevert(OjoParty.BadRecipient.selector);
        party.spray(ID, 1, LABEL, 1, a);
    }

    function test_spray_unknownPartyReverts() public {
        OjoParty.Auth memory a = _mkAuth(ID, 0, LABEL, 1, 1e6);
        vm.expectRevert(OjoParty.NoSuchParty.selector);
        party.spray(ID, 0, LABEL, 1, a);
    }

    function test_spray_authorizationWindowIsEnforcedByToken() public {
        _defaultParty(ID, 1);
        OjoParty.Auth memory expired = _auth(
            AuthReq({
                key: guestKey,
                tokenDomain: usdcDomain,
                to: address(party),
                value: 1e6,
                validAfter: 0,
                validBefore: block.timestamp, // not strictly in the future
                nonce: _nonce(ID, 0, LABEL, 1)
            })
        );
        vm.expectRevert(bytes("authorization is expired"));
        party.spray(ID, 0, LABEL, 1, expired);

        OjoParty.Auth memory early = _auth(
            AuthReq({
                key: guestKey,
                tokenDomain: usdcDomain,
                to: address(party),
                value: 1e6,
                validAfter: block.timestamp + 10,
                validBefore: block.timestamp + 60,
                nonce: _nonce(ID, 0, LABEL, 2)
            })
        );
        vm.expectRevert(bytes("authorization is not yet valid"));
        party.spray(ID, 0, LABEL, 2, early);
    }

    function test_spray_worksWithAusdParty() public {
        _create(ID, address(ausd), _recips(1), uint64(block.timestamp + 1 hours), ALL);
        OjoParty.Auth memory a = _auth(
            AuthReq({
                key: guestKey,
                tokenDomain: ausd.DOMAIN_SEPARATOR(),
                to: address(party),
                value: 2e6,
                validAfter: 0,
                validBefore: block.timestamp + 60,
                nonce: _nonce(ID, 0, LABEL, 7)
            })
        );
        party.spray(ID, 0, LABEL, 7, a);
        assertEq(ausd.balanceOf(celebrant), 2e6);
        assertEq(usdc.balanceOf(celebrant), 0);
    }

    // ---------- closeParty ----------

    function test_close_emitsTotalAndLocks() public {
        _defaultParty(ID, 1);
        party.spray(ID, 0, LABEL, 1, _mkAuth(ID, 0, LABEL, 1, 10e6));
        vm.expectEmit(true, false, false, true);
        emit PartyClosed(ID, 10e6);
        party.closeParty(ID, _closeSig(ID, hostKey));
        assertTrue(party.getParty(ID).closed);
    }

    function test_close_wrongSignerReverts() public {
        _defaultParty(ID, 1);
        bytes memory sig = _closeSig(ID, guestKey);
        vm.expectRevert(OjoParty.NotHost.selector);
        party.closeParty(ID, sig);
    }

    function test_close_twiceReverts() public {
        _defaultParty(ID, 1);
        party.closeParty(ID, _closeSig(ID, hostKey));
        bytes memory sig = _closeSig(ID, hostKey);
        vm.expectRevert(OjoParty.PartyIsClosed.selector);
        party.closeParty(ID, sig);
    }

    function test_close_unknownPartyReverts() public {
        bytes memory sig = _closeSig(ID, hostKey);
        vm.expectRevert(OjoParty.NoSuchParty.selector);
        party.closeParty(ID, sig);
    }

    function test_close_allowedAfterExpiry() public {
        uint64 closesAt = _defaultParty(ID, 1);
        vm.warp(closesAt + 1 days);
        party.closeParty(ID, _closeSig(ID, hostKey));
        assertTrue(party.getParty(ID).closed);
    }

    function test_close_signatureIsPartySpecific() public {
        _defaultParty(ID, 1);
        _defaultParty(ID2, 1);
        bytes memory sigForId2 = _closeSig(ID2, hostKey);
        vm.expectRevert(OjoParty.NotHost.selector);
        party.closeParty(ID, sigForId2);
    }
}
