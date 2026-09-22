extends Control

signal actor_selected(id: int)

const TEAM_COLORS = [Color("ef777e"), Color("64b2fc"), Color("66d3a5")]
var sim
var selected_id := 0
var center := Vector2(3000, 3000)
var zoom := 1.0
var dragging := false
var show_trails := true
var show_heat := false
var show_labels := false
var follow := false
var buildings: Array = []
var contours: Array = []
var font: Font

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	font = get_theme_default_font()
	var r := RandomNumberGenerator.new()
	r.seed = 81403
	for i in range(270):
		var p := Vector2(r.randf_range(1650, 4320), r.randf_range(1600, 4370))
		buildings.append(Rect2(p, Vector2(r.randf_range(35, 90), r.randf_range(22, 65))))
	for i in range(22):
		var points := PackedVector2Array()
		var c := Vector2(r.randf_range(-1000, 7000), r.randf_range(-1000, 7000))
		for j in range(65):
			var a := float(j) / 64.0 * TAU
			var rad := 170 + i * 52 + sin(a * 4 + i) * 50
			points.append(c + Vector2(cos(a) * rad, sin(a) * rad * 0.7))
		contours.append(points)
	gui_input.connect(_map_input)

func scale_factor() -> float:
	return minf(size.x / 6300.0, size.y / 6300.0) * zoom

func project(p: Vector2) -> Vector2:
	return (p - center) * scale_factor() + size * 0.5

func unproject(p: Vector2) -> Vector2:
	return (p - size * 0.5) / scale_factor() + center

func fit() -> void:
	center = Vector2(3000, 3000)
	zoom = 1.0
	follow = false
	queue_redraw()

func focus_actor() -> void:
	if sim and selected_id < sim.actors.size():
		center = sim.actors[selected_id].pos
		zoom = maxf(zoom, 2.3)
		follow = true
		queue_redraw()

func _process(delta: float) -> void:
	if sim == null:
		return
	if follow and selected_id < sim.actors.size():
		center = sim.actors[selected_id].pos
	elif get_viewport().gui_get_focus_owner() == null:
		var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		center += direction * 850 * delta / scale_factor()
	center = center.clamp(Vector2(-1000, -1000), Vector2(7000, 7000))
	queue_redraw()

func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed
			follow = false
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var old := unproject(event.position)
			zoom = clampf(zoom * (1.16 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.16), 0.65, 8.0)
			center += old - unproject(event.position)
			follow = false
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and sim:
			var best := 19.0
			var chosen := -1
			for a in sim.actors:
				var dist: float = project(a.pos).distance_to(event.position)
				if dist < best:
					best = dist
					chosen = a.id
			if chosen >= 0:
				selected_id = chosen
				actor_selected.emit(chosen)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		center -= event.relative / scale_factor()
		accept_event()

func _line_world(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	draw_line(project(a), project(b), color, width, true)

func _text(p: Vector2, value: String, color: Color, font_size: int = 12) -> void:
	draw_string(font, p, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101e25"))
	if sim == null or font == null:
		return
	var s := scale_factor()
	for contour in contours:
		var points := PackedVector2Array()
		for p in contour:
			points.append(project(p))
		draw_polyline(points, Color(0.21, 0.33, 0.31, 0.20), 1.0, true)
	for i in range(-2000, 8500, 500):
		var alpha := 0.16 if i % 1000 == 0 else 0.07
		_line_world(Vector2(i, -2500), Vector2(i, 8500), Color(0.5, 0.65, 0.63, alpha))
		_line_world(Vector2(-2500, i), Vector2(8500, i), Color(0.5, 0.65, 0.63, alpha))
	var roads := [[Vector2(835,1750), Vector2(1850,1750), Vector2(2770,2770),Vector2(4000,3400),Vector2(5165,1750)], [Vector2(3000,5500), Vector2(2900,4150), Vector2(2770,2770), Vector2(3100,1800), Vector2(5165,1750)], [Vector2(1900,3100),Vector2(3100,3100),Vector2(4300,2100)]]
	for road in roads:
		for i in range(road.size()-1):
			_line_world(road[i], road[i+1], Color("263938"), maxf(4.0, 48*s))
			_line_world(road[i], road[i+1], Color("4c5850"), 1.0)
	for b in buildings:
		var rect := Rect2(project(b.position), b.size * s)
		draw_rect(rect, Color("293b3b"))
		if zoom > 1.5:
			draw_rect(rect, Color("42524b"), false, 0.8)
	var zone: Rect2 = sim.control_zone
	draw_rect(Rect2(project(zone.position), zone.size*s), Color(0.48, 0.69, 0.63, 0.05))
	draw_rect(Rect2(project(zone.position), zone.size*s), Color("729c92"), false, 1.5)
	_text(project(zone.position) + Vector2(0,-10), "CONTROL ZONE / 2 × 2 km", Color("a9c9bf"), 12)
	var hot: Vector2 = project(sim.hot_center)
	var radius: float = sim.hot_radius * s
	draw_circle(hot, radius, Color(0.96,0.65,0.33,0.12))
	draw_arc(hot, radius, 0, TAU, 80, Color("efa654"), 2.0, true)
	draw_arc(hot, radius + 5, 0, TAU, 80, Color(0.96,0.65,0.33,0.16), 1.0, true)
	_text(hot + Vector2(-35,-radius-10), "HOT ZONE ×2", Color("ffc27d"), 12)
	for t in range(3):
		var p: Vector2 = project(sim.base_positions[t])
		var c: Color = TEAM_COLORS[t]
		draw_circle(p, 24, Color(c, 0.09))
		draw_rect(Rect2(p-Vector2(9,9), Vector2(18,18)), Color(c,0.15))
		draw_rect(Rect2(p-Vector2(9,9), Vector2(18,18)), c, false, 1.8)
		draw_line(p-Vector2(5,0),p+Vector2(5,0), c,1.5)
		draw_line(p-Vector2(0,5),p+Vector2(0,5), c,1.5)
		_text(p+Vector2(-34,42), ["VALKYRA / 红", "LONESTAR / 蓝", "MANTICORE / 绿"][t], c, 12)
	for fob in sim.fobs:
		if fob.hp <= 0:
			continue
		var p: Vector2 = project(fob.pos)
		var c: Color = TEAM_COLORS[fob.team]
		draw_circle(p, 15, Color(c,0.12))
		draw_polyline(PackedVector2Array([p+Vector2(-9,5),p+Vector2(0,-8),p+Vector2(9,5),p+Vector2(-9,5)]),c,2,true)
		_text(p+Vector2(12,0), "FOB %d" % int(fob.supply), c, 11)
	if show_heat:
		for a in sim.actors:
			if a.hp > 0:
				draw_circle(project(a.pos), 130*s, Color(TEAM_COLORS[a.team], 0.07))
	for a in sim.actors:
		var p: Vector2 = project(a.pos)
		if not Rect2(Vector2(-30,-30),size+Vector2(60,60)).has_point(p):
			continue
		var c: Color = TEAM_COLORS[a.team]
		if show_trails and (a.id == selected_id or zoom > 1.8) and a.trail.size() > 1:
			var points := PackedVector2Array()
			for pt in a.trail:
				points.append(project(pt))
			draw_polyline(points, Color(c,0.25 if a.id != selected_id else 0.65), 1.2, true)
		if a.id == selected_id:
			draw_arc(p, 12, 0, TAU, 32, Color("ffe0ac"), 2.0, true)
			draw_dashed_line(p,project(a.target),Color(1.0,0.84,0.57,0.6),1.0,6.0,true)
		if a.hp <= 0:
			draw_line(p+Vector2(-3,-3),p+Vector2(3,3),Color(c,0.5),1.5)
			draw_line(p+Vector2(-3,3),p+Vector2(3,-3),Color(c,0.5),1.5)
		elif int(a.vehicle) >= 0:
			draw_circle(p, 2, c)
		else:
			var r := 4.5 if a.id == selected_id else 3.1
			draw_circle(p,r+1.5, Color("0c151b"))
			draw_circle(p,r,c)
			if a.role == "medic":
				draw_line(p-Vector2(2,0),p+Vector2(2,0),Color.WHITE,1)
				draw_line(p-Vector2(0,2),p+Vector2(0,2),Color.WHITE,1)
		if show_labels or a.id == selected_id:
			_text(p+Vector2(12,-11), a.name, Color("e5eee9"),12)
	for v in sim.vehicles:
		if v.hp <= 0:
			continue
		var p: Vector2 = project(v.pos)
		var c: Color = TEAM_COLORS[v.team]
		var air: bool = "heli" in str(v.kind) or "mh6" in str(v.kind) or "z20" in str(v.kind)
		if air:
			draw_circle(p,8,Color("0b1820"))
			draw_line(p+Vector2(-10,0),p+Vector2(10,0),c,2)
			draw_line(p+Vector2(0,-7),p+Vector2(0,7),c,2)
		else:
			draw_rect(Rect2(p-Vector2(6,4), Vector2(12,8)), Color("0b1820"))
			draw_rect(Rect2(p-Vector2(6,4), Vector2(12,8)),c,false,1.5)
			draw_line(p,p+Vector2(9,-3),c,1.5)
		if zoom > 2.0:
			_text(p+Vector2(10,15), str(v.kind),c,10)
	# Screen furniture stays legible at every zoom.
	draw_rect(Rect2(14,14,200,48), Color(0.04,0.08,0.1,0.94))
	_text(Vector2(26,34), "局部战区  /  6 × 6 km", Color("c4d6d3"),13)
	_text(Vector2(26,51), "示意地形 · 非原版地图复刻",Color("77978e"),10)
	_text(Vector2(size.x-50,31), "N ↑", Color("ccd9d2"),15)
	var meters := 500.0 if zoom < 2 else 100.0
	var scale_y := size.y-28.0
	draw_line(Vector2(22,scale_y),Vector2(22+meters*s,scale_y),Color("a6beb5"),2)
	draw_line(Vector2(22,scale_y-4),Vector2(22,scale_y+4),Color("a6beb5"),1)
	draw_line(Vector2(22+meters*s,scale_y-4),Vector2(22+meters*s,scale_y+4),Color("a6beb5"),1)
	_text(Vector2(24,scale_y-9), "%d m" % int(meters),Color("a6beb5"),11)
	_text(Vector2(size.x-156,size.y-18), "ZOOM %d%%" % int(zoom*100),Color("91aea6"),11)
	draw_rect(Rect2(Vector2.ZERO,size),Color("2c4147"),false,1)
