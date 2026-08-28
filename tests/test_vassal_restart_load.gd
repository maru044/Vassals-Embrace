extends SceneTree


const SLOT := 5


func _initialize() -> void:
	print("P0_HEARTBEAT restart initialize")
	create_timer(60.0).timeout.connect(_on_timeout)
	call_deferred("_run")


func _on_timeout() -> void:
	push_error("P0_TIMEOUT restart load exceeded 60 seconds")
	quit(124)


func _run() -> void:
	var checks: Array[String] = []
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var sm: Node = root.get_node_or_null("/root/SaveManager")
	if gm == null or sm == null:
		push_error("P0_FAIL required autoload missing")
		quit(2)
		return
	print("P0_HEARTBEAT restart autoloads ready")
	var data: Dictionary = sm.call("load_game_from_slot", SLOT)
	if data.is_empty():
		push_error("P0_FAIL restart slot missing")
		quit(3)
		return
	checks.append("restart slot exists: %s" % not data.is_empty())
	gm.call("deserialize", data)
	gm.set("loaded_from_save", true)

	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	if game == null:
		push_error("P0_FAIL restart game scene instantiate returned null")
		quit(4)
		return
	root.add_child(game)
	await process_frame
	await process_frame
	print("P0_HEARTBEAT restart game scene ready")

	checks.append("restart load Scotland liege: %s" % (gm.call("effective_liege", "Scotland") == "England"))
	checks.append("restart load Scotland type: %s" % (gm.call("effective_vassal_type", "Scotland") == "feudal"))
	checks.append("restart load Tyrone liege: %s" % (gm.call("effective_liege", "Tyrone") == "England"))
	checks.append("restart load Tyrone type: %s" % (gm.call("effective_vassal_type", "Tyrone") == "protectorate"))
	checks.append("restart load static Wales liege: %s" % (gm.call("effective_liege", "Wales") == "England"))
	checks.append("restart load static Wales type: %s" % (gm.call("effective_vassal_type", "Wales") == "autonomous"))
	checks.append("restart load static Northumberland liege: %s" % (gm.call("effective_liege", "Northumberland") == "England"))
	checks.append("restart load static Northumberland type: %s" % (gm.call("effective_vassal_type", "Northumberland") == "feudal"))
	checks.append("restart country cache populated: %s" % (gm.get("_country_list").size() > 0))
	checks.append("restart load date: %s" % (gm.get("year") == 1407 and gm.get("month") == 11))
	checks.append("restart load economy: %s" % (float(gm.get("country_gold").get("England", 0.0)) == 77.0))
	checks.append("restart load favor: %s" % (float(gm.get("player_favor").get("Scotland", 0.0)) == 88.0))
	checks.append("restart load war: %s" % (gm.get("wars").size() == 1 and int(gm.get("wars")[0].get("id", 0)) == 91))
	checks.append("restart game entered: %s" % bool(game.get("_in_game")))
	checks.append("restart player country: %s" % (str(game.get("_player_country_id")) == "England"))

	var legacy_data: Dictionary = data.duplicate(true)
	legacy_data.erase("runtime_liege")
	legacy_data.erase("runtime_vassal_type")
	gm.call("deserialize", legacy_data)
	checks.append("legacy save static Wales liege: %s" % (gm.call("effective_liege", "Wales") == "England"))
	checks.append("legacy save static Wales type: %s" % (gm.call("effective_vassal_type", "Wales") == "autonomous"))

	print("\n".join(checks))
	for line in checks:
		if line.ends_with(": false"):
			print("P0_RESTART_FAILED")
			quit(1)
			return
	print("P0_RESTART_DONE")
	quit(0)
