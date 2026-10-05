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

## 2026-10-05: `createParty` takes `host` explicitly and reverts unless the signature recovers to it

The plan derived the host from the signature. That lets anyone front-run a party id with their own key and squat it.
Now the caller names the host and the signature must match, so a front-runner needs the host's own signature, which
only lets them submit the party the host already asked for. Test: `test_createParty_cannotSquatAnId`.

## 2026-10-05: BundleDesk vouchers are bearer keys, not codes

The plan used a secret `code`. A code revealed in a claim transaction can be copied by anyone watching and re-submitted
to a different recipient. Now the vendor signs `Voucher(vendor, token, amount, voucher, expiry)` where `voucher` is the
address of a fresh key printed in the QR, and that key signs `Claim(voucherDigest, to)`. `to` is inside the voucher
key's signature, so nobody can redirect a payout. Cost: the QR carries a private key, so treat the QR as cash.

## 2026-10-05: Fork tests need `--network monad`

Without it forge builds an Ethereum EVM and rejects a chainId-143 fork. With it, forge applies Monad's gas schedule.
The relayer gas limit comes from the fork numbers, not from Ethereum-flavoured ones.

## 2026-10-05: Relayer gas limits, measured

Cold-path `spray`: AUSD 196,328 gas, USDC 247,897 gas (`contracts/snapshots/ForkMonadTest.json`). The test cools the
party, token, recipient and guest accounts first, because a real spray is its own transaction. The token proxies'
implementation contracts stay warm in the test, so the limit carries a 15% margin plus intrinsic gas and calldata:
AUSD 260,000, USDC 320,000. Monad charges the limit, not gas used, so a tighter limit is cheaper but a too-tight limit
fails the transaction. Re-check against a real testnet or mainnet spray in Phase 2.

## 2026-10-05: Phase 1 self-review (manual, no `solidity-auditor` run), and known limits

Checked by hand: state is updated before the external calls; only AUSD and USDC are ever called (fixed at deploy), so
no token callback can re-enter; signatures are checked through `tryRecover`, which never reverts or trusts a
malformed signature; domains carry chainId and contract address, so testnet signatures do not replay on mainnet;
the contracts have no owner, no upgrade path and no fee. Accepted limits, not bugs:
- A `label` is whatever the guest signs. The wall and the MC console must filter or cap it (Phase 5 and 7).
- If Circle or Agora blacklists a recipient, the party contract or the desk, the spray or claim reverts atomically and
  no funds move. A paused token stops all sprays.
- A vendor can withdraw before a signed voucher is claimed; the claim then reverts with `InsufficientBalance`.
- `PartyClosed` can be emitted after expiry by anyone holding the host's close signature.
A second pair of eyes (`solidity-auditor` or an outside reviewer) is still worth doing before mainnet money moves.

## 2026-10-05: Routing is bound by the guest's own signature

The ERC-3009 nonce is `keccak256(abi.encode(id, recipientIdx, label, salt))`. A relayer cannot redirect a note to
another party, recipient or name without invalidating the guest's signature.
