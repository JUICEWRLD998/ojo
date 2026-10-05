// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3009} from "./interfaces/IERC3009.sol";

/// @title OjoParty
/// @notice Rain stablecoin notes on a celebrant. A guest signs an ERC-3009 authorization off-chain; anyone (the
///         relayer) submits it. The contract never holds funds past one call, has no owner, no upgrade path and no fee.
/// @dev Routing is bound by the guest's own signature: the ERC-3009 nonce must equal
///      keccak256(abi.encode(id, recipientIdx, label, salt)), recomputed here. A relayer that changes the party,
///      the recipient, the label or the salt makes the token reject the signature.
///      Only two tokens are accepted (AUSD and USDC, fixed at deploy), so no token callback can re-enter.
contract OjoParty is EIP712 {
    using SafeERC20 for IERC20;

    struct Party {
        address host;
        uint64 closesAt;
        uint16 noteMask; // bit i allows note i: $1 $2 $5 $10 $20 $50 $100
        bool closed;
        address token;
        address[] recipients;
        uint256 total;
    }

    /// The guest's signed ERC-3009 authorization. `to` is always this contract and `nonce` is derived, so neither is here.
    struct Auth {
        address from;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    bytes32 public constant CREATE_PARTY_TYPEHASH =
        keccak256("CreateParty(bytes32 id,address token,bytes32 recipientsHash,uint64 closesAt,uint16 noteMask)");
    bytes32 public constant CLOSE_PARTY_TYPEHASH = keccak256("CloseParty(bytes32 id)");
    uint256 public constant MAX_RECIPIENTS = 8;

    address public immutable AUSD;
    address public immutable USDC;

    mapping(bytes32 id => Party) private _parties;

    event PartyCreated(bytes32 indexed id, address indexed host, address token, address[] recipients, uint64 closesAt);
    event Sprayed(
        bytes32 indexed id, address indexed from, address indexed recipient, uint256 value, bytes32 label, bytes32 nonce
    );
    event PartyClosed(bytes32 indexed id, uint256 total);

    error NoSuchParty();
    error PartyExists();
    error PartyIsClosed();
    error PartyExpired();
    error UnsupportedToken();
    error NoRecipients();
    error TooManyRecipients();
    error ZeroRecipient();
    error BadClosesAt();
    error BadNoteMask();
    error BadRecipient();
    error BadNote();
    error NoteNotAllowed();
    error BadHostSig();
    error NotHost();
    error ZeroAddress();

    constructor(address ausd, address usdc) EIP712("OjoParty", "1") {
        if (ausd == address(0) || usdc == address(0)) revert ZeroAddress();
        AUSD = ausd;
        USDC = usdc;
    }

    // ------------------------------------------------------------------ host

    /// @notice Create a party. Relayed: the host signs `CreateParty` off-chain, anyone may submit it.
    /// @dev `host` is passed explicitly and must equal the signer, so nobody can squat an id with their own key.
    function createParty(
        bytes32 id,
        address host,
        address token,
        address[] calldata recipients,
        uint64 closesAt,
        uint16 noteMask,
        bytes calldata hostSig
    ) external {
        if (_parties[id].host != address(0)) revert PartyExists();
        if (token != AUSD && token != USDC) revert UnsupportedToken();
        uint256 n = recipients.length;
        if (n == 0) revert NoRecipients();
        if (n > MAX_RECIPIENTS) revert TooManyRecipients();
        for (uint256 i = 0; i < n; i++) {
            if (recipients[i] == address(0)) revert ZeroRecipient();
        }
        if (closesAt <= block.timestamp) revert BadClosesAt();
        if (noteMask == 0 || noteMask > 0x7F) revert BadNoteMask();

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CREATE_PARTY_TYPEHASH, id, token, keccak256(abi.encodePacked(recipients)), closesAt, noteMask
                )
            )
        );
        if (!_signedBy(digest, hostSig, host)) revert BadHostSig();

        Party storage p = _parties[id];
        p.host = host;
        p.closesAt = closesAt;
        p.noteMask = noteMask;
        p.token = token;
        p.recipients = recipients;

        emit PartyCreated(id, host, token, recipients, closesAt);
    }

    /// @notice Close a party. Relayed: the host signs `CloseParty(id)`. Allowed after expiry too, to emit the total.
    function closeParty(bytes32 id, bytes calldata hostSig) external {
        Party storage p = _parties[id];
        if (p.host == address(0)) revert NoSuchParty();
        if (p.closed) revert PartyIsClosed();
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(CLOSE_PARTY_TYPEHASH, id)));
        if (!_signedBy(digest, hostSig, p.host)) revert NotHost();
        p.closed = true;
        emit PartyClosed(id, p.total);
    }

    // ----------------------------------------------------------------- guest

    /// @notice Pull one signed note from `a.from` and pay it straight to the chosen recipient.
    function spray(bytes32 id, uint8 recipientIdx, bytes32 label, uint256 salt, Auth calldata a) external {
        Party storage p = _parties[id];
        if (p.host == address(0)) revert NoSuchParty();
        if (p.closed) revert PartyIsClosed();
        if (block.timestamp >= p.closesAt) revert PartyExpired();
        if (recipientIdx >= p.recipients.length) revert BadRecipient();
        if (p.noteMask & (uint256(1) << _noteIndex(a.value)) == 0) revert NoteNotAllowed();

        bytes32 nonce = keccak256(abi.encode(id, recipientIdx, label, salt));
        address recipient = p.recipients[recipientIdx];
        address token = p.token;

        p.total += a.value;
        IERC3009(token)
            .receiveWithAuthorization(a.from, address(this), a.value, a.validAfter, a.validBefore, nonce, a.v, a.r, a.s);
        IERC20(token).safeTransfer(recipient, a.value);

        emit Sprayed(id, a.from, recipient, a.value, label, nonce);
    }

    // ------------------------------------------------------------------ view

    function getParty(bytes32 id) external view returns (Party memory) {
        return _parties[id];
    }

    // -------------------------------------------------------------- internal

    /// Notes are $1 $2 $5 $10 $20 $50 $100 in 6-decimal units; anything else is not a note.
    function _noteIndex(uint256 value) private pure returns (uint256) {
        if (value == 1e6) return 0;
        if (value == 2e6) return 1;
        if (value == 5e6) return 2;
        if (value == 10e6) return 3;
        if (value == 20e6) return 4;
        if (value == 50e6) return 5;
        if (value == 100e6) return 6;
        revert BadNote();
    }

    /// True only when `sig` is a well-formed signature by `signer` (never reverts on a malformed signature).
    function _signedBy(bytes32 digest, bytes calldata sig, address signer) private pure returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sig);
        return err == ECDSA.RecoverError.NoError && recovered == signer && signer != address(0);
    }
}
