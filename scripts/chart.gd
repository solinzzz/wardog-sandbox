extends Control

var sim
var metric := "scores"
var font: Font
const COLORS = [Color("ef777e"),Color("64b2fc"),Color("66d3a5")]

func _ready() -> void:
	font = get_theme_default_font()
	mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	if sim == null or font == null:
		return
	var plot := Rect2(47,15,size.x-63,size.y-48)
	var maximum := 100.0 if metric == "scores" else 1.0
	var minimum := 0.0
	if metric != "scores":
		for row in sim.history:
			for value in row.get(metric,[0,0,0]):
				maximum = maxf(maximum,float(value))
				minimum = minf(minimum,float(value))
	for i in range(5):
		var y := plot.position.y + plot.size.y * i/4.0
		draw_line(Vector2(plot.position.x,y),Vector2(plot.end.x,y),Color("24373c"),1)
		var value := maximum-(maximum-minimum)*i/4.0
		var label := "%.0f" % value if absf(value)<1000 else "%.0fk" % (value/1000.0)
		draw_string(font,Vector2(2,y+4),label,HORIZONTAL_ALIGNMENT_RIGHT,36,11,Color("78978e"))
	if sim.history.size()>1:
		var duration: float = maxf(sim.time,30)
		for team in range(3):
			var points := PackedVector2Array()
			for row in sim.history:
				var value: float = float(row.get(metric,[0,0,0])[team])
				points.append(Vector2(plot.position.x+float(row.time)/duration*plot.size.x,plot.end.y-(value-minimum)/(maximum-minimum)*plot.size.y))
			draw_polyline(points,COLORS[team],2,true)
	else:
		draw_string(font,plot.position+Vector2(30,plot.size.y/2),"每 30 秒采样 · 正在等待数据",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("78978e"))
	draw_string(font,Vector2(plot.position.x,size.y-9),"00:00",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("78978e"))
	var seconds: int = int(sim.time)
	draw_string(font,Vector2(plot.end.x-40,size.y-9),"%02d:%02d" % [seconds/60,seconds%60],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("78978e"))
