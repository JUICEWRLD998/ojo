// End-to-end rehearsal: host creates a party, a guest signs a note, a relayer submits it, the host closes the party.
// Works on a local anvil fork, Monad testnet and Monad mainnet. Every step is checked against on-chain state.
//
// Run: node --env-file=../.env e2e-spray.mjs
// Env: RPC_URL, PARTY_ADDRESS, TOKEN_ADDRESS, TOKEN_NAME, TOKEN_VERSION, EXPLORER_TX_BASE (optional),
//      NOTE_USD (default 1), GAS_LIMIT (default 320000), DEPLOYER_PRIVATE_KEY (host and relayer), GUEST_PRIVATE_KEY.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import {
  createPublicClient, createWalletClient, http, defineChain, keccak256, encodeAbiParameters, concat, pad,
  parseAbi, decodeEventLog, hashDomain, stringToHex, getAddress, formatUnits, parseUnits,
} from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

const need = (k) => { const v = process.env[k]; if (!v) throw new Error(`missing env ${k}`); return v; };
const RPC_URL = need("RPC_URL");
const PARTY = getAddress(need("PARTY_ADDRESS"));
const TOKEN = getAddress(need("TOKEN_ADDRESS"));
const TOKEN_NAME = need("TOKEN_NAME");
const TOKEN_VERSION = need("TOKEN_VERSION");
const NOTE = parseUnits(process.env.NOTE_USD ?? "1", 6);
const GAS_LIMIT = BigInt(process.env.GAS_LIMIT ?? "320000");
const abi = JSON.parse(readFileSync(new URL("./abi/OjoParty.json", import.meta.url)));

const host = privateKeyToAccount(need("DEPLOYER_PRIVATE_KEY")); // host and relayer are the same key in the rehearsal
const guest = privateKeyToAccount(need("GUEST_PRIVATE_KEY"));

const probe = createPublicClient({ transport: http(RPC_URL) });
const chainId = await probe.getChainId();
const chain = defineChain({ id: chainId, name: `monad-${chainId}`, nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 }, rpcUrls: { default: { http: [RPC_URL] } } });
const pub = createPublicClient({ chain, transport: http(RPC_URL) });
const relayer = createWalletClient({ account: host, chain, transport: http(RPC_URL) });

const erc20 = parseAbi(["function balanceOf(address) view returns (uint256)", "function DOMAIN_SEPARATOR() view returns (bytes32)"]);
const bal = (who) => pub.readContract({ address: TOKEN, abi: erc20, functionName: "balanceOf", args: [who] });
const explorer = (h) => (process.env.EXPLORER_TX_BASE ? `${process.env.EXPLORER_TX_BASE}${h}` : h);
const log = (k, v) => console.log(k.padEnd(26), v);

// 1. The domain we sign under must equal the token's own. Fail before any money moves.
const tokenDomain = { name: TOKEN_NAME, version: TOKEN_VERSION, chainId, verifyingContract: TOKEN };
const onchainSep = await pub.readContract({ address: TOKEN, abi: erc20, functionName: "DOMAIN_SEPARATOR" });
if (hashDomain({ domain: tokenDomain, types: { EIP712Domain: [
  { name: "name", type: "string" }, { name: "version", type: "string" },
  { name: "chainId", type: "uint256" }, { name: "verifyingContract", type: "address" }] } }) !== onchainSep) {
  throw new Error("token EIP-712 domain does not match its on-chain DOMAIN_SEPARATOR; refusing to sign");
}
log("chain", chainId); log("party", PARTY); log("token", `${TOKEN} (${TOKEN_NAME} v${TOKEN_VERSION})`);
log("host/relayer", host.address); log("guest", guest.address);

const guestBefore = await bal(guest.address);
if (guestBefore < NOTE) throw new Error(`guest holds ${formatUnits(guestBefore, 6)} but the note is ${formatUnits(NOTE, 6)}; fund ${guest.address}`);

// 2. Host signs CreateParty, relayer submits.
const recipient = privateKeyToAccount(generatePrivateKey()).address; // fresh address: its balance delta is the proof
const id = keccak256(stringToHex(`ojo-e2e-${Date.now()}-${Math.random()}`));
const closesAt = BigInt(Math.floor(Date.now() / 1000) + 3600);
const noteMask = 0x7f;
const partyDomain = { name: "OjoParty", version: "1", chainId, verifyingContract: PARTY };
const recipients = [recipient];
const recipientsHash = keccak256(concat(recipients.map((a) => pad(a))));
const createSig = await host.signTypedData({
  domain: partyDomain,
  types: { CreateParty: [
    { name: "id", type: "bytes32" }, { name: "token", type: "address" }, { name: "recipientsHash", type: "bytes32" },
    { name: "closesAt", type: "uint64" }, { name: "noteMask", type: "uint16" }] },
  primaryType: "CreateParty",
  message: { id, token: TOKEN, recipientsHash, closesAt, noteMask },
});
const createHash = await relayer.writeContract({ address: PARTY, abi, functionName: "createParty", args: [id, host.address, TOKEN, recipients, closesAt, noteMask, createSig] });
const createRcpt = await pub.waitForTransactionReceipt({ hash: createHash });
if (createRcpt.status !== "success") throw new Error("createParty reverted");
log("createParty tx", explorer(createHash)); log("createParty gasUsed", createRcpt.gasUsed);

// 3. Guest signs the note. The nonce binds party, recipient, label and salt into the guest's own signature.
const label = stringToHex("Tunde Houston", { size: 32 });
const salt = BigInt(Date.now());
const nonce = keccak256(encodeAbiParameters([{ type: "bytes32" }, { type: "uint8" }, { type: "bytes32" }, { type: "uint256" }], [id, 0, label, salt]));
const latest = await pub.getBlock();
const validBefore = latest.timestamp + 120n;
const authSig = await guest.signTypedData({
  domain: tokenDomain,
  types: { ReceiveWithAuthorization: [
    { name: "from", type: "address" }, { name: "to", type: "address" }, { name: "value", type: "uint256" },
    { name: "validAfter", type: "uint256" }, { name: "validBefore", type: "uint256" }, { name: "nonce", type: "bytes32" }] },
  primaryType: "ReceiveWithAuthorization",
  message: { from: guest.address, to: PARTY, value: NOTE, validAfter: 0n, validBefore, nonce },
});
const r = authSig.slice(0, 66), s = `0x${authSig.slice(66, 130)}`, v = parseInt(authSig.slice(130, 132), 16);
const auth = { from: guest.address, value: NOTE, validAfter: 0n, validBefore, v, r, s };

// 4. Dry-run first (eth_call), then submit with the fixed gas limit. Monad charges the limit, not gas used.
await pub.simulateContract({ account: host, address: PARTY, abi, functionName: "spray", args: [id, 0, label, salt, auth], gas: GAS_LIMIT });
const t0 = performance.now();
const sprayHash = await relayer.writeContract({ address: PARTY, abi, functionName: "spray", args: [id, 0, label, salt, auth], gas: GAS_LIMIT });
const sprayRcpt = await pub.waitForTransactionReceipt({ hash: sprayHash });
const ms = performance.now() - t0;
if (sprayRcpt.status !== "success") throw new Error("spray reverted");
log("spray tx", explorer(sprayHash));
log("spray gasUsed / limit", `${sprayRcpt.gasUsed} / ${GAS_LIMIT}  (${Number((sprayRcpt.gasUsed * 100n) / GAS_LIMIT)}% of limit)`);
log("spray send-to-receipt ms", ms.toFixed(0));
log("spray cost (MON)", formatUnits(GAS_LIMIT * sprayRcpt.effectiveGasPrice, 18));

// 5. Verify against chain state, not against what we meant to do.
const sprayed = sprayRcpt.logs.map((l) => { try { return decodeEventLog({ abi, data: l.data, topics: l.topics }); } catch { return null; } })
  .find((e) => e?.eventName === "Sprayed");
const checks = {
  sprayedEvent: !!sprayed && sprayed.args.id === id && sprayed.args.from === guest.address && sprayed.args.recipient === recipient && sprayed.args.value === NOTE && sprayed.args.label === label,
  recipientGotNote: (await bal(recipient)) === NOTE,
  guestPaidNote: guestBefore - (await bal(guest.address)) === NOTE,
  partyHoldsNothing: (await bal(PARTY)) === 0n,
  partyTotal: (await pub.readContract({ address: PARTY, abi, functionName: "getParty", args: [id] })).total === NOTE,
};

// 6. Replay must revert (same authorization again).
let replayReverted = false;
try { await pub.simulateContract({ account: host, address: PARTY, abi, functionName: "spray", args: [id, 0, label, salt, auth], gas: GAS_LIMIT }); }
catch { replayReverted = true; }
checks.replayReverts = replayReverted;

// 7. Host closes the party.
const closeSig = await host.signTypedData({ domain: partyDomain, types: { CloseParty: [{ name: "id", type: "bytes32" }] }, primaryType: "CloseParty", message: { id } });
const closeHash = await relayer.writeContract({ address: PARTY, abi, functionName: "closeParty", args: [id, closeSig] });
const closeRcpt = await pub.waitForTransactionReceipt({ hash: closeHash });
checks.partyClosed = closeRcpt.status === "success" && (await pub.readContract({ address: PARTY, abi, functionName: "getParty", args: [id] })).closed === true;
log("closeParty tx", explorer(closeHash));

console.log("\nchecks", checks);
const allOk = Object.values(checks).every(Boolean);
// OUT_DIR=rehearsals for local forks: a fork reports chainId 143 too, and must never be filed as mainnet evidence.
const outDir = process.env.OUT_DIR ?? "deployments";
mkdirSync(new URL(`./${outDir}/`, import.meta.url), { recursive: true });
writeFileSync(new URL(`./${outDir}/e2e-${chainId}-${TOKEN_NAME.replace(/\W+/g, "_")}.json`, import.meta.url), JSON.stringify({
  chainId, party: PARTY, token: TOKEN, partyId: id, recipient, guest: guest.address,
  txs: { createParty: createHash, spray: sprayHash, closeParty: closeHash },
  sprayGasUsed: sprayRcpt.gasUsed.toString(), sprayGasLimit: GAS_LIMIT.toString(), sendToReceiptMs: Math.round(ms), checks, ok: allOk,
}, null, 2));
console.log(allOk ? "\nE2E PASS" : "\nE2E FAIL");
process.exit(allOk ? 0 : 1);
