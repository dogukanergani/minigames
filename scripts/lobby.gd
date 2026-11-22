extends Control
## Lobi: oda kur / katıl, takım seç, host oyunu başlatır.

const UiTheme = preload("res://scripts/ui_theme.gd")

var name_edit: LineEdit
var ip_edit: LineEdit
var status: Label
var connect_box: VBoxContainer
var room_box: VBoxContainer
var team_lists: Array[VBoxContainer] = []
var team_titles: Array[Label] = []
var team_btn: Button
var start_btn: Button
var ready_btn: Button
var quick_join := false


func _ready() -> void:
	_build_ui()
	Net.players_changed.connect(_refresh)
	Net.game_started.connect(_on_game_started)
	Net.join_failed.connect(_show_connect.bind("Bağlanılamadı."))
	Net.lost_connection.connect(_show_connect.bind("Bağlantı koptu."))
	var notice := Net.last_notice  # oyundan döndüysek sebebini göster
	Net.last_notice = ""
	_show_connect(notice)
	if not Net.players.is_empty():  # bağlantı sürüyorsa aynı odaya dön
		_refresh()
		if notice != "":
			status.text = notice + "  " + status.text
	# Geliştirici kısayolu: godot ... -- quick-host / quick-join
	var args := OS.get_cmdline_user_args()
	if "quick-host" in args:
		_on_host_pressed.call_deferred()
	elif "quick-join" in args:
		quick_join = true
		_on_join_pressed.call_deferred()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make_theme()  # 640x360 iç çözünürlük: küçük yazı, taş-metal çerçeveler
	add_child(UiTheme.make_backdrop())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := UiTheme.banner("banner_gold", "MINIGAMES  -  LOBİ", 16)
	title.custom_minimum_size = Vector2(0, 30)
	root.add_child(title)

	status = UiTheme.make_label("", 12, UiTheme.GOLD_L)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status)

	# Bağlantı paneli (ortada, çerçeveli)
	connect_box = VBoxContainer.new()
	connect_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	connect_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(connect_box)
	var cpanel := PanelContainer.new()
	cpanel.custom_minimum_size = Vector2(300, 0)
	cpanel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	connect_box.add_child(cpanel)
	var cform := VBoxContainer.new()
	cform.add_theme_constant_override("separation", 6)
	cpanel.add_child(cform)
	cform.add_child(UiTheme.make_label("İSMİN", 10, UiTheme.DIM))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "İsmin"
	name_edit.text = "Oyuncu%d" % randi_range(100, 999)
	cform.add_child(name_edit)
	cform.add_child(UiTheme.make_label("HOST IP (katılmak için)", 10, UiTheme.DIM))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP (katılmak için)"
	ip_edit.text = "127.0.0.1"
	cform.add_child(ip_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	cform.add_child(row)
	var host_btn := Button.new()
	host_btn.text = "Oda Kur"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host_pressed)
	row.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.text = "Katıl"
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_pressed)
	row.add_child(join_btn)

	# Oda paneli: iki takım sütunu
	room_box = VBoxContainer.new()
	room_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_box.add_theme_constant_override("separation", 8)
	root.add_child(room_box)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 14)
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_box.add_child(teams)
	for t in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		teams.add_child(col)
		var header := UiTheme.team_banner(t, "", 13)
		header.custom_minimum_size = Vector2(0, 22)
		col.add_child(header)
		team_titles.append(header.get_child(0) as Label)
		var panel := PanelContainer.new()
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(panel)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 3)
		panel.add_child(list)
		team_lists.append(list)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	room_box.add_child(buttons)
	team_btn = Button.new()
	team_btn.text = "Takım Değiştir"
	team_btn.pressed.connect(func(): Net.request_team(1 - Net.my_team()))
	buttons.add_child(team_btn)
	ready_btn = Button.new()
	ready_btn.toggle_mode = true
	ready_btn.text = "Hazır"
	ready_btn.pressed.connect(func(): Net.set_my_ready(ready_btn.button_pressed))
	buttons.add_child(ready_btn)
	start_btn = Button.new()
	start_btn.text = "Oyunu Başlat"
	start_btn.pressed.connect(_on_start_pressed)
	buttons.add_child(start_btn)
	var leave_btn := Button.new()
	leave_btn.text = "Ayrıl"
	leave_btn.pressed.connect(func():
		Net.leave()
		_show_connect(""))
	buttons.add_child(leave_btn)


func _show_connect(msg: String) -> void:
	connect_box.show()
	room_box.hide()
	status.text = msg


func _on_host_pressed() -> void:
	var err := Net.host(name_edit.text)
	if err != OK:
		status.text = "Oda kurulamadı (hata %d). Port kullanımda olabilir." % err


func _on_join_pressed() -> void:
	status.text = "Bağlanılıyor..."
	var err := Net.join(ip_edit.text, name_edit.text)
	if err != OK:
		status.text = "Bağlantı başlatılamadı (hata %d)." % err


func _on_start_pressed() -> void:
	var msg := Net.start_game()
	if msg != "":
		status.text = msg


func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _refresh() -> void:
	if Net.players.is_empty():
		return
	connect_box.hide()
	room_box.show()
	var my_id := multiplayer.get_unique_id()
	for t in 2:
		team_titles[t].text = "%s Takım (%d/%d)" % [Net.TEAM_NAMES[t], Net.team_count(t), Net.TEAM_SIZE]
		for c in team_lists[t].get_children():
			c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		team_lists[p.team].add_child(_player_row(id, p, id == my_id))
	start_btn.visible = multiplayer.is_server()
	ready_btn.visible = not multiplayer.is_server()
	ready_btn.set_pressed_no_signal(Net.my_ready())
	if quick_join and not Net.my_ready():
		Net.set_my_ready(true)  # geliştirici kısayolu
	status.text = "Oda: %d oyuncu" % Net.players.size()


## Oyuncu satırı: durum ikonu (host ★, hazır ✓, bekliyor ...) + ad; kendi satırım altın çerçeveli.
func _player_row(id: int, p: Dictionary, mine: bool) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.row_box(mine))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	pc.add_child(h)
	var mark := "star" if id == 1 else ("check" if p.ready else "dots")
	h.add_child(UiTheme.icon_rect(mark, 14))
	var name_l := UiTheme.make_label(p.name, 12, UiTheme.GOLD_L if mine else UiTheme.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	h.add_child(name_l)
	if mine:
		h.add_child(UiTheme.make_label("sen", 10, UiTheme.DIM))
	elif id == 1:
		h.add_child(UiTheme.make_label("host", 10, UiTheme.DIM))
	return pc
