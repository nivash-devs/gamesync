@tool
extends RefCounted
## Text operations for live script editing. Same rules as server/ot.js:
## an op is a list of steps applied in order,
##   {"i": pos, "s": "text"}  insert
##   {"d": pos, "n": count}   delete
## transform(A, B) returns [A', B'] so A then B' == B then A'.


static func is_ins(c: Dictionary) -> bool:
	return c.has("s")


static func norm(op: Array) -> Array:
	# JSON turns numbers into floats; make them ints again and drop empty steps.
	var out: Array = []
	for c in op:
		if not (c is Dictionary):
			continue
		if c.has("s"):
			var s := str(c.s)
			if s != "":
				out.append({"i": int(c.get("i", 0)), "s": s})
		elif c.has("d"):
			var n := int(c.get("n", 0))
			if n > 0:
				out.append({"d": int(c.d), "n": n})
	return out


static func transform(A: Array, B: Array, a_first: bool) -> Array:
	A = norm(A)
	B = norm(B)
	if A.is_empty() or B.is_empty():
		return [A, B]
	if A.size() > 1:
		var r1: Array = transform([A[0]], B, a_first)
		var r2: Array = transform(A.slice(1), r1[1], a_first)
		return [r1[0] + r2[0], r2[1]]
	if B.size() > 1:
		var r1: Array = transform(A, [B[0]], a_first)
		var r2: Array = transform(r1[0], B.slice(1), a_first)
		return [r2[0], r1[1] + r2[1]]
	var p := _pair(A[0], B[0], a_first)
	return [norm(p[0]), norm(p[1])]


static func _pair(a: Dictionary, b: Dictionary, a_first: bool) -> Array:
	if is_ins(a) and is_ins(b):
		var a_goes_first: bool = a.i < b.i or (a.i == b.i and a_first)
		if a_goes_first:
			return [[a], [{"i": b.i + str(a.s).length(), "s": b.s}]]
		return [[{"i": a.i + str(b.s).length(), "s": a.s}], [b]]
	if is_ins(a):
		return [[_ins_after_del(a, b)], _del_after_ins(b, a)]
	if is_ins(b):
		return [_del_after_ins(a, b), [_ins_after_del(b, a)]]
	return [_del_after_del(a, b), _del_after_del(b, a)]


static func _ins_after_del(ins: Dictionary, del: Dictionary) -> Dictionary:
	if ins.i <= del.d:
		return ins
	if ins.i >= del.d + del.n:
		return {"i": ins.i - del.n, "s": ins.s}
	return {"i": del.d, "s": ins.s}


static func _del_after_ins(del: Dictionary, ins: Dictionary) -> Array:
	var L := str(ins.s).length()
	if ins.i <= del.d:
		return [{"d": del.d + L, "n": del.n}]
	if ins.i >= del.d + del.n:
		return [del]
	var before: int = ins.i - del.d
	return [{"d": del.d, "n": before}, {"d": del.d + L, "n": del.n - before}]


static func _del_after_del(a: Dictionary, b: Dictionary) -> Array:
	var ae: int = a.d + a.n
	var be: int = b.d + b.n
	if ae <= b.d:
		return [a]
	if a.d >= be:
		return [{"d": a.d - b.n, "n": a.n}]
	var overlap: int = mini(ae, be) - maxi(a.d, b.d)
	var left: int = a.n - overlap
	if left > 0:
		return [{"d": mini(a.d, b.d), "n": left}]
	return []


## Returns the new text, or null if the op doesn't fit the text.
static func apply(text: String, op: Array):
	for c in op:
		if is_ins(c):
			if c.i < 0 or c.i > text.length():
				return null
			text = text.substr(0, c.i) + str(c.s) + text.substr(c.i)
		else:
			if c.d < 0 or c.n < 0 or c.d + c.n > text.length():
				return null
			text = text.substr(0, c.d) + text.substr(c.d + c.n)
	return text


## The edits that turn old into new, touching only characters that changed.
## Uses the Myers diff (same idea as git diff). Very different texts fall back
## to one delete + one insert.
static func diff(old: String, new: String, max_d: int = 400) -> Array:
	if old == new:
		return []
	var start := 0
	var max_start := mini(old.length(), new.length())
	while start < max_start and old.unicode_at(start) == new.unicode_at(start):
		start += 1
	var end_old := old.length()
	var end_new := new.length()
	while end_old > start and end_new > start and old.unicode_at(end_old - 1) == new.unicode_at(end_new - 1):
		end_old -= 1
		end_new -= 1
	var a := old.substr(start, end_old - start)
	var b := new.substr(start, end_new - start)
	if a != "" and b != "":
		var steps = _myers(a, b, max_d)
		if steps != null:
			return _steps_to_op(steps, a, b, start)
	var op: Array = []
	if a != "":
		op.append({"d": start, "n": a.length()})
	if b != "":
		op.append({"i": start, "s": b})
	return op


## Returns a list of "=", "-", "+" steps (one per character), or null if the
## texts differ in more than max_d places.
static func _myers(a: String, b: String, max_d: int):
	var n := a.length()
	var m := b.length()
	var off := max_d + 1
	var v := PackedInt32Array()
	v.resize(2 * off + 1)
	var trace: Array = []
	for d in max_d + 1:
		trace.append(v.duplicate())
		for k in range(-d, d + 1, 2):
			var x: int
			if k == -d or (k != d and v[off + k - 1] < v[off + k + 1]):
				x = v[off + k + 1]
			else:
				x = v[off + k - 1] + 1
			var y := x - k
			while x < n and y < m and a.unicode_at(x) == b.unicode_at(y):
				x += 1
				y += 1
			v[off + k] = x
			if x >= n and y >= m:
				return _backtrack(trace, n, m, off)
	return null


static func _backtrack(trace: Array, n: int, m: int, off: int) -> Array:
	var steps: Array = []
	var x := n
	var y := m
	for d in range(trace.size() - 1, -1, -1):
		var v: PackedInt32Array = trace[d]
		var k := x - y
		var prev_k: int
		if k == -d or (k != d and v[off + k - 1] < v[off + k + 1]):
			prev_k = k + 1
		else:
			prev_k = k - 1
		var prev_x: int = v[off + prev_k] if d > 0 else 0
		var prev_y: int = prev_x - prev_k if d > 0 else 0
		while x > prev_x and y > prev_y:
			steps.append("=")
			x -= 1
			y -= 1
		if d > 0:
			steps.append("+" if x == prev_x else "-")
		x = prev_x
		y = prev_y
	steps.reverse()
	return steps


static func _steps_to_op(steps: Array, a: String, b: String, start: int) -> Array:
	var op: Array = []
	var pos := start
	var ai := 0
	var bi := 0
	var i := 0
	while i < steps.size():
		var s: String = steps[i]
		var j := i
		while j < steps.size() and steps[j] == s:
			j += 1
		var count := j - i
		if s == "=":
			pos += count
			ai += count
			bi += count
		elif s == "-":
			op.append({"d": pos, "n": count})
			ai += count
		else:
			op.append({"i": pos, "s": b.substr(bi, count)})
			pos += count
			bi += count
		i = j
	return op


## The op that undoes `op`. `before` is the text op was applied to.
static func invert(op: Array, before: String) -> Array:
	var text := before
	var inv: Array = []
	for c in op:
		if is_ins(c):
			inv.push_front({"d": c.i, "n": str(c.s).length()})
			text = text.substr(0, c.i) + str(c.s) + text.substr(c.i)
		else:
			inv.push_front({"i": c.d, "s": text.substr(c.d, c.n)})
			text = text.substr(0, c.d) + text.substr(c.d + c.n)
	return inv


## Where a cursor at `offset` ends up after op.
static func map_offset(offset: int, op: Array) -> int:
	for c in op:
		if is_ins(c):
			if c.i < offset:
				offset += str(c.s).length()
		else:
			if offset >= c.d + c.n:
				offset -= c.n
			elif offset > c.d:
				offset = c.d
	return offset
