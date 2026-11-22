extends Control
## Lobi: oda kur / katıl, takım seç, host oyunu başlatır.

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
	_show_connect("")
	# Geliştirici kısayolu: godot ... -- quick-host / quick-join
	var args := OS.get_cmdline_user_args()
	if "quick-host" in args:
		_on_host_pressed.call_deferred()
	elif "quick-join" in args:
		quick_join = true
		_on_join_pressed.call_deferred()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 640x360 iç çözünürlük için küçük yazı boyutu
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 12
	theme = ui_theme
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "MINIGAMES - LOBİ"
	root.add_child(title)

	status = Label.new()
	root.add_child(status)

	# Bağlantı paneli
	connect_box = VBoxContainer.new()
	root.add_child(connect_box)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "İsmin"
	name_edit.text = "Oyuncu%d" % randi_range(100, 999)
	connect_box.add_child(name_edit)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP (katılmak için)"
	ip_edit.text = "127.0.0.1"
	connect_box.add_child(ip_edit)
	var row := HBoxContainer.new()
	connect_box.add_child(row)
	var host_btn := Button.new()
	host_btn.text = "Oda Kur"
	host_btn.pressed.connect(_on_host_pressed)
	row.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.text = "Katıl"
	join_btn.pressed.connect(_on_join_pressed)
	row.add_child(join_btn)

	# Oda paneli
	room_box = VBoxContainer.new()
	root.add_child(room_box)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 32)
	room_box.add_child(teams)
	for t in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		teams.add_child(col)
		var header := Label.new()
		col.add_child(header)
		team_titles.append(header)
		var list := VBoxContainer.new()
		col.add_child(list)
		team_lists.append(list)
	var buttons := HBoxContainer.new()
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
		var label := Label.new()
		var mark := " ★" if id == 1 else (" ✓" if p.ready else " ...")
		label.text = p.name + mark + (" (sen)" if id == my_id else "")
		team_lists[p.team].add_child(label)
	start_btn.visible = multiplayer.is_server()
	ready_btn.visible = not multiplayer.is_server()
	ready_btn.set_pressed_no_signal(Net.my_ready())
	if quick_join and not Net.my_ready():
		Net.set_my_ready(true)  # geliştirici kısayolu
	status.text = "Oda: %d oyuncu" % Net.players.size()
