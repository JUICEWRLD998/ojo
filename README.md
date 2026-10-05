# Òjò

Rain money on the celebrant, from anywhere, final in under a second.

At a Lagos party, spraying naira notes on the celebrant is how a room says "we love you". Òjò (Yoruba for "rain")
moves that moment onto Monad. A guest scans the QR on the hall's screen, creates a wallet with Face ID, and flicks
stablecoin notes. Each note is final on Monad in about 0.6 seconds, rains onto the celebrant's photo on the big
screen, and the MC calls the guest's name only once the note is final. A relative abroad can spray live from the
party's stream.

Built for Monad Metropolis, Track 03: Social, Attention & Culture.

## Status

Phase 0 (spikes and setup) in progress. Nothing here is deployed yet. See `CLAIMS.md` for what has been verified and
how, and `DECISIONS.md` for why things are the way they are.

## Layout

| Path | Purpose |
|---|---|
| `contracts/` | `OjoParty` and `BundleDesk` (Foundry) |
| `relayer/` | Gas-sponsoring relayer (Node + Hono) |
| `web/` | Guest page, big-screen wall, MC console (Next.js) |
| `indexer/` | Ledger and leaderboard |
| `spikes/` | Phase 0 experiments, each with its recorded output |

## Author

Mustapha Fadhlullah, independent security researcher.
