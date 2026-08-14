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

	# ⑦ 局势事件触发（Master 8/14）：type=situation + trigger.situation；玩家拥有才可能入队
	var ev_cfg := {
		"hw_france_push": "hundred_years_war",
		"hw_england_push": "hundred_years_war",
		"hw_decisive": "hundred_years_war",
		"iu_tribal_gathering": "unify_ireland",
		"iu_beltane": "unify_ireland",
		"iu_british_threat": "unify_ireland",
		"cd_glory_hole": "corruption_durham",
		"cd_altar_sacrilege": "corruption_durham",
		"cd_high_mass": "corruption_durham",
		"cd_pilgrimage": "corruption_durham",
		"cd_rumor": "corruption_durham",
	}
	var all_ok := true
	for eid in ev_cfg:
		var ev: Dictionary = gm.call("get_event", eid)
		if str(ev.get("type", "")) != "situation":
			all_ok = false
		if str(ev.get("trigger", {}).get("situation", "")) != ev_cfg[eid]:
			all_ok = false
	out.append("situation events all type=situation + bound correctly: %s" % all_ok)
	# ⑦b 阵营映射验证（Master 8/14）：百年战争双方拥有者阵营相反（England→英国胜利0 / Scotland→法国胜利100，老同盟）
	var hw_sides_ok := true
	var hw_opts_ok := true
	for eid in ["hw_france_push", "hw_england_push", "hw_decisive"]:
		var ev: Dictionary = gm.call("get_event", eid)
		var s: Dictionary = ev.get("sides", {})
		if str(s.get("England", "")) != "england" or str(s.get("Scotland", "")) != "france":
			hw_sides_ok = false
		for o in ev.get("options", []):
			if not o.has("side"):
				hw_opts_ok = false
	out.append("hw_* sides map England->england / Scotland->france: %s" % hw_sides_ok)
	out.append("hw_* all options have side tag: %s" % hw_opts_ok)
	# 拥有者判定驱动的触发范围：England 拥有百年战争（不拥有统一爱尔兰/堕落度）
	gm.set("player_country_id", "England")
	out.append("England owns hundred_years_war (triggerable): %s" % gm.call("player_owns_situation", "hundred_years_war"))
	out.append("England NOT own unify_ireland (not triggerable): %s" % (not gm.call("player_owns_situation", "unify_ireland")))
	out.append("England NOT own corruption_durham (not triggerable): %s" % (not gm.call("player_owns_situation", "corruption_durham")))
	gm.set("player_country_id", "Durham")
	out.append("Durham owns corruption_durham (triggerable): %s" % gm.call("player_owns_situation", "corruption_durham"))
	# 局势事件落地 → 局势值变化（用 cd 事件选项验证堕落度上升）
	gm.set("player_country_id", "Durham")
	gm.set("situation_value", {"corruption_durham": 0})
	gm.call("_apply_option_effects", "Durham", {"effects": {"situations": [{"id": "corruption_durham", "delta": 15}]}}, "test_cd")
	out.append("cd_glory_hole delta +15: 0->15: %s" % (gm.call("get_situation_value", "corruption_durham") == 15))

	# ⑧ 随机触发验证（Master 8/14）：玩家拥有局势 → _tick_events 会将其局势事件入玩家队列
	# 单次 tick 命中概率仅 weight/100（cd_* 各 8%），故循环 60 个月（5 年）累积验证归属正确
	gm.set("player_country_id", "Durham")
	gm.set("situation_value", {"corruption_durham": 0, "hundred_years_war": 50, "unify_ireland": 0})
	var cd_fired := false
	for i in 60:
		gm.set("player_event_queue", [])
		Dice._rng.seed = 42 + i   # 每个月独立种子，序列可复现
		gm.call("_tick_events")
		var q: Array = gm.get("player_event_queue")
		for item in q:
			if str(item.get("event_id", "")).begins_with("cd_"):
				cd_fired = true
	out.append("Durham 60mo tick -> cd event fired: %s" % cd_fired)
	# 非拥有者不触发：切到 England（不拥有堕落度），循环同样月份，验证不出现 cd_*
	gm.set("player_country_id", "England")
	var cd_leaked := false
	for i in 60:
		gm.set("player_event_queue", [])
		Dice._rng.seed = 42 + i
		gm.call("_tick_events")
		var q2: Array = gm.get("player_event_queue")
		for item in q2:
			if str(item.get("event_id", "")).begins_with("cd_"):
				cd_leaked = true
	out.append("England 60mo tick -> NO cd event leaked: %s" % (not cd_leaked))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
