extends Control

const Simulation = preload("res://scripts/simulation.gd")
const Report = preload("res://scripts/report.gd")
const MapView = preload("res://scripts/map_view.gd")
const ChartView = preload("res://scripts/chart.gd")
const COLORS = [Color("ef777e"), Color("64b2fc"), Color("66d3a5")]
const SCENARIOS = ["balanced", "profit", "coordinated"]
const SPEEDS = [0.25, 1.0, 4.0, 10.0, 30.0, 100.0]
const ROLE_NAMES = {"assault":"占点突击", "medic":"战地医护", "transport":"运输驾驶", "engineer":"后勤工程", "armor":"装甲驾驶", "sniper":"游走狙击", "opportunist":"收益逐利"}
const INCOME_NAMES = {"kill":"击杀", "kills":"击杀", "zone":"区域驻留", "revive":"救援复活", "heal":"治疗", "transport":"运送乘员", "supply":"后勤补给", "build":"建造", "spot":"侦察标记", "recon":"侦察标记", "vehicle_destroyed":"摧毁载具", "supply_purchase":"补给购买", "supplies":"补给购买", "zone_entry":"首次进入控制区", "enter_zone":"首次进入控制区", "equipment":"装备购置", "vehicle_kill":"摧毁载具", "win":"胜利奖励", "win_bonus":"胜利奖励", "loadout":"装备购置", "vehicle":"载具购买", "fob":"前线基地", "hammer":"工程工具", "repair":"维修"}

var sim = Simulation.new()
var map_view
var chart_view
var paused := false
var speed := 10.0
var accumulator := 0.0
var ui_clock := 0.0
var selected_id := 0
var ended_shown := false
var score_labels: Array = []
var timer_label: Label
var clock_detail: Label
var pause_button: Button
var speed_select: OptionButton
var scenario_select: OptionButton
var seed_input: SpinBox
var cash_input: SpinBox
var reward_input: SpinBox
var carry_check: CheckBox
var actor_select: OptionButton
var actor_info: RichTextLabel
var economy_info: RichTextLabel
var situation_info: RichTextLabel
var event_info: RichTextLabel
var status_label: Label
var popup: Panel
var popup_shade: ColorRect
var popup_title: Label
var popup_text: RichTextLabel
var popup_resume := false
var toast := ""
var toast_time := 0.0
var latest_export := ""
var smoke := false
var smoke_elapsed := 0.0
var smoke_captured := false
var capture_done := false

func _ready() -> void:
	var ui_theme := Theme.new()
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 14
	ui_theme.set_color("font_color", "Label", Color("d9e4df"))
	ui_theme.set_color("font_color", "Button", Color("c8d8d1"))
	ui_theme.set_color("font_hover_color", "Button", Color("ffe0ac"))
	for type in ["Button", "OptionButton"]:
		ui_theme.set_stylebox("normal", type, _style(Color("192c33"),Color("34494c"),5))
		ui_theme.set_stylebox("hover", type, _style(Color("283d40"),Color("aa865b"),5))
		ui_theme.set_stylebox("pressed", type, _style(Color("334542"),Color("edb87b"),5))
		ui_theme.set_stylebox("focus", type, _style(Color(0,0,0,0),Color("b69a6c"),5))
	ui_theme.set_stylebox("normal","LineEdit",_style(Color("0e1b22"),Color("34494c"),4))
	ui_theme.set_color("font_color","LineEdit",Color("d9e4df"))
	ui_theme.set_color("default_color","RichTextLabel",Color("b8cdc4"))
	theme = ui_theme
	sim.setup(42,"balanced")
	_build_ui()
	_refresh_actors()
	_refresh()
	if "--record-demo" in OS.get_cmdline_user_args():
		get_viewport().gui_embed_subwindows = true
		var director = load("res://scripts/demo_director.gd").new()
		add_child(director)
	if "--smoke-test" in OS.get_cmdline_user_args() or "--ui-test" in OS.get_cmdline_user_args():
		smoke = true
		for i in range(3600):
			sim.step(0.25)
		_refresh()
		paused = true
		pause_button.text = "▶ 继续推演"
		if "--ui-test" in OS.get_cmdline_user_args():
			call_deferred("_ui_test")

func _style(bg: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

func _panel(rect: Rect2, bg: String = "101f27") -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel",_style(Color(bg),Color("293c42")))
	add_child(p)
	return p

func _label(parent: Node, pos: Vector2, value: String, font_size: int = 14, color: String = "d9e4df") -> Label:
	var l := Label.new()
	l.position = pos
	l.text = value
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",Color(color))
	parent.add_child(l)
	return l

func _button(parent: Node, rect: Rect2, value: String, callback: Callable) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.text = value
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _rich(parent: Node, rect: Rect2, font_size: int = 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.position = rect.position
	r.size = rect.size
	r.bbcode_enabled = true
	r.add_theme_font_size_override("normal_font_size",font_size)
	r.add_theme_constant_override("line_separation",6)
	parent.add_child(r)
	return r

func _spin(parent: Node, pos: Vector2, width: float, minimum: float, maximum: float, value: float, interval: float) -> SpinBox:
	var s := SpinBox.new()
	s.position = pos
	s.size = Vector2(width,34)
	s.min_value = minimum
	s.max_value = maximum
	s.step = interval
	s.value = value
	parent.add_child(s)
	return s

func _build_ui() -> void:
	_label(self,Vector2(22,13),"WARDOGS",29,"f0e9d9")
	_label(self,Vector2(205,26),"战局推演实验室",17,"bfccc1")
	_label(self,Vector2(24,55),"TACTICAL ECONOMY LAB   /   观察 · 对照 · 推演",11,"718f87")
	for t in range(3):
		var panel := _panel(Rect2(460+t*251,14,237,65))
		var accent := ColorRect.new()
		accent.position = Vector2(0,10)
		accent.size = Vector2(3,45)
		accent.color = COLORS[t]
		panel.add_child(accent)
		var txt := _rich(panel,Rect2(15,7,211,58),13)
		txt.scroll_active = false
		score_labels.append(txt)
	timer_label = _label(self,Vector2(1257,14),"00:00",30,"f0e9d9")
	clock_detail = _label(self,Vector2(1382,29),"推演中  /  1×",13,"dfb77e")
	_label(self,Vector2(1258,55),"100 人 · 三方对抗 · 固定步长 0.25s",11,"718f87")
	pause_button = _button(self,Rect2(20,97,112,34),"Ⅱ 暂停推演",_toggle_pause)
	speed_select = OptionButton.new()
	speed_select.position = Vector2(143,97)
	speed_select.size = Vector2(107,34)
	speed_select.focus_mode = Control.FOCUS_NONE
	for v in SPEEDS:
		speed_select.add_item("速度 %s×" % v)
	speed_select.select(3)
	speed_select.item_selected.connect(func(index): speed = SPEEDS[index])
	add_child(speed_select)
	_button(self,Rect2(262,97,106,34),"推进 30 秒",_step_thirty)
	_button(self,Rect2(380,97,89,34),"全图 Home",map_fit)
	_button(self,Rect2(480,97,89,34),"跟随 F",_focus)
	_button(self,Rect2(580,97,96,34),"轨迹 T",func(): map_view.show_trails = not map_view.show_trails)
	_button(self,Rect2(687,97,96,34),"兵力密度",func(): map_view.show_heat = not map_view.show_heat)
	_button(self,Rect2(794,97,96,34),"玩家名称",func(): map_view.show_labels = not map_view.show_labels)
	_button(self,Rect2(1019,97,104,34),"全员排行",_show_roster)
	_button(self,Rect2(1134,97,106,34),"规则与数值",_show_rules)
	_button(self,Rect2(1260,97,152,34),"导出本局报告",_export)
	_button(self,Rect2(1422,97,158,34),"查看最近报告",_open_export)
	var left := _panel(Rect2(20,150,224,419))
	_label(left,Vector2(16,13),"01 / 实验设置",16,"efdfc5")
	_label(left,Vector2(16,47),"玩家行为分布",12,"7c9b90")
	scenario_select = OptionButton.new()
	scenario_select.position = Vector2(14,72)
	scenario_select.size = Vector2(195,36)
	scenario_select.add_item("均衡生态 · 基准组")
	scenario_select.add_item("经济优先 · 逐利组")
	scenario_select.add_item("红队协同 · 对照组")
	left.add_child(scenario_select)
	_label(left,Vector2(16,119),"随机种子 / 可重复实验",12,"7c9b90")
	seed_input = _spin(left,Vector2(14,143),195,0,999999,42,1)
	_label(left,Vector2(16,188),"初始账户 $ / 官方基线 10,000",11,"7c9b90")
	cash_input = _spin(left,Vector2(14,211),195,0,1000000,10000,500)
	_label(left,Vector2(16,254),"行动奖励倍率 / 敏感性试验",11,"7c9b90")
	reward_input = _spin(left,Vector2(14,277),195,0,10,1,0.25)
	carry_check = CheckBox.new()
	carry_check.position = Vector2(9,320)
	carry_check.text = "下一局继承本局账户"
	carry_check.add_theme_font_size_override("font_size",12)
	left.add_child(carry_check)
	_button(left,Rect2(14,368,195,35),"应用设置 / 开始新局",_new_match)
	var overview := _panel(Rect2(20,584,224,254))
	_label(overview,Vector2(16,13),"02 / 战局概况",16,"efdfc5")
	situation_info = _rich(overview,Rect2(16,49,196,193),13)
	situation_info.add_theme_constant_override("line_separation",1)
	var provenance := _panel(Rect2(20,851,224,124),"17262a")
	_label(provenance,Vector2(15,13),"数值可信度",13,"efbd7b")
	var warning := _rich(provenance,Rect2(15,39,197,83),11)
	warning.add_theme_constant_override("line_separation",1)
	warning.text = "[color=#8fc5ad]● 官方核实：核心计分规则[/color]\n[color=#edb879]● 历史实测 / 假设：部分经济[/color]\n[color=#87a398]行为、战斗与地图为仿真模型\n不代表真实玩家胜率预测[/color]"
	map_view = MapView.new()
	map_view.position = Vector2(263,150)
	map_view.size = Vector2(977,567)
	map_view.sim = sim
	map_view.actor_selected.connect(_select_actor)
	add_child(map_view)
	_label(self,Vector2(270,722),"● 步兵    + 医护    ▰ 载具    △ FOB       左键选人 · 滚轮缩放 · 右键拖动 · WASD 平移",11,"7b9b90")
	var right := _panel(Rect2(1260,150,320,825))
	_label(right,Vector2(17,14),"03 / 玩家观察席",16,"efdfc5")
	actor_select = OptionButton.new()
	actor_select.position = Vector2(16,51)
	actor_select.size = Vector2(286,35)
	actor_select.focus_mode = Control.FOCUS_NONE
	actor_select.item_selected.connect(_select_actor)
	right.add_child(actor_select)
	actor_info = _rich(right,Rect2(18,105,284,355),14)
	actor_info.add_theme_constant_override("line_separation",3)
	_label(right,Vector2(18,473),"个人经济账本",15,"efdfc5")
	economy_info = _rich(right,Rect2(18,510,284,291),13)
	economy_info.add_theme_constant_override("line_separation",3)
	var chart_panel := _panel(Rect2(263,753,473,222))
	_label(chart_panel,Vector2(15,11),"三方走势",15,"efdfc5")
	var metrics := OptionButton.new()
	metrics.position = Vector2(276,8)
	metrics.size = Vector2(178,30)
	metrics.add_item("团队得分")
	metrics.add_item("团队现金余额")
	metrics.add_item("区域实际人数")
	metrics.focus_mode = Control.FOCUS_NONE
	metrics.item_selected.connect(func(index): chart_view.metric = ["scores","cash","presence"][index]; chart_view.queue_redraw())
	chart_panel.add_child(metrics)
	chart_view = ChartView.new()
	chart_view.position = Vector2(9,46)
	chart_view.size = Vector2(452,167)
	chart_view.sim = sim
	chart_panel.add_child(chart_view)
	var events_panel := _panel(Rect2(751,753,489,222))
	_label(events_panel,Vector2(15,11),"战场事件流",15,"efdfc5")
	_label(events_panel,Vector2(330,15),"最新 6 条 / 全量可导出",10,"7b9b90")
	event_info = _rich(events_panel,Rect2(15,44,459,167),12)
	event_info.add_theme_constant_override("line_separation",3)
	status_label = _label(self,Vector2(22,982),"",11,"7c9b90")
	popup_shade = ColorRect.new()
	popup_shade.size = Vector2(1600,1000)
	popup_shade.color = Color(0,0,0,0.58)
	popup_shade.z_index = 40
	popup_shade.visible = false
	add_child(popup_shade)
	popup = _panel(Rect2(160,96,1280,814),"101e25")
	popup.z_index = 50
	popup.visible = false
	popup_title = _label(popup,Vector2(25,20),"",22,"efdfc5")
	_button(popup,Rect2(1129,17,127,35),"关闭 Esc",_close_popup)
	popup_text = _rich(popup,Rect2(26,78,1226,706),15)
	popup_text.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))

func _process(delta: float) -> void:
	if not paused and not sim.finished:
		accumulator += minf(delta,0.25) * speed
		var budget := 0
		while accumulator >= 0.25 and not sim.finished and budget < 500:
			sim.step(0.25)
			accumulator -= 0.25
			budget += 1
	if sim.finished and not ended_shown:
		ended_shown = true
		paused = true
		pause_button.text = "本局已结束"
		if sim.winner >= 0:
			_toast("%s 达到 %d 分获胜。可导出报告，或继承账户开始下一局。" % [sim.teams[sim.winner].name, sim.config.get("score_target",100)])
		else:
			_toast("达到本模型的推演时长上限，尚无队伍获胜。本局以未决结果导出。")
		_export(false)
	ui_clock += delta
	toast_time = maxf(0,toast_time-delta)
	if ui_clock > 0.25:
		ui_clock = 0
		_refresh()
	if smoke:
		smoke_elapsed += delta
		if smoke_elapsed > 1.5 and not smoke_captured:
			smoke_captured = true
			_capture()
		if smoke_elapsed > 3.0 and capture_done:
			print("UI_SMOKE_OK actors=%d time=%s" % [sim.actors.size(),sim.time])
			get_tree().quit()

func _money(value: float) -> String:
	return ("−" if value < 0 else "") + "$%s" % str(int(absf(value)))

func _time(value: float) -> String:
	var total := int(value)
	return "%02d:%02d" % [total/60,total%60]

func _refresh() -> void:
	for t in range(3):
		var team: Dictionary = sim.teams[t]
		score_labels[t].text = "[color=#%s]%s[/color]  [font_size=23][b]%d[/b][/font_size][color=#728e85] / %d[/color]\n[color=#91aaa0]区内 %d 人 · 计分权重 %d[/color]" % [COLORS[t].to_html(false),team.name,int(team.score),int(sim.config.get("score_target",100)),int(team.presence),int(team.get("weighted_presence",team.presence))]
	timer_label.text = _time(sim.time)
	clock_detail.text = ("已结束" if sim.finished else ("已暂停" if paused else "推演中")) + "  /  %s×" % speed
	var alive := 0
	var down := 0
	var total_earned := 0.0
	var total_spent := 0.0
	var zone := 0
	for a in sim.actors:
		if a.hp > 0:
			alive += 1
		elif a.state == "downed":
			down += 1
		total_earned += a.earned
		total_spent += a.spent
	for t in sim.teams:
		zone += int(t.presence)
	var active_vehicles := 0
	for v in sim.vehicles:
		if v.hp > 0:
			active_vehicles += 1
	situation_info.text = "存活  [b]%d[/b] / %d   倒地 %d\n区域参与  [b]%d 人[/b]\n在役载具  %d   前线基地 %d\n\n[color=#8fc5ad]累计产出   %s[/color]\n[color=#edb879]累计消耗   %s[/color]\n净现金变化  %s\n下次计分  %.1f 秒" % [alive,sim.actors.size(),down,zone,active_vehicles,sim.fobs.filter(func(f): return f.hp > 0).size(),_money(total_earned),_money(total_spent),_money(total_earned-total_spent),float(sim.config.get("score_interval",30))-fmod(sim.time,float(sim.config.get("score_interval",30)))]
	if selected_id >= 0 and selected_id < sim.actors.size():
		var a: Dictionary = sim.actors[selected_id]
		var t := int(a.team)
		actor_info.text = "[color=#%s][font_size=21][b]%s[/b][/font_size][/color]\n%s · %s\n\n[color=#718f87]正在做什么[/color]\n[b]%s[/b]\n[color=#718f87]决策原因[/color]\n%s\n\n生命  %d   状态  %s\n击杀 %d  /  死亡 %d  /  救援 %d\n送达乘员 %d 人\n区域驻留 %s\n坐标  %d, %d m" % [COLORS[t].to_html(false),a.name,sim.teams[t].name,ROLE_NAMES.get(a.role,a.role),a.action,a.reason,maxi(0,int(a.hp)),_state_name(a.state),int(a.kills),int(a.deaths),int(a.revives),int(a.deliveries),_time(a.zone_seconds),int(a.pos.x),int(a.pos.y)]
		if int(a.vehicle) >= 0 and int(a.vehicle) < sim.vehicles.size():
			var vehicle: Dictionary = sim.vehicles[int(a.vehicle)]
			actor_info.text += "\n载具  %s\n耐久 %d / %d   乘员 %d / %d" % [sim.config.vehicles[vehicle.kind].label,int(vehicle.hp),int(vehicle.max_hp),vehicle.passengers.size(),int(vehicle.seats)]
		var net: float = a.earned-a.spent
		var content := "[font_size=24][b]%s[/b][/font_size]  可用现金\n[color=#%s]本局净收益  %s[/color]\n总收入 %s  /  总支出 %s\n\n" % [_money(a.cash),"8fc5ad" if net >= 0 else "ef777e",_money(net),_money(a.earned),_money(a.spent)]
		for key in a.income:
			if a.income[key] > 0:
				content += "[color=#8fc5ad]+ %s[/color]    %s\n" % [_money(a.income[key]),INCOME_NAMES.get(key,key)]
		for key in a.costs:
			if a.costs[key] > 0:
				content += "[color=#bda88a]− %s[/color]    %s\n" % [_money(a.costs[key]),INCOME_NAMES.get(key,key)]
		economy_info.text = content
	var event_text := ""
	for i in range(sim.events.size()-1,maxi(-1,sim.events.size()-7),-1):
		var e: Dictionary = sim.events[i]
		var color := "9db6ab"
		if int(e.get("team",-1)) in [0,1,2]:
			color = COLORS[int(e.team)].to_html(false)
		event_text += "[color=#68877f]%s[/color]  [color=#%s]%s[/color]\n" % [_time(e.time),color,e.text]
	event_info.text = event_text if not event_text.is_empty() else "各方开始部署。行为与交易发生后会在这里记录。"
	chart_view.queue_redraw()
	status_label.text = toast if toast_time > 0 else "SPACE 暂停   ·   + / − 调速   ·   TAB 选人   ·   HOME 全图     |     公开规则 + 可校准行为模型   ·   SEED %d" % sim.seed_value

func _state_name(value: String) -> String:
	return {"alive":"行动中","active":"行动中","downed":"等待救援","dead":"等待重生","respawning":"等待重生","riding":"搭乘中", "embarked":"搭乘中"}.get(value,value)

func _refresh_actors() -> void:
	actor_select.clear()
	for a in sim.actors:
		actor_select.add_item("%s · %s / %s" % [["红","蓝","绿"][a.team],a.name,ROLE_NAMES.get(a.role,a.role)])
	_select_actor(0)

func _select_actor(id: int) -> void:
	selected_id = id
	map_view.selected_id = id
	actor_select.select(id)
	_refresh()

func _toggle_pause() -> void:
	if sim.finished or popup.visible:
		return
	paused = not paused
	pause_button.text = "▶ 继续推演" if paused else "Ⅱ 暂停推演"
	_refresh()

func _step_thirty() -> void:
	paused = true
	pause_button.text = "▶ 继续推演"
	accumulator = 0
	for i in range(120):
		sim.step(0.25)
	_refresh()

func map_fit() -> void:
	map_view.fit()

func _focus() -> void:
	map_view.focus_actor()

func _new_match() -> void:
	var balances := []
	if carry_check.button_pressed:
		for a in sim.actors:
			balances.append(a.cash)
	var rewards: Dictionary = sim.config.get("rewards",{}).duplicate(true)
	# Reload base data so repeated restarts do not compound the multiplier.
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	if raw is Dictionary:
		rewards = raw.get("rewards",{}).duplicate(true)
	for key in rewards:
		if rewards[key] is float or rewards[key] is int:
			rewards[key] *= reward_input.value
	sim.setup(int(seed_input.value),SCENARIOS[scenario_select.selected],{"starting_cash":cash_input.value,"rewards":rewards},balances)
	sim.config["experiment_overrides"] = {"initial_cash_setting":cash_input.value,"reward_multiplier":reward_input.value,"carry_previous_balance":carry_check.button_pressed}
	if raw is Dictionary and not is_equal_approx(cash_input.value,float(raw.get("starting_cash",10000))):
		sim.config.parameter_status["starting_cash"] = {"status":"experimental_override","source":"User experiment initial balance; official new-account baseline is $10,000."}
	if not is_equal_approx(reward_input.value,1.0):
		sim.config.parameter_status["rewards"] = {"status":"experimental_override","source":"User experiment reward multiplier %s; original community observations and assumptions are scaled for sensitivity analysis." % reward_input.value}
	paused = false
	ended_shown = false
	accumulator = 0
	pause_button.text = "Ⅱ 暂停推演"
	map_view.fit()
	_refresh_actors()
	_refresh()
	_toast("新局已开始。种子 %d；经济奖励倍率 %s×。" % [int(seed_input.value),reward_input.value])
	seed_input.get_line_edit().release_focus()
	cash_input.get_line_edit().release_focus()
	reward_input.get_line_edit().release_focus()

func _toast(message: String) -> void:
	toast = message
	toast_time = 18

func _show_popup(title: String, content: String) -> void:
	popup_resume = not paused
	paused = true
	popup.visible = true
	popup_shade.visible = true
	popup_title.text = title
	popup_text.text = content
	popup_text.scroll_to_line(0)

func _close_popup() -> void:
	popup.visible = false
	popup_shade.visible = false
	if popup_resume and not sim.finished:
		paused = false
	_refresh()

func _show_rules() -> void:
	var content := "[b]当前公开版规则 · 核实日期 2026-09-18[/b]\n100 名玩家；Valkyra 红 / Lonestar 蓝 / Manticore 绿；默认分配 34 / 33 / 33。\n控制区 2 × 2 km，每 30 秒统计有效占区人数，领先者 +1 分，先到 100 分胜利。\n热区人数权重 ×2、现金 ×2；平局不加分的处理属于本模型假设。初始账户 $10,000，每命重购装备。\n\n[b]当前模拟范围[/b]\n7 种行为倾向；空间移动、交火、倒地救援、重生重购、乘员运输、后勤补给和 FOB。\n6 × 6 km 局部示意战区；原作大地图 256 km²。地形用于阅读局势，不模拟原作弹道与逐栋破坏。\n固定 0.25 秒逻辑步长；速度控制只改变每秒执行的步数。同种子、同参数可复现。\n\n[b]参数来源必须区分[/b]\n绿色：官方公开明确值。黄色：历史试玩观测或人为设定，不能当作当前客户端精确值。\nAI 的偏好、射击命中、载具性能、移动速度和地形均是待校准模型。\n本局收益未计局末排名奖金、XP、永久解锁费和服务器人数缩放；研究账户假设已解锁装备。\n数值文件：res://data/rules.json；完整证据：docs/RULE_SOURCES.md。\n\n[b]本局经济参数（修改 JSON 后点“开始新局”读取）[/b]\n"
	content += "起始现金：%s\n装备购置：%s\n行动奖励：%s\n" % [_money(sim.config.get("starting_cash",10000)),str(sim.config.get("loadout_cost",{})),str(sim.config.get("rewards",{}))]
	content += "\n[url=https://store.steampowered.com/app/1867240/WARDOGS/]Steam 官方商店：规则与经济循环[/url]\n[url=https://steamcommunity.com/app/1867240/discussions/0/762932533852726673/]Steam 开发者 FAQ：计分与胜利规则[/url]\n\n[b]实验解读[/b]\n均衡：三队使用相近玩家偏好；经济优先：提高逐利行为比重；红队协同：红方增加占点与支持。\n团队得分、个人收益、成本与活动都来自同一模拟状态。高收入不等于队伍一定获胜。\n对照时使用相同种子，批量多种子报告会单列未结束的对局；一次模拟不能证明策略优劣。"
	content += "\n\n[b]逐项证据标签[/b]\n"
	for key in sim.config.get("parameter_status",{}):
		var evidence: Dictionary = sim.config.parameter_status[key]
		var verified: bool = str(evidence.get("status","")).begins_with("official")
		content += "[color=#%s]%s · %s[/color]\n%s\n\n" % ["8fc5ad" if verified else "edb879",key,evidence.get("status","unknown"),evidence.get("source","")]
	_show_popup("规则、来源与模拟边界",content)

func _show_roster() -> void:
	var sorted: Array = sim.actors.duplicate()
	sorted.sort_custom(func(a,b): return a.earned-a.spent > b.earned-b.spent)
	var body := "按本局净收益排序；负值包含已购装备和载具。点选地图或右侧列表可观察具体决策。\n\n[table=8][cell][b]玩家[/b][/cell][cell][b]行为倾向[/b][/cell][cell][b]可用现金[/b][/cell][cell][b]净收益[/b][/cell][cell][b]击杀/死亡[/b][/cell][cell][b]救援[/b][/cell][cell][b]区域时间[/b][/cell][cell][b]当前行动[/b][/cell]"
	for a in sorted:
		body += "[cell][color=#%s]%s[/color]  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%d / %d  [/cell][cell]%d  [/cell][cell]%s  [/cell][cell]%s[/cell]" % [COLORS[a.team].to_html(false),a.name,ROLE_NAMES.get(a.role,a.role),_money(a.cash),_money(a.earned-a.spent),a.kills,a.deaths,a.revives,_time(a.zone_seconds),a.action]
	body += "[/table]"
	_show_popup("全员经济与贡献排行 / %d 人" % sim.actors.size(),body)

func _export(show_message: bool = true) -> void:
	var destination := "user://reports/run_%d_%d" % [sim.seed_value,int(Time.get_unix_time_from_system())]
	latest_export = sim.export_run(destination)
	if latest_export.is_empty():
		_toast("报告写入失败，请检查输出目录权限。")
		return
	var report_text: String = Report.make(sim)
	var report_file := FileAccess.open(latest_export.path_join("报告.txt"),FileAccess.WRITE)
	if report_file:
		report_file.store_string(report_text)
	if show_message:
		_toast("已导出本局报告、玩家明细、经济账本和趋势数据。点击“查看最近报告”打开目录。")
		_show_popup("本局推演报告 / 已保存",report_text)

func _open_export() -> void:
	if latest_export.is_empty():
		_export(false)
	if not latest_export.is_empty():
		var absolute := ProjectSettings.globalize_path(latest_export)
		OS.shell_open(absolute if DirAccess.dir_exists_absolute(absolute) else absolute.get_base_dir())

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and popup.visible:
		_close_popup()
		return
	if popup.visible:
		return
	match event.keycode:
		KEY_SPACE: _toggle_pause()
		KEY_HOME, KEY_0: map_fit()
		KEY_F: _focus()
		KEY_T: map_view.show_trails = not map_view.show_trails
		KEY_TAB: _select_actor((selected_id+1) % sim.actors.size())
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			speed_select.select(mini(SPEEDS.size()-1,speed_select.selected+1))
			speed = SPEEDS[speed_select.selected]
		KEY_MINUS, KEY_KP_SUBTRACT:
			speed_select.select(maxi(0,speed_select.selected-1))
			speed = SPEEDS[speed_select.selected]

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		capture_done = true
		return
	await RenderingServer.frame_post_draw
	var capture_dir := "res://artifacts" if OS.has_feature("editor") else "user://captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	var screenshot := get_viewport().get_texture().get_image()
	var capture_path := capture_dir.path_join("wardogs_sandbox.png")
	var error := screenshot.save_png(capture_path)
	print("SCREENSHOT_RESULT=%d" % error)
	print("SCREENSHOT_PATH="+ProjectSettings.globalize_path(capture_path))
	capture_done = true

func _ui_test() -> void:
	var before: float = sim.time
	_step_thirty()
	assert(is_equal_approx(sim.time,before+30.0))
	_select_actor(50)
	assert(map_view.selected_id == 50)
	_focus()
	assert(map_view.follow)
	map_fit()
	assert(not map_view.follow and is_equal_approx(map_view.zoom,1.0))
	_show_rules()
	assert(popup.visible and paused)
	_close_popup()
	_show_roster()
	assert(popup_text.text.contains("[table=8]"))
	_close_popup()
	_export(false)
	assert(not latest_export.is_empty())
	assert(FileAccess.file_exists(latest_export.path_join("报告.txt")))
	print("REPORT_PATH="+ProjectSettings.globalize_path(latest_export))
	var pointer := InputEventMouseButton.new()
	pointer.button_index = MOUSE_BUTTON_LEFT
	pointer.pressed = true
	pointer.position = map_view.project(sim.actors[50].pos)
	map_view._map_input(pointer)
	assert(selected_id == 50, "Map click should select the actor at its displayed position")
	pointer.button_index = MOUSE_BUTTON_WHEEL_UP
	pointer.position = Vector2(160,160)
	var anchored: Vector2 = map_view.unproject(pointer.position)
	map_view._map_input(pointer)
	assert(anchored.distance_to(map_view.unproject(pointer.position)) < 0.01, "Zoom must remain anchored under the pointer")
	pointer.button_index = MOUSE_BUTTON_RIGHT
	map_view._map_input(pointer)
	var previous_center: Vector2 = map_view.center
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(24,16)
	map_view._map_input(motion)
	assert(previous_center.distance_to(map_view.center) > 1.0, "Map drag must pan the view")
	pointer.pressed = false
	map_view._map_input(pointer)
	map_fit()
	var previous_balance: float = sim.actors[0].cash
	carry_check.button_pressed = true
	reward_input.value = 2.0
	_new_match()
	assert(is_equal_approx(sim.actors[0].initial_cash,previous_balance), "Carry cash must preserve ending balance before new purchases")
	var reward_once: float = sim.config.rewards.zone
	_new_match()
	assert(is_equal_approx(sim.config.rewards.zone,reward_once), "Repeated apply must not compound reward multiplier")
	carry_check.button_pressed = false
	reward_input.value = 1.0
	_new_match()
	for i in range(3600):
		sim.step(0.25)
	paused = true
	pause_button.text = "▶ 继续推演"
	_select_actor(50)
	_refresh()
	print("UI_INTERACTION_TEST_OK: selection, anchored zoom, pan, follow, fixed step, report, cash carry, non-compounding parameters")
