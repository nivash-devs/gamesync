// Text operations for live script editing (operational transformation).
//
// An op is a list of steps applied in order:
//   { i: pos, s: "text" }   insert text at pos
//   { d: pos, n: count }    delete count characters at pos
// Positions count characters (code points), same as Godot strings.
//
// transform(A, B) takes two ops made at the same time on the same text and
// returns [A', B'] so that applying A then B' gives the same text as B then A'.
// When both insert at the same spot, `aFirst` decides whose text goes first.

const isIns = (c) => typeof c.s === "string";

function len(s) {
  return Array.from(s).length;
}

function clean(op) {
  return op.filter((c) => (isIns(c) ? c.s.length > 0 : c.n > 0));
}

function pair(a, b, aFirst) {
  if (isIns(a) && isIns(b)) {
    const aGoesFirst = a.i < b.i || (a.i === b.i && aFirst);
    return [
      [aGoesFirst ? a : { i: a.i + len(b.s), s: a.s }],
      [aGoesFirst ? { i: b.i + len(a.s), s: b.s } : b],
    ];
  }
  if (isIns(a) && !isIns(b)) return [[insAfterDel(a, b)], delAfterIns(b, a)];
  if (!isIns(a) && isIns(b)) return [delAfterIns(a, b), [insAfterDel(b, a)]];
  return [delAfterDel(a, b), delAfterDel(b, a)];
}

// Where an insert lands once a delete has happened.
function insAfterDel(ins, del) {
  if (ins.i <= del.d) return ins;
  if (ins.i >= del.d + del.n) return { i: ins.i - del.n, s: ins.s };
  return { i: del.d, s: ins.s };
}

// A delete once an insert has happened. If the insert landed inside the
// deleted range, the delete splits in two so the inserted text survives.
function delAfterIns(del, ins) {
  const L = len(ins.s);
  if (ins.i <= del.d) return [{ d: del.d + L, n: del.n }];
  if (ins.i >= del.d + del.n) return [del];
  const before = ins.i - del.d;
  return [{ d: del.d, n: before }, { d: del.d + L, n: del.n - before }];
}

// A delete once another delete has happened: don't delete text twice.
function delAfterDel(a, b) {
  const ae = a.d + a.n, be = b.d + b.n;
  if (ae <= b.d) return [a];
  if (a.d >= be) return [{ d: a.d - b.n, n: a.n }];
  const overlap = Math.min(ae, be) - Math.max(a.d, b.d);
  const left = a.n - overlap;
  return left > 0 ? [{ d: Math.min(a.d, b.d), n: left }] : [];
}

function transform(A, B, aFirst) {
  A = clean(A);
  B = clean(B);
  if (A.length === 0 || B.length === 0) return [A, B];
  if (A.length > 1) {
    const [a1, B1] = transform([A[0]], B, aFirst);
    const [rest, B2] = transform(A.slice(1), B1, aFirst);
    return [a1.concat(rest), B2];
  }
  if (B.length > 1) {
    const [A1, b1] = transform(A, [B[0]], aFirst);
    const [A2, rest] = transform(A1, B.slice(1), aFirst);
    return [A2, b1.concat(rest)];
  }
  return pair(A[0], B[0], aFirst).map(clean);
}

// Applies op to an array of characters. Returns false if the op doesn't fit.
function apply(chars, op) {
  for (const c of op) {
    if (isIns(c)) {
      if (!Number.isInteger(c.i) || c.i < 0 || c.i > chars.length) return false;
      const ins = Array.from(c.s);
      const tail = chars.splice(c.i);
      for (const ch of ins) chars.push(ch);
      for (const ch of tail) chars.push(ch);
    } else {
      if (!Number.isInteger(c.d) || !Number.isInteger(c.n) || c.d < 0 || c.n < 0 || c.d + c.n > chars.length) return false;
      chars.splice(c.d, c.n);
    }
  }
  return true;
}

function validShape(op) {
  return Array.isArray(op) && op.length <= 2000 && op.every((c) =>
    c && typeof c === "object" &&
    ((typeof c.s === "string" && Number.isInteger(c.i) && c.s.length <= 1_000_000) ||
     (Number.isInteger(c.d) && Number.isInteger(c.n))));
}

module.exports = { transform, apply, validShape };
