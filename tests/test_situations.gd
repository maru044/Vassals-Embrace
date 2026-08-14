extends SceneTree
## 引擎⑥-局势系统冒烟测试（Master 8/14）：
## situations.json 加载 / 初始值（initial_stage 与 initial_zero）/ 玩家拥有判定 /
## change_situation 增减 + clamp / 玩家未拥有不生效 / 事件 effects.situations 落地
## 运行：godot --headless --path . --script res://tests/test_situations.gd

const RESULT_PATH := "user://test_situations_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame

	# ① 局势表加载（3 条：百年战争/统一爱尔兰/圣女堕落度）
	out.append("situations loaded (hundred_years_war): %s" % (not gm.call("get_situation", "hundred_years_war").is_empty()))
	out.append("situations loaded (corruption_durham): %s" % (not gm.call("get_situation", "corruption_durham").is_empty()))
	out.append("situations loaded (unify_ireland): %s" % (not gm.call("get_situation", "unify_ireland").is_empty()))

	# ② 初始值：百年战争 III=50；统一爱尔兰 initial_zero=0；圣女堕落度 initial_zero=0
	gm.set("player_country_id", "England")
	gm.call("_init_situations")
	out.append("init hundred_years_war = 50: %s" % (gm.call("get_situation_value", "hundred_years_war") == 50))
	out.append("init unify_ireland = 0: %s" % (gm.call("get_situation_value", "unify_ireland") == 0))
	out.append("init corruption_durham = 0: %s" % (gm.call("get_situation_value", "corruption_durham") == 0))

	# ③ 玩家拥有判定：England 拥有百年战争（scope 含 England/Scotland），不拥有统一爱尔兰
	out.append("England owns hundred_years_war: %s" % gm.call("player_owns_situation", "hundred_years_war"))
	out.append("England NOT own unify_ireland: %s" % (not gm.call("player_owns_situation", "unify_ireland")))
	# 动态至高王（Master 8/14）：初始蒂龙拥有统一爱尔兰；夺取至高王后拥有者切换
	gm.set("high_king_id", "Tyrone")
	gm.set("player_country_id", "Tyrone")
	out.append("Tyrone (initial high king) owns unify_ireland: %s" % gm.call("player_owns_situation", "unify_ireland"))
	gm.call("set_high_king", "Ulster")   # Ulster 夺取至高王
	gm.set("player_country_id", "Ulster")
	out.append("Ulster (new high king) owns unify_ireland: %s" % gm.call("player_owns_situation", "unify_ireland"))
	gm.set("player_country_id", "Tyrone")
	out.append("Tyrone lost high king -> NOT own: %s" % (not gm.call("player_owns_situation", "unify_ireland")))

	# ④ change_situation：百年战争 +15 → 65；clamp 到 100；非拥有者（Durham 堕落在 Tyrone 视角）不生效
	gm.set("player_country_id", "England")
	gm.call("change_situation", "hundred_years_war", 15.0)
	out.append("hundred_years_war 50+15 = 65: %s" % (gm.call("get_situation_value", "hundred_years_war") == 65))
	gm.call("change_situation", "hundred_years_war", 1000.0)
	out.append("hundred_years_war clamp <=100: %s" % (gm.call("get_situation_value", "hundred_years_war") == 100))
	# 玩家不是 Durham → 堕落度不变
	gm.call("change_situation", "corruption_durham", 15.0)
	out.append("England change Durham corruption no-op (0): %s" % (gm.call("get_situation_value", "corruption_durham") == 0))
	# 玩家切到 Durham → 生效 +15
	gm.set("player_country_id", "Durham")
	gm.call("change_situation", "corruption_durham", 15.0)
	out.append("Durham corruption 0+15 = 15: %s" % (gm.call("get_situation_value", "corruption_durham") == 15))

	# ⑤ 阶段：15 → stage 0（I）；65 → stage 3（IV）；100 → stage 4（V）
	gm.set("player_country_id", "England")
	gm.call("change_situation", "hundred_years_war", -100.0)   # 100 → 0
	out.append("hundred_years_war stage(0) = 0: %s" % (gm.call("get_situation_stage", "hundred_years_war") == 0))
	gm.call("change_situation", "hundred_years_war", 65.0)     # 0 → 65
	out.append("hundred_years_war stage(65) = 3: %s" % (gm.call("get_situation_stage", "hundred_years_war") == 3))
	gm.call("change_situation", "hundred_years_war", 40.0)     # 65 → 100
	out.append("hundred_years_war stage(100) = 4: %s" % (gm.call("get_situation_stage", "hundred_years_war") == 4))

	# ⑥ 事件 effects.situations 落地（玩家 England，百年战争 +10）
	gm.set("player_country_id", "England")
	gm.call("_apply_option_effects", "England", {"effects": {"situations": [{"id": "hundred_years_war", "delta": -50}]}}, "test_ev")
	out.append("event situation -50: 100->50: %s" % (gm.call("get_situation_value", "hundred_years_war") == 50))
	# 玩家拥有列表只含百年战争（England 视角）
	var list: Array = gm.call("get_player_situations")
	out.append("player situations (England) = 1: %s" % (list.size() == 1))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
