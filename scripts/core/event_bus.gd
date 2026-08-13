extends Node
## 全局事件总线（Autoload 单例）。
## 设计原则：UI 只发事件、系统只响应事件、LLM 层发异步事件——各系统互相独立、可插拔。
## 订阅方式：EventBus.<signal>.connect(<callback>)
## 发送方式：EventBus.<signal>.emit(...)

# ---------- 1. UI / 导航 ----------
signal start_game
signal load_game
signal configure_api
signal quit_game
signal country_selected(country_id: int)
signal confirm_country
signal open_panel(panel_id: String)
signal close_panel(panel_id: String)
signal end_month

# ---------- 2. 回合 / 时间 ----------
signal month_advanced(month: int, year: int)
signal year_advanced(year: int)

# ---------- 3. 国家 / 资源 ----------
signal treasury_changed(country_id: int, value: int)
signal prestige_changed(country_id: int, value: int)
signal army_changed(country_id: int, units: int)
signal favor_changed(target_id: String, value: float)
signal income_changed(country_id: int, value: int)
signal building_changed(province_id: int, building: String, level: int)
signal province_owner_changed(province_id: int, old_owner: int, new_owner: int)

# ---------- 4. 战争 / 军事 ----------
signal war_started(war_id: int)
signal war_ended(war_id: int)
signal battle_resolved(winner_id: int, loser_id: int)
signal siege_started(province_id: int)
signal siege_progress(province_id: int, progress: float)
signal siege_finished(province_id: int, attacker_id: int)
signal peace_signed(war_id: int)

# ---------- 5. 外交 / 组织 ----------
signal diplomatic_play_started(play_id: int)
signal diplomatic_play_resolved(play_id: int)
signal vassal_changed(liege_id: int, vassal_id: int, relation: String)
signal union_changed(lead_id: int, member_id: int, active: bool)
signal organization_changed(org_id: int)
signal diplomatic_relation_changed(actor: String, target: String, relation: String)   # 引擎④-CB：要求X同意后附庸/受保护国/联合统治关系建立

# ---------- 6. 系统 ----------
signal event_triggered(event_id: String)
signal event_resolved(event_id: String)
signal mission_completed(mission_id: String)
signal mission_unlocked(mission_id: String)
signal situation_changed(situation_id: String, value: int)

# ---------- 7. LLM ----------
signal llm_request_started
signal llm_response_received(response: Dictionary)
signal tool_executed(tool_name: String, result: Dictionary)

# ---------- 8. 后宫 ----------
signal harem_member_added(country_id: int, member_name: String)
signal harem_member_changed(country_id: int, member_name: String)
signal service_tendency_changed(country_id: int, value: int)
