// Spike 2b: how long from a block first being seen ("Proposed") to each later commitState?
// Run: node measure.mjs [seconds] [wss-url]
const SECONDS = Number(process.argv[2] ?? 60);
const URL_ = process.argv[3] ?? "wss://rpc.monad.xyz";
const ws = new WebSocket(URL_);

const blocks = new Map(); // number -> { state: firstSeenMs }
const states = new Set();

ws.onopen = () => ws.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_subscribe", params: ["monadNewHeads"] }));

ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.method !== "eth_subscription") return;
  const h = m.params.result;
  const n = parseInt(h.number, 16);
  const t = performance.now();
  states.add(h.commitState);
  const rec = blocks.get(n) ?? {};
  rec[h.commitState] ??= t;
  rec.blockTs ??= parseInt(h.timestamp, 16);
  blocks.set(n, rec);
};

const pct = (arr, p) => {
  const a = [...arr].sort((x, y) => x - y);
  return a.length ? a[Math.min(a.length - 1, Math.floor((p / 100) * a.length))] : null;
};

setTimeout(() => {
  ws.close();
  const first = [...states];
  const out = { seconds: SECONDS, blocksSeen: blocks.size, statesObserved: first, deltasMs: {} };
  // Delta from the earliest state each block was seen in to every other state.
  const order = ["Proposed", "Voted", "Finalized", "Verified"];
  for (const target of order.slice(1)) {
    const d = [];
    for (const rec of blocks.values()) {
      if (rec.Proposed !== undefined && rec[target] !== undefined) d.push(rec[target] - rec.Proposed);
    }
    out.deltasMs[`Proposed->${target}`] = {
      n: d.length,
      p50: pct(d, 50)?.toFixed(0) ?? null,
      p95: pct(d, 95)?.toFixed(0) ?? null,
      max: d.length ? Math.max(...d).toFixed(0) : null,
    };
  }
  // Blocks that never showed a Proposed event cannot be timed from Proposed; count them honestly.
  out.blocksWithoutProposed = [...blocks.values()].filter((r) => r.Proposed === undefined).length;
  console.log(JSON.stringify(out, null, 2));
  process.exit(0);
}, SECONDS * 1000);
