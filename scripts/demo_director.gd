extends Control
## Optional, deterministic 90-second movie demonstration.
## Uses the existing UI callbacks and live simulation; no fabricated balances or curves.

var app
var frame := 0
var event_index := 0
var events: Array = []
var action_log: Array = []
var cursor := Vector2(420,400)
var cursor_target := Vector2(420,400)
var click_position := Vector2.ZERO
var click_age := 10.0
var highlight := Rect2()
var heading: Label
var explanation: Label
var counter: Label
var small_title: Label
var annotation_panel: Panel
var font: Font
var total_seconds := 90.0
var chart_selector: OptionButton
var move_until := 0.0
var previous_drag := Vector2.ZERO

func _ready() -> void:
	app = get_parent()
	process_priority = -100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	font = app.theme.default_font
	chart_selector = _find_chart(app)
	_make_annotation()
	app.paused = true
	app.pause_button.text = "▶ 继续推演"
	app.map_view.fit()
	app._select_actor(0)
	for i in range(3600):
		app.sim.step(0.25)
	app._refresh()
	_build_timeline()
	print("DEMO_BEGIN: 90 seconds, 30 FPS, live simulation warmed to 15:00")

func _make_annotation() -> void:
	var panel := Panel.new()
	annotation_panel = panel
	panel.position = Vector2(20,584)
	panel.size = Vector2(224,254)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17272c")
	style.border_color = Color("b88950")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	small_title = _label(panel,Vector2(16,14),"90 秒功能演示",12,Color("b6a080"))
	heading = _label(panel,Vector2(16,43),"",20,Color("ffe1b6"))
	heading.size = Vector2(194,56)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation = _label(panel,Vector2(16,110),"",14,Color("d3ded5"))
	explanation.size = Vector2(191,99)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	counter = _label(panel,Vector2(16,224),"",11,Color("a28e71"))

func _label(parent: Node, position_value: Vector2, value: String, point_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position_value
	label.text = value
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",point_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _event(at: float, action: String, value = null) -> void:
	events.append({"at":at,"action":action,"value":value})

func _build_timeline() -> void:
	_event(0.0,"chapter",["01 / 战局总览","红、蓝、绿三方与100名玩家。\n已预演15分钟，直接观察正在进行的战局。"])
	_event(0.0,"highlight",Rect2(460,14,740,65))
	_event(2.8,"resume")
	_event(3.6,"point",Vector2(192,114))
	_event(4.1,"chapter",["02 / 加速推演","打开速度菜单，切到100倍。\n时间、单位移动、交火与账本一起推进。"])
	_event(4.3,"speed_menu")
	_event(5.2,"speed",100.0)
	_event(5.3,"highlight",Rect2(263,150,977,567))
	_event(11.6,"point",Vector2(192,114))
	_event(12.0,"speed_menu")
	_event(12.8,"chapter",["03 / 减速观察","先降到1倍，再到0.25倍。\n放慢动作，观察局部行为；逻辑步长保持不变。"])
	_event(12.8,"speed",1.0)
	_event(15.6,"speed_menu")
	_event(16.4,"speed",0.25)
	_event(16.6,"highlight",Rect2(1250,14,330,65))
	_event(20.3,"point",Vector2(74,114))
	_event(20.8,"chapter",["04 / 暂停与单步","暂停后按“推进30秒”。\n精确推进一个计分周期，再继续运行。"])
	_event(21.0,"pause")
	_event(22.0,"point",Vector2(315,114))
	_event(22.6,"step")
	_event(24.0,"speed",10.0)
	_event(24.1,"resume")
	_event(25.0,"chapter",["05 / 放大与平移","滚轮连续放大中央战区。\n右键拖动地图，查看局部单位与行动轨迹。"])
	_event(25.0,"point",Vector2(755,435))
	_event(25.0,"highlight",Rect2())
	for i in range(7):
		_event(25.6+i*0.25,"zoom",1)
	_event(29.0,"drag_start")
	_event(30.3,"drag_end")
	_event(31.0,"chapter",["06 / 点选玩家","在地图上点击一个玩家。\n右侧立刻显示行动、原因、战绩和个人经济账本。"])
	_event(31.2,"pick_map")
	_event(31.4,"highlight",Rect2(1260,150,320,825))
	_event(34.5,"point",Vector2(1410,218))
	_event(35.0,"actor_menu")
	_event(35.9,"select_role","medic")
	_event(36.0,"chapter",["07 / 医疗与跟随","选中一名医护并跟随。\n救援次数与医疗收益，都来自实际发生的救援。"])
	_event(36.4,"point",Vector2(525,114))
	_event(36.9,"focus")
	_event(40.8,"point",Vector2(1410,218))
	_event(41.2,"actor_menu")
	_event(42.0,"select_role","transport")
	_event(42.1,"focus")
	_event(42.1,"chapter",["08 / 运兵与收益","切换到运输玩家。\n查看运抵人数、载具耐久和购车成本；空车不产生运兵奖励。"])
	_event(43.0,"highlight",Rect2(1275,650,290,310))
	_event(48.0,"point",Vector2(425,114))
	_event(48.4,"fit")
	_event(49.0,"chapter",["09 / 观察图层","返回全图，开启兵力密度和名称。\n快速辨认三方兵力分布，再恢复清爽视图。"])
	_event(49.0,"highlight",Rect2(263,150,977,567))
	_event(49.3,"point",Vector2(735,114))
	_event(49.7,"density",true)
	_event(50.7,"point",Vector2(842,114))
	_event(51.1,"names",true)
	_event(53.3,"names",false)
	_event(54.1,"density",false)
	_event(54.6,"point",Vector2(627,775))
	_event(55.0,"chapter",["10 / 现金走势","把团队得分切换成现金余额。\n比较三方经济积累，观察收入与装备消耗的变化。"])
	_event(55.0,"chart_menu")
	_event(55.9,"chart",1)
	_event(56.0,"highlight",Rect2(263,753,473,222))
	_event(61.0,"chart_menu")
	_event(61.9,"chart",2)
	_event(62.0,"chapter",["11 / 兵力走势","切换为区域实际人数。\n它显示前线参与变化；热区加权人数另见顶部。"])
	_event(67.0,"chart_menu")
	_event(67.9,"chart",0)
	_event(68.0,"chapter",["12 / 得分与排行","切回团队得分，再打开全员排行。\n个人赚钱与团队领先，是两个需要同时观察的指标。"])
	_event(70.0,"point",Vector2(1073,114))
	_event(70.5,"roster")
	_event(70.5,"highlight",Rect2())
	_event(75.8,"point",Vector2(1350,130))
	_event(76.3,"close")
	_event(77.0,"point",Vector2(1335,114))
	_event(77.5,"report")
	_event(77.5,"chapter",["13 / 中文复盘报告","导出本局快照：三方战局、各类玩家人均净收益与收支来源。\n报告与明细实际保存。"])
	_event(82.0,"report_scroll")
	_event(85.2,"point",Vector2(1350,130))
	_event(85.7,"close")
	_event(86.0,"fit")
	_event(86.1,"speed",4.0)
	_event(86.5,"chapter",["继续你的实验","改行为分布、种子与奖励倍率。\n可重复对照；未核实数值始终标为社区观测或模型假设。"])
	_event(87.0,"highlight",Rect2(20,150,224,419))
	_event(88.0,"point",Vector2(140,254))
	_event(89.5,"save_log")
	events.sort_custom(func(a,b): return a.at < b.at)

func _process(delta: float) -> void:
	var now: float = float(frame)/30.0
	while event_index < events.size() and float(events[event_index].at) <= now+0.00001:
		_dispatch(events[event_index])
		event_index += 1
	annotation_panel.visible = not app.popup.visible
	if move_until > now:
		var drag_delta := Vector2(-90,45)*delta
		var motion := InputEventMouseMotion.new()
		motion.relative = drag_delta
		app.map_view._map_input(motion)
		cursor_target += drag_delta
	cursor = cursor.lerp(cursor_target,minf(1.0,delta*12.0))
	click_age += delta
	counter.text = "演示 %02d:%02d / 01:30   ·   实际运行" % [int(now)/60,int(now)%60]
	frame += 1
	queue_redraw()

func _dispatch(e: Dictionary) -> void:
	var value = e.value
	var name: String = e.action
	match name:
		"chapter":
			heading.text = value[0]
			explanation.text = value[1]
		"point": cursor_target = value
		"highlight": highlight = value
		"pause":
			if not app.paused: app._toggle_pause()
			_click(Vector2(74,114))
		"resume":
			if app.paused: app._toggle_pause()
			_click(Vector2(74,114))
		"speed_menu":
			app.speed_select.show_popup()
			_click(Vector2(192,114))
		"speed":
			var index: int = app.SPEEDS.find(float(value))
			app.speed_select.select(index)
			app.speed_select.item_selected.emit(index)
			app.speed_select.get_popup().hide()
			_click(Vector2(192,114))
		"step":
			app._step_thirty()
			_click(Vector2(315,114))
		"zoom":
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if int(value)>0 else MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			wheel.position = Vector2(492,285)
			app.map_view._map_input(wheel)
			_click(Vector2(755,435))
		"drag_start":
			var button := InputEventMouseButton.new()
			button.button_index = MOUSE_BUTTON_RIGHT
			button.pressed = true
			app.map_view._map_input(button)
			move_until = float(frame)/30.0 + 1.2
		"drag_end":
			var button := InputEventMouseButton.new()
			button.button_index = MOUSE_BUTTON_RIGHT
			button.pressed = false
			app.map_view._map_input(button)
		"pick_map":
			var actor: Dictionary = _pick_actor("sniper")
			var displayed: Vector2 = app.map_view.project(actor.pos)
			if not Rect2(20,20,930,520).has_point(displayed):
				app.map_view.center = actor.pos
				displayed = app.map_view.project(actor.pos)
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = displayed
			app.map_view._map_input(click)
			_click(displayed+app.map_view.position)
		"actor_menu":
			app.actor_select.show_popup()
			_click(Vector2(1410,218))
		"select_role":
			var actor: Dictionary = _pick_actor(str(value))
			app.actor_select.select(int(actor.id))
			app.actor_select.item_selected.emit(int(actor.id))
			app.actor_select.get_popup().hide()
			_click(Vector2(1410,218))
		"focus":
			app._focus()
			_click(Vector2(525,114))
		"fit":
			app.map_fit()
			_click(Vector2(425,114))
		"density":
			app.map_view.show_heat = bool(value)
			_click(Vector2(735,114))
		"names":
			app.map_view.show_labels = bool(value)
			_click(Vector2(842,114))
		"chart_menu":
			chart_selector.show_popup()
			_click(Vector2(627,775))
		"chart":
			chart_selector.select(int(value))
			chart_selector.item_selected.emit(int(value))
			chart_selector.get_popup().hide()
			_click(Vector2(627,775))
		"roster": app._show_roster()
		"close": app._close_popup()
		"report": app._export()
		"report_scroll": app.popup_text.get_v_scroll_bar().value = 250
		"save_log": _save_log()
	app._refresh()
	action_log.append({"frame":frame,"seconds":float(frame)/30.0,"action":name,"game_seconds":app.sim.time,"speed":app.speed,"selected_actor":app.selected_id,"metric":app.chart_view.metric,"zoom":app.map_view.zoom})
	print("DEMO %05d %.2fs %s sim=%.2f speed=%s" % [frame,float(frame)/30.0,name,app.sim.time,app.speed])

func _pick_actor(role: String) -> Dictionary:
	var best: Dictionary = {}
	var rank := -1e10
	for actor in app.sim.actors:
		if actor.role != role: continue
		var score: float = actor.earned
		if actor.hp>0: score += 1000000
		if actor.state=="active": score += 500000
		if role=="medic": score += float(actor.revives)*1000
		if role=="transport" and int(actor.vehicle)>=0:
			score += 2000000
			if app.sim.vehicles[int(actor.vehicle)].kind=="helicopter": score += 1000000
		if score>rank:
			rank=score
			best=actor
	return best if not best.is_empty() else app.sim.actors[0]

func _find_chart(node: Node) -> OptionButton:
	if node is OptionButton and node.item_count>0 and node.get_item_text(0)=="团队得分": return node
	for child in node.get_children():
		var found := _find_chart(child)
		if found != null: return found
	return null

func _click(point: Vector2) -> void:
	cursor_target = point
	click_position = point
	click_age = 0.0

func _save_log() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/video")
	var file := FileAccess.open("res://artifacts/video/demo_actions.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(action_log,"  "))

func _draw() -> void:
	if highlight.size.length()>1:
		draw_rect(highlight,Color(1.0,0.72,0.36,0.80),false,2.5)
	if click_age < 0.65:
		draw_arc(click_position,9+click_age*30,0,TAU,48,Color(1.0,0.78,0.42,1.0-click_age/0.65),2.5,true)
	var pointer := PackedVector2Array([cursor,cursor+Vector2(0,24),cursor+Vector2(6,17),cursor+Vector2(11,29),cursor+Vector2(16,26),cursor+Vector2(11,15),cursor+Vector2(22,15)])
	draw_colored_polygon(pointer,Color("ffe2ae"))
	pointer.append(cursor)
	draw_polyline(pointer,Color("17212b"),1.8,true)
	if app.popup.visible:
		return
	var progress := clampf(float(frame)/2700.0,0,1)
	draw_line(Vector2(36,798),Vector2(226,798),Color("394340"),3)
	draw_line(Vector2(36,798),Vector2(36+190*progress,798),Color("f2bc78"),3)
