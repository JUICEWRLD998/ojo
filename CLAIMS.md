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
| Mera creates an account and signs twice with one prompt | Open | spike 3 |
| Envio HyperIndex supports chainId 143 | Open | spike 4 |
| Gas per `spray`, and its cost in cents | Open | spike 5 |
