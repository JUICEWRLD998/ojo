# Decisions

Newest last. Each entry: what, why, what it costs.

## 2026-10-05: Guest wallets are never EIP-7702 delegated

Monad requires a delegated EOA to keep a 10 MON reserve. Guests hold no MON, so delegation would strand them.
Guests sign ERC-3009 authorizations and a relayer pays gas instead.

## 2026-10-05: `receiveWithAuthorization`, not `transferWithAuthorization`

`receiveWith...` requires `msg.sender == to`. Nobody can front-run the authorization straight into the token and leave
the wall without an event. Cost: the party contract must be the caller, so every spray goes through `OjoParty`.

## 2026-10-05: Routing is bound by the guest's own signature

The ERC-3009 nonce is `keccak256(abi.encode(id, recipientIdx, label, salt))`. A relayer cannot redirect a note to
another party, recipient or name without invalidating the guest's signature.
