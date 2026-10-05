# Decisions

Newest last. Each entry: what, why, what it costs.

## 2026-10-05: Guest wallets are never EIP-7702 delegated

Monad requires a delegated EOA to keep a 10 MON reserve. Guests hold no MON, so delegation would strand them.
Guests sign ERC-3009 authorizations and a relayer pays gas instead.

## 2026-10-05: `receiveWithAuthorization`, not `transferWithAuthorization`

`receiveWith...` requires `msg.sender == to`. Nobody can front-run the authorization straight into the token and leave
the wall without an event. Cost: the party contract must be the caller, so every spray goes through `OjoParty`.

## 2026-10-05: The two tokens use different EIP-712 domains, so the client reads them per token

AUSD signs under `Agora Dollar` / `1`, USDC under `USDC` / `2`. The wallet and relayer must take the domain from a
per-token config, never share one constant. `name()` is not the domain name for AUSD (`name()` returns `AUSD`).
Evidence: spike 1.

## 2026-10-05: The MC console reads `monadNewHeads` and `monadLogs`, and waits for `Finalized`

Monad's own subscriptions carry `commitState`. The wall shows a note at `Proposed` (greyed) and the MC console calls
the name at `Finalized`. Spike 2 measured `Proposed` to `Finalized` at p50 280 ms but p95 1629 ms, so the Phase 3 exit
target "p95 under 1 s" is not safe as written: re-measure with a real spray before promising it on a slide.

## 2026-10-05: Routing is bound by the guest's own signature

The ERC-3009 nonce is `keccak256(abi.encode(id, recipientIdx, label, salt))`. A relayer cannot redirect a note to
another party, recipient or name without invalidating the guest's signature.
