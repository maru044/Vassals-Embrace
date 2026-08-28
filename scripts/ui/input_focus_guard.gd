extends RefCounted


static func should_block_game_shortcuts(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var focus_owner: Control = viewport.gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
