extends SceneTree
## 引擎⑦-任务树系统冒烟测试（Master 8/14）：
## missions.json 加载 / 玩家任务列表 / 三态(completed/available/locked) / 各条件键判定
## （subject_of / favor_greater_than / flag_set / vassalize_any）/ 事件 flags 置位（老同盟）/
## complete_mission 领奖（grant_cb 限时CB 3年 + 威望/金币）/ 前置解锁 / 重复完成与未满足拒绝
## 运行：godot --headless --path . --script res://tests/test_missions.gd

const RESULT_PATH := "user://test_missions_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "Scotland")
	gm.call("_load_countries")

	# ① missions.json 加载（苏格兰 9 条任务）
	out.append("missions loaded (scotland_recover_isles): %s" % (not gm.call("get_mission", "scotland_recover_isles").is_empty()))
	out.append("missions loaded (scotland_great_britain): %s" % (not gm.call("get_mission", "scotland_great_britain").is_empty()))
	var player_missions: Array = gm.call("get_player_missions")
	out.append("Scotland player missions = 9: %s" % (player_missions.size() == 9))

	# ② 初始三态：无前置任务因条件未满足 locked；有前置任务因前置未完成也 locked
	out.append("recover_isles init locked: %s" % (gm.call("mission_state", "scotland_recover_isles") == "locked"))
	out.append("isles_guard init locked (parent): %s" % (gm.call("mission_state", "scotland_isles_guard") == "locked"))
	out.append("auld_alliance init locked (flag): %s" % (gm.call("mission_state", "scotland_auld_alliance") == "locked"))

	# ③ 附庸化判定（subject 语义：附庸+受保护国均算）：The Isles/Orkney/Shetland 成为苏格兰附庸 → 收回群岛 available
	gm.set("runtime_liege", {"The Isles": "Scotland", "Orkney": "Scotland", "Shetland": "Scotland"})
	out.append("recover_isles available after vassals: %s" % (gm.call("mission_state", "scotland_recover_isles") == "available"))

	# ④ 完成任务：收回群岛 → 领奖 → completed；重复完成被拒
	gm.set("country_prestige", {"Scotland": 50.0})
	var res_r: Dictionary = gm.call("complete_mission", "scotland_recover_isles")
	out.append("complete recover_isles ok: %s" % bool(res_r.get("ok", false)))
	out.append("recover_isles completed: %s" % gm.call("is_mission_completed", "scotland_recover_isles"))
	out.append("recover_isles state=completed: %s" % (gm.call("mission_state", "scotland_recover_isles") == "completed"))
	var res_r2: Dictionary = gm.call("complete_mission", "scotland_recover_isles")
	out.append("repeat complete rejected: %s" % (not bool(res_r2.get("ok", false))))

	# ⑤ 前置解锁 + 好感判定：群岛守护前置完成但好感未达标 → locked；达标 → available
	out.append("isles_guard unlocked but favor low -> locked: %s" % (gm.call("mission_state", "scotland_isles_guard") == "locked"))
	gm.set("player_favor", {"The Isles": 70.0, "Orkney": 70.0, "Shetland": 70.0})
	out.append("isles_guard available after favor: %s" % (gm.call("mission_state", "scotland_isles_guard") == "available"))

	# ⑥ 老同盟：事件 flag 置位 → available → 完成领威望+金币（reward_effects）
	gm.call("set_mission_flag", "scotland_auld_alliance_done")
	out.append("auld_alliance available after flag: %s" % (gm.call("mission_state", "scotland_auld_alliance") == "available"))
	gm.set("country_gold", {"Scotland": 100.0})
	var res_a: Dictionary = gm.call("complete_mission", "scotland_auld_alliance")
	out.append("complete auld_alliance ok: %s" % bool(res_a.get("ok", false)))
	out.append("auld_alliance prestige +10 (=60): %s" % (float(gm.get("country_prestige").get("Scotland", 0.0)) == 60.0))
	out.append("auld_alliance gold +25 (=125): %s" % (float(gm.get("country_gold").get("Scotland", 0.0)) == 125.0))

	# ⑦ vassalize_any（进军爱尔兰）：附庸任一爱尔兰国家 → available → 完成授爱尔兰全境附庸 CB 3年（36 月）
	gm.set("runtime_liege", {"Kildare": "Scotland"})
	out.append("march_into_ireland available after 1 vassal: %s" % (gm.call("mission_state", "scotland_march_into_ireland") == "available"))
	gm.call("complete_mission", "scotland_march_into_ireland")
	var cb_t: Dictionary = gm.get("cb_timers")
	var kildare_cb: int = int(cb_t.get("Scotland:Kildare:vassalize", 0))
	out.append("march reward grants vassalize CB 36mo: %s" % (kildare_cb == 36))
	var tyrone_cb: int = int(cb_t.get("Scotland:Tyrone:vassalize", 0))
	out.append("march reward covers all ireland_clan (Tyrone 36): %s" % (tyrone_cb == 36))

	# ⑧ 未完成条件时 complete 被拒（成立大不列颠 前置未完成 → locked）
	var res_g: Dictionary = gm.call("complete_mission", "scotland_great_britain")
	out.append("great_britain locked cannot complete: %s" % (not bool(res_g.get("ok", false))))

	# ⑨ 端到端畅通验证（Master 8/14）：完整链路推至「成立大不列颠」终局
	# 恢复群岛附庸 + 好感（⑦ 曾整体覆盖 runtime_liege，需重新加回）→ 群岛守护仍可完成
	var rl: Dictionary = gm.get("runtime_liege")
	rl["The Isles"] = "Scotland"
	rl["Orkney"] = "Scotland"
	rl["Shetland"] = "Scotland"
	gm.set("runtime_liege", rl)
	gm.set("player_favor", {"The Isles": 70.0, "Orkney": 70.0, "Shetland": 70.0, "Kildare": 70.0})
	# 群岛线：群岛守护（前置收回群岛已完成 + 好感达标）→ 完成
	var res_ig: Dictionary = gm.call("complete_mission", "scotland_isles_guard")
	out.append("⑨ isles_guard complete: %s" % bool(res_ig.get("ok", false)))
	# 征服爱尔兰：vassalize_all ireland_clan（全部部落附庸）
	var all_tribal: Array = gm.call("_mission_scope_ids", "ireland_clan")
	for tid in all_tribal:
		rl[str(tid)] = "Scotland"
	gm.set("runtime_liege", rl)
	out.append("⑨ conquer_ireland available: %s" % (gm.call("mission_state", "scotland_conquer_ireland") == "available"))
	gm.call("complete_mission", "scotland_conquer_ireland")
	out.append("⑨ conquer_ireland done: %s" % gm.call("is_mission_completed", "scotland_conquer_ireland"))
	# 推进前线：vassalize_any england_subject（静态初始英格兰附庸，如威尔士）→ 附庸威尔士
	rl = gm.get("runtime_liege")
	rl["Wales"] = "Scotland"
	gm.set("runtime_liege", rl)
	out.append("⑨ advance_the_front available: %s" % (gm.call("mission_state", "scotland_advance_the_front") == "available"))
	gm.call("complete_mission", "scotland_advance_the_front")
	out.append("⑨ advance done: %s" % gm.call("is_mission_completed", "scotland_advance_the_front"))
	# 百年战争胜利：苏格兰拥有 hundred_years_war，值推 100
	gm.set("situation_value", {"hundred_years_war": 100})
	out.append("⑨ hyv available: %s" % (gm.call("mission_state", "scotland_hundred_years_victory") == "available"))
	gm.call("complete_mission", "scotland_hundred_years_victory")
	out.append("⑨ hyv done: %s" % gm.call("is_mission_completed", "scotland_hundred_years_victory"))
	# 联合统治英格兰：前置 hyv 完成
	out.append("⑨ union_with_england available: %s" % (gm.call("mission_state", "scotland_union_with_england") == "available"))
	gm.call("complete_mission", "scotland_union_with_england")
	out.append("⑨ union done: %s" % gm.call("is_mission_completed", "scotland_union_with_england"))
	# 终局：成立大不列颠（三前置完成）
	out.append("⑨ great_britain available: %s" % (gm.call("mission_state", "scotland_great_britain") == "available"))
	var res_gb: Dictionary = gm.call("complete_mission", "scotland_great_britain")
	out.append("⑨ great_britain done (终局): %s" % bool(res_gb.get("ok", false)))

	# ⑩ 建筑条件/奖励（Master 8/14）：building_level（单省/全国总等级）+ upgrade_building（免费升级）
	gm.set("province_owner", {"伦敦": "Scotland", "格拉斯哥": "Scotland", "York": "England"})
	gm.set("province_buildings", {"伦敦": {"farm": 2, "market": 1, "brothel": 3, "fort": 1}, "格拉斯哥": {"brothel": 2}, "York": {"brothel": 4}})
	out.append("⑩ building_level 单省 gte 达标: %s" % gm.call("_check_mission_cond", {"building_level": {"province": "伦敦", "building": "brothel", "gte": 3}}))
	out.append("⑩ building_level 单省 gte 不达标: %s" % (not gm.call("_check_mission_cond", {"building_level": {"province": "伦敦", "building": "brothel", "gte": 4}})))
	out.append("⑩ building_total 全国妓院≥5: %s" % gm.call("_check_mission_cond", {"building_level": {"building": "brothel", "gte_total": 5}}))
	gm.call("_apply_effects_dict", "Scotland", {"upgrade_building": {"province": "伦敦", "building": "brothel"}})
	out.append("⑩ upgrade_building 伦敦妓院 3->4: %s" % (int(gm.get("province_buildings").get("伦敦", {}).get("brothel", 0)) == 4))
	gm.call("_apply_effects_dict", "Scotland", {"upgrade_building": {"province": "格拉斯哥", "building": "fort"}})
	out.append("⑩ upgrade_building 要塞不可升: %s" % (int(gm.get("province_buildings").get("格拉斯哥", {}).get("fort", 0)) == 0))

	# ⑪ 英格兰任务树（Master 8/14 样板）：建筑/附庸/好感/局势(value_lte) 条件 + 完整链路至「不列颠之主」终局
	gm.set("player_country_id", "England")
	var eng_missions: Array = gm.call("get_player_missions")
	out.append("⑪ England player missions = 7: %s" % (eng_missions.size() == 7))
	gm.set("province_owner", {"London": "England", "Southwest": "England", "Wessex": "England", "York": "England", "格拉斯哥": "Scotland"})
	gm.set("province_buildings", {"London": {"farm": 1, "market": 2, "brothel": 3, "fort": 1}, "Southwest": {"brothel": 2}, "Wessex": {"brothel": 2}, "York": {"brothel": 1}})
	# 无前置任务的三条先断言（条件满足 → available）
	out.append("⑪ capital_market available (London market≥2): %s" % (gm.call("mission_state", "england_capital_market") == "available"))
	gm.set("runtime_liege", {"Wales": "England"})
	gm.call("set_mission_flag", "england_welsh_revolt_suppressed")
	out.append("⑪ subdue_wales available: %s" % (gm.call("mission_state", "england_subdue_wales") == "available"))
	gm.set("situation_value", {"hundred_years_war": 15})
	out.append("⑪ hundred_years available (value_lte≤20): %s" % (gm.call("mission_state", "england_hundred_years") == "available"))
	# 先完成无前置任务，再断言有前置的子任务
	gm.call("complete_mission", "england_capital_market")
	gm.call("complete_mission", "england_subdue_wales")
	gm.call("complete_mission", "england_hundred_years")
	out.append("⑪ brothel_network available after parent (total≥8): %s" % (gm.call("mission_state", "england_brothel_network") == "available"))
	gm.set("player_favor", {"Northumberland": 65.0, "Westmorland": 65.0, "York": 65.0})
	out.append("⑪ northern_loyalty available after parent: %s" % (gm.call("mission_state", "england_northern_loyalty") == "available"))
	# 完整链路 → 不列颠之主终局
	gm.call("complete_mission", "england_brothel_network")
	gm.call("complete_mission", "england_northern_loyalty")
	gm.call("complete_mission", "england_france_claim")
	out.append("⑪ britain_lord available: %s" % (gm.call("mission_state", "england_britain_lord") == "available"))
	var res_e: Dictionary = gm.call("complete_mission", "england_britain_lord")
	out.append("⑪ britain_lord done (终局): %s" % bool(res_e.get("ok", false)))
	out.append("⑪ brothel reward upgraded London 3->4: %s" % (int(gm.get("province_buildings").get("London", {}).get("brothel", 0)) == 4))

	# ⑫ 威尔士任务树（Master 8/14：独立是完成条件而非奖励）
	gm.set("player_country_id", "Wales")
	var wal_missions: Array = gm.call("get_player_missions")
	out.append("⑫ Wales player missions = 7: %s" % (wal_missions.size() == 7))
	gm.set("province_owner", {"Wales": "Wales", "London": "England"})
	gm.set("province_buildings", {"Wales": {"market": 2, "brothel": 3, "fort": 1}, "London": {"brothel": 2}})
	# 独立（无宗主）+ 卡迪夫商埠（建筑）+ 凯尔特同盟（附庸）三条无前置先断言
	# runtime_liege["Wales"]="" = 显式独立（独立战争胜利后置位；erase 会回退静态 liege=England）
	gm.set("runtime_liege", {"Wales": ""})
	out.append("⑫ wales_independence available (independent): %s" % (gm.call("mission_state", "wales_independence") == "available"))
	out.append("⑫ wales_market_heart available (market≥2): %s" % (gm.call("mission_state", "wales_market_heart") == "available"))
	gm.set("runtime_liege", {"Wales": "", "Kildare": "Wales"})
	out.append("⑫ wales_irish_pact available (vassalize_any): %s" % (gm.call("mission_state", "wales_irish_pact") == "available"))
	# 完成无前置三条
	gm.call("complete_mission", "wales_independence")
	gm.call("complete_mission", "wales_market_heart")
	gm.call("complete_mission", "wales_irish_pact")
	# 犬牙武装（前置独立，army_limit≥8）：BASE 5+1省×2=7，加 army_cap 修正 +3 → 10
	gm.call("_add_modifier", "Wales", "army_cap", 3, 12)
	out.append("⑫ wales_march_army available (army_limit≥8): %s" % (gm.call("mission_state", "wales_march_army") == "available"))
	# 犬娘欢场（前置卡迪夫，Wales 省妓院≥3）
	out.append("⑫ wales_brothel_dens available (brothel≥3): %s" % (gm.call("mission_state", "wales_brothel_dens") == "available"))
	# 向英格兰复仇（前置 独立+凯尔特，附庸英格兰原附庸=约克）
	gm.set("runtime_liege", {"Wales": "", "Kildare": "Wales", "York": "Wales"})
	out.append("⑫ wales_revenge available (england_subject): %s" % (gm.call("mission_state", "wales_revenge") == "available"))
	# 完整链路 → 红龙燎原终局
	gm.call("complete_mission", "wales_march_army")
	gm.call("complete_mission", "wales_brothel_dens")
	gm.call("complete_mission", "wales_revenge")
	out.append("⑫ wales_britain_fire available: %s" % (gm.call("mission_state", "wales_britain_fire") == "available"))
	var res_w: Dictionary = gm.call("complete_mission", "wales_britain_fire")
	out.append("⑫ wales_britain_fire done (终局): %s" % bool(res_w.get("ok", false)))

	# ⑬ 达勒姆任务树（Master 8/14：圣女堕落度局势主题，战争少）
	gm.set("player_country_id", "Durham")
	var dur_missions: Array = gm.call("get_player_missions")
	out.append("⑬ Durham player missions = 7: %s" % (dur_missions.size() == 7))
	gm.set("province_owner", {"Durham": "Durham"})
	gm.set("province_buildings", {"Durham": {"market": 2, "brothel": 3, "fort": 1}})
	# 圣洁线：堕落度≤10 → 北境坚堡 → 教会权威（英格兰好感≥60）
	gm.set("situation_value", {"corruption_durham": 5})
	out.append("⑬ durham_holy_wall available (corruption≤10): %s" % (gm.call("mission_state", "durham_holy_wall") == "available"))
	gm.call("complete_mission", "durham_holy_wall")
	gm.set("player_favor", {"England": 70.0})
	out.append("⑬ durham_church_authority available (favor England≥60): %s" % (gm.call("mission_state", "durham_church_authority") == "available"))
	# 堕落线：堕落度 20→50→90
	gm.set("situation_value", {"corruption_durham": 25})
	out.append("⑬ durham_first_sin available (corruption≥20): %s" % (gm.call("mission_state", "durham_first_sin") == "available"))
	gm.call("complete_mission", "durham_first_sin")
	gm.set("situation_value", {"corruption_durham": 50})
	out.append("⑬ durham_glory_hole available (corruption≥50): %s" % (gm.call("mission_state", "durham_glory_hole_fame") == "available"))
	gm.call("complete_mission", "durham_glory_hole_fame")
	gm.set("situation_value", {"corruption_durham": 90})
	out.append("⑬ durham_full_corruption available (corruption≥90): %s" % (gm.call("mission_state", "durham_full_corruption") == "available"))
	gm.call("complete_mission", "durham_full_corruption")
	# 内政：达勒姆市场≥2 → 采邑繁荣
	out.append("⑬ durham_market_heart available (market≥2): %s" % (gm.call("mission_state", "durham_market_heart") == "available"))
	gm.call("complete_mission", "durham_market_heart")
	# 终局：圣女之名（彻底堕落 + 采邑繁荣）
	out.append("⑬ durham_saint_or_sinner available: %s" % (gm.call("mission_state", "durham_saint_or_sinner") == "available"))
	var res_d: Dictionary = gm.call("complete_mission", "durham_saint_or_sinner")
	out.append("⑬ durham_saint_or_sinner done (终局): %s" % bool(res_d.get("ok", false)))

	# ⑭ 塞壬群岛任务树（Master 8/14：海盗劫掠 raids_gte 条件，与海盗联盟国际组织无关）
	gm.set("player_country_id", "The Isles")
	var isles_missions: Array = gm.call("get_player_missions")
	out.append("⑭ The Isles player missions = 7: %s" % (isles_missions.size() == 7))
	gm.set("province_owner", {"The Isles": "The Isles"})
	gm.set("province_buildings", {"The Isles": {"brothel": 2, "market": 2, "fort": 1}})
	# 劫掠线：raids_gte（add_raid 累计）
	gm.call("add_raid", 5)
	out.append("⑭ first_raid available (raids≥3): %s" % (gm.call("mission_state", "isles_first_raid") == "available"))
	gm.call("complete_mission", "isles_first_raid")
	gm.call("add_raid", 5)
	out.append("⑭ sea_king available (raids≥8): %s" % (gm.call("mission_state", "isles_sea_king") == "available"))
	# 巢穴线：建筑
	out.append("⑭ isles_tavern available (brothel≥2): %s" % (gm.call("mission_state", "isles_tavern") == "available"))
	gm.call("complete_mission", "isles_tavern")
	out.append("⑭ isles_market_cove available (market≥2): %s" % (gm.call("mission_state", "isles_market_cove") == "available"))
	# 掠夺线：附庸爱尔兰
	gm.set("runtime_liege", {"Kildare": "The Isles"})
	out.append("⑭ isles_celtic_raid available: %s" % (gm.call("mission_state", "isles_celtic_raid") == "available"))
	# 完整链路 → 北海霸主终局
	gm.call("complete_mission", "isles_sea_king")
	gm.call("add_raid", 10)
	gm.call("complete_mission", "isles_grand_loot")
	gm.call("complete_mission", "isles_market_cove")
	gm.call("complete_mission", "isles_celtic_raid")
	out.append("⑭ isles_north_sea_lord available: %s" % (gm.call("mission_state", "isles_north_sea_lord") == "available"))
	var res_n: Dictionary = gm.call("complete_mission", "isles_north_sea_lord")
	out.append("⑭ isles_north_sea_lord done (终局): %s" % bool(res_n.get("ok", false)))

	# ⑮ 爱尔兰通用任务树（Master 8/14：成为至高王 → 统一爱尔兰局势 → 吞并全岛；16 部共用）
	gm.set("player_country_id", "Tyrone")
	var ire_missions: Array = gm.call("get_player_missions")
	out.append("⑮ Tyrone player missions = 6: %s" % (ire_missions.size() == 6))
	# 条件1：成为至高王（is_high_king）
	gm.set("high_king_id", "Tyrone")
	out.append("⑮ ireland_high_king available (is_high_king): %s" % (gm.call("mission_state", "ireland_high_king") == "available"))
	gm.call("complete_mission", "ireland_high_king")
	# 统一局势：unify_ireland 40→80→100
	gm.set("situation_value", {"unify_ireland": 40})
	out.append("⑮ ireland_unity_1 available (unify≥40): %s" % (gm.call("mission_state", "ireland_unity_1") == "available"))
	gm.call("complete_mission", "ireland_unity_1")
	gm.set("situation_value", {"unify_ireland": 80})
	out.append("⑮ ireland_unity_2 available (unify≥80): %s" % (gm.call("mission_state", "ireland_unity_2") == "available"))
	gm.call("complete_mission", "ireland_unity_2")
	gm.set("situation_value", {"unify_ireland": 100})
	out.append("⑮ ireland_unity_3 available (unify≥100): %s" % (gm.call("mission_state", "ireland_unity_3") == "available"))
	gm.call("complete_mission", "ireland_unity_3")
	# 部族堡垒：全国市场总等级≥3
	gm.set("province_owner", {"Tyrone": "Tyrone", "Ulster": "Ulster", "Munster": "Munster"})
	gm.set("province_buildings", {"Tyrone": {"market": 3}, "Ulster": {"market": 1}, "Munster": {"market": 1}})
	out.append("⑮ ireland_bastion available (market total≥3): %s" % (gm.call("mission_state", "ireland_bastion") == "available"))
	gm.call("complete_mission", "ireland_bastion")
	# 终局：全岛之主 → 吞并所有爱尔兰国家（annex_scope）
	out.append("⑮ ireland_all_island available: %s" % (gm.call("mission_state", "ireland_all_island") == "available"))
	var res_ir: Dictionary = gm.call("complete_mission", "ireland_all_island")
	out.append("⑮ ireland_all_island done (吞并全岛): %s" % bool(res_ir.get("ok", false)))
	out.append("⑮ annex Ulster province -> Tyrone: %s" % (str(gm.get("province_owner").get("Ulster", "")) == "Tyrone"))

	# ⑯ 诺森伯兰任务树（Master 8/14：珀西叛乱/北境战姬主题）
	gm.set("player_country_id", "Northumberland")
	var nor_missions: Array = gm.call("get_player_missions")
	out.append("⑯ Northumberland player missions = 7: %s" % (nor_missions.size() == 7))
	gm.set("province_owner", {"Northumberland": "Northumberland", "London": "England"})
	gm.set("province_buildings", {"Northumberland": {"market": 2, "brothel": 2, "fort": 1}, "London": {"market": 1}})
	# 反叛线：独立（independent）
	gm.set("runtime_liege", {"Northumberland": ""})
	out.append("⑯ northumberland_revolt available (independent): %s" % (gm.call("mission_state", "northumberland_revolt") == "available"))
	gm.call("complete_mission", "northumberland_revolt")
	# 内政线：边疆市镇 → 战地营帐
	out.append("⑯ northumberland_march_town available (market≥2): %s" % (gm.call("mission_state", "northumberland_march_town") == "available"))
	gm.call("complete_mission", "northumberland_march_town")
	out.append("⑯ northumberland_war_camp available (brothel≥2): %s" % (gm.call("mission_state", "northumberland_war_camp") == "available"))
	# 战姬军团：army_limit≥10（BASE 5+1省×2=7，加 army_cap +3 → 10）
	gm.call("_add_modifier", "Northumberland", "army_cap", 3, 12)
	out.append("⑯ northumberland_war_machine available (army_limit≥10): %s" % (gm.call("mission_state", "northumberland_war_machine") == "available"))
	# 篡位线：折断玫瑰（附庸英格兰原附庸约克）→ 觊觎王座（联统 CB）
	gm.set("runtime_liege", {"Northumberland": "", "York": "Northumberland"})
	out.append("⑯ northumberland_weaken_england available: %s" % (gm.call("mission_state", "northumberland_weaken_england") == "available"))
	gm.call("complete_mission", "northumberland_weaken_england")
	out.append("⑯ northumberland_claim_throne available: %s" % (gm.call("mission_state", "northumberland_claim_throne") == "available"))
	# 完整链路 → 北境女王终局
	gm.call("complete_mission", "northumberland_war_machine")
	gm.call("complete_mission", "northumberland_war_camp")
	gm.call("complete_mission", "northumberland_claim_throne")
	out.append("⑯ northumberland_britain_queen available: %s" % (gm.call("mission_state", "northumberland_britain_queen") == "available"))
	var res_nb: Dictionary = gm.call("complete_mission", "northumberland_britain_queen")
	out.append("⑯ northumberland_britain_queen done (终局): %s" % bool(res_nb.get("ok", false)))

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
