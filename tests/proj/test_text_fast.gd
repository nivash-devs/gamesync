extends SceneTree
## Friends' typing is applied line by line; the editor must end up with exactly the room's text.

const Plugin := preload("res://addons/gamesync/plugin.gd")
var passed := 0
var failed := 0

func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok   ", label)
	else:
		failed += 1
		print("FAIL ", label)

func case(before: String, after: String, label: String) -> void:
	var ce := CodeEdit.new()
	get_root().add_child(ce)
	ce.text = before
	Plugin._set_text_fast(ce, before, after)
	# Same result as replacing the whole text the slow way.
	var ref := CodeEdit.new()
	get_root().add_child(ref)
	ref.text = after
	check(ce.text == ref.text, label)
	ce.queue_free()
	ref.queue_free()

func _initialize() -> void:
	case("a\nb\nc", "a\nbX\nc", "typing inside a line")
	case("func f():\n\tpass\n", "func f():\n\treturn 1\n", "changing an indented line")
	case("a\nb\nc", "a\nb\nnew\nc", "adding a line")
	case("a\nb\nc", "a\nc", "deleting a line")
	case("a\nb", "a\r\nb2", "text with Windows line endings")
	case("", "hello", "empty script")
	case("x\ny\nz", "X\ny\nZ", "two lines change at once")
	print("passed %d | failed %d" % [passed, failed])
	quit(1 if failed > 0 else 0)
