# Claims

Every number or capability claim the project makes, with how it was checked. A claim with no evidence link is not
a claim yet.

| Claim | Status | Evidence |
|---|---|---|
| Monad mainnet chainId is 143, public RPC `https://rpc.monad.xyz` | Verified live 2026-10-04 | `eth_chainId` returned `0x8f` |
| AUSD `0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a`, 6 decimals | Verified live 2026-10-04 | `symbol()`, `decimals()` |
| USDC `0x754704Bc059F8C67012fEd69BC8A327a5aafb603`, 6 decimals | Verified live 2026-10-04 | `symbol()`, `decimals()` |
| AUSD and USDC expose the ERC-3009 `RECEIVE_WITH_AUTHORIZATION_TYPEHASH` getter | Verified live 2026-10-04 | getter returns the standard value |
| A signed `receiveWithAuthorization` call moves balance on both tokens; replay and wrong-nonce signatures revert | Verified on fork, block 110755048 | `spikes/01-erc3009.output.txt`, test in `spikes/01-erc3009/test/Erc3009.t.sol` |
| AUSD EIP-712 domain is name `Agora Dollar`, version `1`, chainId 143; USDC is name `USDC`, version `2` | Verified on fork, recomputed separator equals on-chain `DOMAIN_SEPARATOR()` | same output file |
| Token-side gas for one `receiveWithAuthorization`: AUSD 137,694, USDC 187,789 (cold fork state, excludes `OjoParty` overhead) | Measured on fork | same output file |
| Monad exposes a proposed vs finalized signal: `eth_subscribe("monadNewHeads")` on `wss://rpc.monad.xyz` adds `commitState` (`Proposed`, `Voted`, `Finalized`, `Verified`) and `blockId` to each head | Verified live 2026-10-05 | `spikes/02-finality/probe.output.txt` |
| `eth_getBlockByNumber` also accepts `safe` and `finalized` tags | Verified live 2026-10-05 | `cast block safe`, `cast block finalized` |
| Block-level delay after first sight (`Proposed`): to `Finalized` p50 280 ms, p95 1629 ms, max 4528 ms; to `Verified` p50 1522 ms. One 60 s run, 170 blocks, client-side arrival times from one machine | Measured, single run | `spikes/02-finality/measure.output.txt` |
| Flick-to-log latency of a real spray (signed note to `Sprayed` log, p50 / p95) | Open | needs a funded relayer key and a deployed contract, Phase 2 |
| Mera `@category-labs/mera` 0.2.0 API for our flow: `createSecretVaultWithNewPasskey` (one passkey prompt, plus a second on authenticators without PRF at creation), `decryptSecretVaultWithPasskey` (one prompt), `createSecp256k1SigningSession`, `toViemAccount` from `@category-labs/mera/viem` | Verified by reading the shipped `.d.ts` | `spikes/03-mera/node_modules/@category-labs/mera/dist/*.d.ts` (install with `npm i`) |
| A Mera session signs repeated EIP-712 `ReceiveWithAuthorization` messages with no prompt; signatures verify with viem; a tampered message fails; signing after `end()` throws `SESSION_ENDED` | Verified in Node, 5/5 | `spikes/03-mera/session-sign.output.txt` |
| Mera creates a passkey account on a real iPhone (Safari) and Android (Chrome) | Open, needs a phone | device matrix not yet recorded |
| Envio HyperIndex lists Monad mainnet (chainId 143) with a live HyperSync endpoint `https://143.hypersync.xyz` (height 110758608 vs RPC 110758614) | Verified live 2026-10-05 | `spikes/04-envio/evidence.txt`. Not yet run: an actual indexer |
| `OjoParty` and `BundleDesk` pass 56 tests: 34 + 18 unit tests on a mock ERC-3009 token (including fuzz: sum of notes equals recipient delta and the contract balance stays 0) and 4 fork tests on the real AUSD and USDC | Verified, `forge test --network monad` in `contracts/` | `contracts/test/`, fork pinned to block 110755048 |
| A relayer cannot change party id, recipient, label, salt, note value or the payee; replay and tampered signatures revert; a closed or expired party and a note outside the mask revert | Verified by tests, unit and fork | `contracts/test/OjoParty.t.sol`, `ForkMonad.t.sol` |
| Cold-path `spray` function gas on the Monad-flavoured fork: AUSD 196,328, USDC 247,897 | Measured | `contracts/snapshots/ForkMonadTest.json` |
| Cost per spray (superseded by the line above once Phase 2 measures a real transaction): about 0.08 to 0.10 US cents (0.80 to 0.97 USD per 1,000), at 102 gwei and MON 0.0315 USD | Estimate. Token-call gas is measured, the other 87,000 gas is assumed until `OjoParty` exists | `spikes/05-gas/estimate.txt` |
