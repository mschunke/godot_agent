@tool
extends Window

signal load_requested(id: String)
signal delete_requested(id: String)
signal closed

var _list: ItemList
var _summaries: Array = []
var _empty_label: Label
var _load_btn: Button
var _delete_btn: Button


func _init() -> void:
	title = "Godot Agent — Chat history"
	size = Vector2i(560, 480)
	unresizable = false
	transient = true
	exclusive = false
	close_requested.connect(_on_close)


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	outer.offset_left = 12
	outer.offset_top = 12
	outer.offset_right = -12
	outer.offset_bottom = -12
	add_child(outer)

	var header := Label.new()
	header.text = "Previous conversations (stored in addons/godot_agent/conversations/)"
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	outer.add_child(header)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.item_activated.connect(_on_item_activated)
	_list.item_selected.connect(_on_item_selected)
	outer.add_child(_list)

	_empty_label = Label.new()
	_empty_label.text = "No saved conversations yet."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	outer.add_child(_empty_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 6)
	outer.add_child(btn_row)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.disabled = true
	_delete_btn.pressed.connect(_on_delete)
	btn_row.add_child(_delete_btn)

	_load_btn = Button.new()
	_load_btn.text = "Load"
	_load_btn.disabled = true
	_load_btn.pressed.connect(_on_load)
	btn_row.add_child(_load_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)


func refresh(summaries: Array) -> void:
	_summaries = summaries
	if not is_instance_valid(_list):
		return
	_list.clear()
	for s in _summaries:
		var when := _format_time(int(s.get("updated_at", 0)))
		var count: int = int(s.get("message_count", 0))
		var title_txt := String(s.get("title", "(untitled)"))
		var tokens: int = int(s.get("tokens_total", 0))
		var token_str := "  ·  %s tok" % _format_tokens(tokens) if tokens > 0 else ""
		_list.add_item("%s\n  %s · %d msg%s" % [title_txt, when, count, token_str])
	_empty_label.visible = _summaries.is_empty()
	_load_btn.disabled = true
	_delete_btn.disabled = true


func _on_item_selected(_index: int) -> void:
	_load_btn.disabled = false
	_delete_btn.disabled = false


func _on_item_activated(index: int) -> void:
	if index < 0 or index >= _summaries.size():
		return
	load_requested.emit(String(_summaries[index].id))
	hide()


func _on_load() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var index: int = sel[0]
	if index < 0 or index >= _summaries.size():
		return
	load_requested.emit(String(_summaries[index].id))
	hide()


func _on_delete() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var index: int = sel[0]
	if index < 0 or index >= _summaries.size():
		return
	delete_requested.emit(String(_summaries[index].id))


func _on_close() -> void:
	closed.emit()
	hide()


static func _format_time(unix: int) -> String:
	if unix <= 0:
		return "—"
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]


static func _format_tokens(n: int) -> String:
	if n < 1000:
		return str(n)
	if n < 1_000_000:
		return "%.1fk" % (float(n) / 1000.0)
	return "%.2fM" % (float(n) / 1_000_000.0)
