// Spike 2a: which subscription types does rpc.monad.xyz accept, and what do they say about commit state?
// Run: node probe.mjs [wss-url]
const URL_ = process.argv[2] ?? "wss://rpc.monad.xyz";
const ws = new WebSocket(URL_);
let id = 0;
const pending = new Map();

const send = (method, params = []) =>
  new Promise((resolve) => {
    const myId = ++id;
    pending.set(myId, resolve);
    ws.send(JSON.stringify({ jsonrpc: "2.0", id: myId, method, params }));
  });

const seen = {};
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) {
    pending.get(m.id)(m);
    pending.delete(m.id);
  } else if (m.method === "eth_subscription") {
    const sub = m.params.subscription;
    seen[sub] ??= [];
    // Keep output readable: drop the 512-byte bloom and the other 32-byte roots, keep what identifies state.
    const r = m.params.result;
    const slim = r?.logsBloom
      ? { number: r.number, timestamp: r.timestamp, hash: r.hash, keys: Object.keys(r).filter((k) => !/Root|Bloom|Hash|Uncles/.test(k)) }
      : r;
    if (seen[sub].length < 3) seen[sub].push(slim);
  }
};

ws.onopen = async () => {
  const candidates = [
    ["newHeads", ["newHeads"]],
    ["monadNewHeads", ["monadNewHeads"]],
    ["logs", ["logs", {}]],
    ["monadLogs", ["monadLogs", {}]],
  ];
  const subs = {};
  for (const [label, params] of candidates) {
    const r = await send("eth_subscribe", params);
    console.log(JSON.stringify({ label, accepted: !r.error, result: r.result ?? r.error }));
    if (!r.error) subs[r.result] = label;
  }
  await new Promise((r) => setTimeout(r, 4000));
  for (const [subId, label] of Object.entries(subs)) {
    console.log(JSON.stringify({ label, sample: seen[subId] ?? [] }, null, 1));
  }
  ws.close();
};
