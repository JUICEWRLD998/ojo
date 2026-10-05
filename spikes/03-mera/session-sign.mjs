// Spike 3a: the signing half of Mera, without a passkey. A session built from a 32-byte key signs
// ReceiveWithAuthorization (EIP-712) through viem repeatedly with no prompt, and refuses after end().
// Run: node session-sign.mjs
import { createSecp256k1SigningSession, isMeraError } from "@category-labs/mera";
import { toViemAccount } from "@category-labs/mera/viem";
import { verifyTypedData } from "viem";
import { randomBytes } from "node:crypto";

const AUSD = "0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a";
const domain = { name: "Agora Dollar", version: "1", chainId: 143, verifyingContract: AUSD };
const types = {
  ReceiveWithAuthorization: [
    { name: "from", type: "address" },
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "validAfter", type: "uint256" },
    { name: "validBefore", type: "uint256" },
    { name: "nonce", type: "bytes32" },
  ],
};
const party = "0x000000000000000000000000000000000000dEaD";

const session = createSecp256k1SigningSession({ privateKey: randomBytes(32) });
const account = toViemAccount(session);
console.log("address", account.address, "source", account.source);

let ok = 0;
const t0 = performance.now();
for (let i = 0; i < 5; i++) {
  const message = {
    from: account.address,
    to: party,
    value: BigInt(1_000_000 * (i + 1)),
    validAfter: 0n,
    validBefore: BigInt(Math.floor(Date.now() / 1000) + 60),
    nonce: `0x${randomBytes(32).toString("hex")}`,
  };
  const signature = await account.signTypedData({ domain, types, primaryType: "ReceiveWithAuthorization", message });
  const valid = await verifyTypedData({ address: account.address, domain, types, primaryType: "ReceiveWithAuthorization", message, signature });
  if (valid) ok++;
}
console.log(`signed and verified ${ok}/5 notes from one session in ${(performance.now() - t0).toFixed(0)} ms`);

// Negative control: a tampered message must NOT verify against the same signature.
const msg = { from: account.address, to: party, value: 1n, validAfter: 0n, validBefore: 9999999999n, nonce: `0x${"11".repeat(32)}` };
const sig = await account.signTypedData({ domain, types, primaryType: "ReceiveWithAuthorization", message: msg });
const tampered = await verifyTypedData({ address: account.address, domain, types, primaryType: "ReceiveWithAuthorization", message: { ...msg, value: 2n }, signature: sig });
console.log("tampered message verifies (must be false):", tampered);

session.end();
try {
  await account.signTypedData({ domain, types, primaryType: "ReceiveWithAuthorization", message: msg });
  console.log("after end(): signed (BAD)");
} catch (e) {
  console.log("after end(): refused, code =", isMeraError(e) ? e.code : e.message);
}
