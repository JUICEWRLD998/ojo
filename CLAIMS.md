# Claims

Every number or capability claim the project makes, with how it was checked. A claim with no evidence link is not
a claim yet.

| Claim | Status | Evidence |
|---|---|---|
| Monad mainnet chainId is 143, public RPC `https://rpc.monad.xyz` | Verified live 2026-10-04 | `eth_chainId` returned `0x8f` |
| AUSD `0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a`, 6 decimals | Verified live 2026-10-04 | `symbol()`, `decimals()` |
| USDC `0x754704Bc059F8C67012fEd69BC8A327a5aafb603`, 6 decimals | Verified live 2026-10-04 | `symbol()`, `decimals()` |
| AUSD and USDC expose the ERC-3009 `RECEIVE_WITH_AUTHORIZATION_TYPEHASH` getter | Verified live 2026-10-04 | getter returns the standard value |
| A signed `receiveWithAuthorization` call moves balance on both tokens | Open | spike 1 |
| Monad exposes a proposed vs finalized signal | Open | spike 2 |
| Flick-to-log latency p50 / p95 | Open | spike 2 |
| Mera creates an account and signs twice with one prompt | Open | spike 3 |
| Envio HyperIndex supports chainId 143 | Open | spike 4 |
| Gas per `spray`, and its cost in cents | Open | spike 5 |
