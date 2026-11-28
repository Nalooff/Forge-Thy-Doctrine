extends SceneTree
var fails := 0
func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1
func _initialize() -> void:
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_root().add_child(menu)
	await process_frame
	menu._freematch_cfg()
	await process_frame
	var found: OptionButton = null
	var stack: Array = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is OptionButton and (n as OptionButton).item_count == MapDefs.all().size():
			found = n
		stack.append_array(n.get_children())
	check(found != null, "the Freematch screen has a map list with all %d maps" % MapDefs.all().size())
	if found != null:
		var texts: Array = []
		for i in found.item_count:
			texts.append(found.get_item_text(i))
		check(texts.any(func(t): return String(t).contains("Solar System") and String(t).contains("1,000,000 km")) and texts.any(func(t): return String(t).contains("Shard Graveyard") and String(t).contains("100 km")), "maps show their size (e.g. Solar System 1,000,000 km)")
	var g: Node = get_root().get_node("Game")
	menu._sandbox_cfg(false)
	await process_frame
	check(true, "the Sandbox screen builds with the map list")
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
