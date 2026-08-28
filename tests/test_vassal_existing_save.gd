extends SceneTree


const SLOT := 4


func _initialize() -> void:
	print("P0_HEARTBEAT existing-save initialize")
	create_timer(60.0).timeout.connect(_on_timeout)
	call_deferred("_run")


func _on_timeout() -> void:
	push_error("P0_TIMEOUT existing-save load exceeded 60 seconds")
	quit(124)


func _run() -> void:
	var checks: Array[String] = []
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var sm: Node = root.get_node_or_null("/root/SaveManager")
	if gm == null or sm == null:
		push_error("P0_FAIL required autoload missing")
		quit(2)
		return

	var data: Dictionary = sm.call("load_game_from_slot", SLOT)
	if data.is_empty():
		push_error("P0_FAIL existing save fixture missing")
		quit(3)
		return
	print("P0_HEARTBEAT existing-save fixture loaded")
	checks.append("existing save player England: %s" % (str(data.get("player_country_id", "")) == "England"))
	checks.append("existing save runtime_liege empty: %s" % data.get("runtime_liege", {}).is_empty())
	checks.append("existing save runtime_vassal_type empty: %s" % data.get("runtime_vassal_type", {}).is_empty())

	gm.call("deserialize", data)
	gm.set("loaded_from_save", true)
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	if game == null:
		push_error("P0_FAIL existing-save game scene instantiate returned null")
		quit(4)
		return
	root.add_child(game)
	await process_frame
	await process_frame
	print("P0_HEARTBEAT existing-save game scene ready")

	checks.append("existing save Wales liege: %s" % (gm.call("effective_liege", "Wales") == "England"))
	checks.append("existing save Wales type: %s" % (gm.call("effective_vassal_type", "Wales") == "autonomous"))
	checks.append("existing save Northumberland liege: %s" % (gm.call("effective_liege", "Northumberland") == "England"))
	checks.append("existing save Northumberland type: %s" % (gm.call("effective_vassal_type", "Northumberland") == "feudal"))
	checks.append("existing save Isle of Man liege: %s" % (gm.call("effective_liege", "Isle of Man") == "England"))
	checks.append("existing save Isle of Man type: %s" % (gm.call("effective_vassal_type", "Isle of Man") == "protectorate"))
	checks.append("existing save country cache populated: %s" % (gm.get("_country_list").size() > 0))
	checks.append("existing save economy preserved: %s" % (gm.get("country_gold") == data.get("country_gold", {})))
	checks.append("existing save favor preserved: %s" % (gm.get("player_favor") == data.get("player_favor", {})))
	checks.append("existing save wars preserved: %s" % (gm.get("wars") == data.get("wars", [])))
	checks.append("existing save game entered: %s" % bool(game.get("_in_game")))

	print("\n".join(checks))
	for line in checks:
		if line.ends_with(": false"):
			print("P0_EXISTING_SAVE_FAILED")
			quit(1)
			return
	print("P0_EXISTING_SAVE_DONE")
	quit(0)
