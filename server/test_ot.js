// Fuzz test: thousands of random simultaneous edits must always end with the
// same text on both sides.
const { transform, apply } = require("./ot");

let seed = 12345;
const rnd = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
const ALPHA = ["a", "b", "c", "\n", " ", "é", "🙂"];
const word = () => Array.from({ length: 1 + rnd(4) }, () => ALPHA[rnd(ALPHA.length)]).join("");

function randomOp(len) {
  const op = [];
  let cur = len;
  for (let k = 0; k < 1 + rnd(3); k++) {
    if (cur > 0 && rnd(2)) {
      const d = rnd(cur), n = 1 + rnd(Math.min(5, cur - d));
      op.push({ d, n }); cur -= n;
    } else {
      const s = word(); op.push({ i: rnd(cur + 1), s }); cur += Array.from(s).length;
    }
  }
  return op;
}

let passed = 0, failed = 0;
for (let t = 0; t < 20000; t++) {
  const base = Array.from(word() + word() + word() + word());
  const A = randomOp(base.length), B = randomOp(base.length);
  const aFirst = rnd(2) === 1;
  const [A2, B2] = transform(A, B, aFirst);
  const x = base.slice(), y = base.slice();
  const ok1 = apply(x, A) && apply(x, B2);
  const ok2 = apply(y, B) && apply(y, A2);
  if (ok1 && ok2 && x.join("") === y.join("")) passed++;
  else {
    failed++;
    if (failed < 4) console.log("FAIL", JSON.stringify({ base: base.join(""), A, B, aFirst, A2, B2, x: x.join(""), y: y.join("") }));
  }
}
// Same-spot inserts: the one that goes first must actually be first.
const c = Array.from("xy");
const [L, R] = transform([{ i: 1, s: "A" }], [{ i: 1, s: "B" }], true);
const p = c.slice(); apply(p, [{ i: 1, s: "A" }]); apply(p, R);
console.log(p.join("") === "xABy" ? "ok   tie goes to the first side" : "FAIL tie order");
console.log(`random pairs: passed ${passed} | failed ${failed}`);
process.exit(failed ? 1 : 0);
