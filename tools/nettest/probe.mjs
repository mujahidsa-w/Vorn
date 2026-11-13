// Protocol probe for the Firebase Realtime Database used by the online mode.
// Only touches /vorn/_probe/<random>.
import WebSocket from "ws";
const DB = process.argv[2];
const host = new URL(DB).host;
const ns = host.split(".")[0];
const key = "t" + Math.random().toString(36).slice(2, 10);
const base = `/vorn/_probe/${key}`;
function open(name, h = host) {
  return new Promise((res, rej) => {
    const ws = new WebSocket(`wss://${h}/.ws?v=5&ns=${ns}`);
    const c = { ws, name, r: 0, log: [] };
    ws.on("message", (m) => { const s = m.toString(); console.log(`[${name}] <- ${s.slice(0, 600)}`); c.log.push(s); });
    ws.on("open", () => res(c));
    ws.on("error", (e) => { console.log(`[${name}] error ${e}`); rej(e); });
    ws.on("close", (code, why) => console.log(`[${name}] closed ${code} ${why}`));
  });
}
function send(c, a, b) { const m = JSON.stringify({ t: "d", d: { r: ++c.r, a, b } }); console.log(`[${c.name}] -> ${m.slice(0, 300)}`); c.ws.send(m); }
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const A = await open("A");
await wait(800);
const B = await open("B");
await wait(800);
send(A, "q", { p: base, h: "" });
send(B, "q", { p: base, h: "" });
await wait(800);
send(A, "p", { p: base + "/meta", d: { host: "a", n: 1 } });
await wait(600);
send(B, "p", { p: base + "/s/b", d: [1, 2, 3, "x"] });
await wait(600);
send(B, "m", { p: base + "/meta", d: { n: 2, extra: true } });
await wait(600);
send(A, "p", { p: base + "/ev/" + "k1", d: { ts: { ".sv": "timestamp" }, v: 1 } });
await wait(600);
send(B, "o", { p: base + "/s/b", d: null });
send(A, "o", { p: base, d: null });
await wait(600);
A.ws.send("0");
await wait(400);
// big frame test (> 16384 chars)
send(A, "p", { p: base + "/big", d: "y".repeat(40000) });
await wait(1200);
send(A, "p", { p: base + "/big", d: null });
await wait(500);
console.log("--- closing B (its onDisconnect should remove s/b)");
B.ws.close();
await wait(1500);
console.log("--- closing A (its onDisconnect should remove everything)");
A.ws.close();
await wait(1500);
const C = await open("C");
await wait(500);
send(C, "q", { p: base, h: "" });
await wait(1000);
C.ws.close();
await wait(300);
console.log("PROBE DONE");
