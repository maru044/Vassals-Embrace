extends SceneTree


const SLOT := 5


func _initialize() -> void:
	print("P0_HEARTBEAT initialize")
	create_timer(60.0).timeout.connect(_on_timeout)
	call_deferred("_run")


func _on_timeout() -> void:
	push_error("P0_TIMEOUT create/in-game load exceeded 60 seconds")
	quit(124)


func _run() -> void:
	var checks: Array[String] = []
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var sm: Node = root.get_node_or_null("/root/SaveManager")
	if gm == null or sm == null:
		push_error("P0_FAIL required autoload missing")
		quit(2)
		return
	print("P0_HEARTBEAT autoloads ready")
	sm.call("delete_slot", SLOT)

	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	if game == null:
		push_error("P0_FAIL game scene instantiate returned null")
		quit(3)
		return
	root.add_child(game)
	await process_frame
	await process_frame
	print("P0_HEARTBEAT game scene ready")

	gm.call("start_new_game", "England")
	checks.append("new-game country cache populated: %s" % (gm.get("_country_list").size() > 0))
	var feudal: Dictionary = gm.call("establish_requirement", "England", "Scotland", "vassalize")
	var protected: Dictionary = gm.call("establish_requirement", "England", "Tyrone", "protectorate")
	gm.set("year", 1407)
	gm.set("month", 11)
	gm.set("country_gold", {"England": 77.0, "Scotland": 33.0, "Tyrone": 44.0})
	gm.set("country_prestige", {"England": 66.0, "Scotland": 22.0, "Tyrone": 55.0})
	gm.set("player_favor", {"Scotland": 88.0, "Tyrone": 79.0})
	gm.set("wars", [{"id": 91, "attacker": ["England"], "defender": ["France"], "status": "active"}])

	checks.append("setup feudal relation: %s" % bool(feudal.get("ok", false)))
	checks.append("setup protectorate relation: %s" % bool(protected.get("ok", false)))
	checks.append("before save Scotland liege: %s" % (gm.call("effective_liege", "Scotland") == "England"))
	checks.append("before save Tyrone liege: %s" % (gm.call("effective_liege", "Tyrone") == "England"))
	checks.append("before save static Wales liege: %s" % (gm.call("effective_liege", "Wales") == "England"))
	checks.append("before save static Northumberland liege: %s" % (gm.call("effective_liege", "Northumberland") == "England"))

	var save_panel: Node = game.get("_save_panel")
	if save_panel == null:
		push_error("P0_FAIL save panel missing")
		quit(4)
		return
	save_panel.call("_on_save", SLOT)
	print("P0_HEARTBEAT save completed")
	var saved: Dictionary = sm.call("load_game_from_slot", SLOT)
	checks.append("save contains runtime_liege: %s" % (saved.get("runtime_liege", {}).get("Scotland", "") == "England"))
	checks.append("save contains runtime_vassal_type: %s" % (saved.get("runtime_vassal_type", {}).get("Tyrone", "") == "protectorate"))
	checks.append("save leaves static Wales out of runtime overrides: %s" % not saved.get("runtime_liege", {}).has("Wales"))
	checks.append("save path: %s" % ProjectSettings.globalize_path("user://saves/slot_6.json"))

	gm.set("runtime_liege", {})
	gm.set("runtime_vassal_type", {})
	gm.set("year", 9999)
	gm.set("country_gold", {})
	gm.set("wars", [])
	save_panel.call("_on_load", SLOT)
	print("P0_HEARTBEAT in-game load completed")

	checks.append("in-game load Scotland liege: %s" % (gm.call("effective_liege", "Scotland") == "England"))
	checks.append("in-game load Scotland type: %s" % (gm.call("effective_vassal_type", "Scotland") == "feudal"))
	checks.append("in-game load Tyrone liege: %s" % (gm.call("effective_liege", "Tyrone") == "England"))
	checks.append("in-game load Tyrone type: %s" % (gm.call("effective_vassal_type", "Tyrone") == "protectorate"))
	checks.append("in-game load static Wales liege: %s" % (gm.call("effective_liege", "Wales") == "England"))
	checks.append("in-game load static Wales type: %s" % (gm.call("effective_vassal_type", "Wales") == "autonomous"))
	checks.append("in-game load static Northumberland liege: %s" % (gm.call("effective_liege", "Northumberland") == "England"))
	checks.append("in-game load date: %s" % (gm.get("year") == 1407 and gm.get("month") == 11))
	checks.append("in-game load economy: %s" % (float(gm.get("country_gold").get("England", 0.0)) == 77.0))
	checks.append("in-game load favor: %s" % (float(gm.get("player_favor").get("Scotland", 0.0)) == 88.0))
	checks.append("in-game load war: %s" % (gm.get("wars").size() == 1 and int(gm.get("wars")[0].get("id", 0)) == 91))

	print("\n".join(checks))
	for line in checks:
		if line.ends_with(": false"):
			print("P0_CREATE_FAILED")
			quit(1)
			return
	print("P0_CREATE_DONE")
	quit(0)
