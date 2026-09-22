extends RefCounted
## WAR DOGS behavioural sandbox. All unverified tuning lives in data/rules.json.
## Fixed .25s ticks make a seed invariant to display frame rate / playback speed.
const FIXED_STEP: float = 0.25
const ROLES: Array = ["assault", "medic", "transport", "engineer", "armor", "sniper", "opportunist"]
const ROLE_NAMES: Dictionary = {"assault":"占点突击", "medic":"救援医疗", "transport":"运输司机", "engineer":"后勤工程", "armor":"装甲驾驶", "sniper":"游走侦察", "opportunist":"逐利佣兵"}
var config: Dictionary = {}
var actors: Array = []
var teams: Array = []
var vehicles: Array = []
var fobs: Array = []
var events: Array = []
var ledger: Array = []
var history: Array = []
var time: float = 0.0
var winner: int = -1
var finished: bool = false
var seed_value: int = 42
var scenario: String = "balanced"
var hot_center: Vector2 = Vector2(3000, 3000)
var hot_radius: float = 250.0
var control_zone: Rect2 = Rect2(2000, 2000, 2000, 2000)
var base_positions: Array = [Vector2(835,1750), Vector2(5165,1750), Vector2(3000,5500)]
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _accumulator: float = 0.0
var _tick_index: int = 0
var _all_events: Array = []
var _start_positions: Array = []
var _spatial: Dictionary = {}
var _last_score: float = 0.0
var _last_cash: float = 0.0

func setup(seed: int = 42, scenario_id: String = "balanced", overrides: Dictionary = {}, carry_cash: Array = []) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	config = parsed if parsed is Dictionary else {}
	_merge(config, overrides)
	seed_value = seed
	scenario = scenario_id if scenario_id in ["balanced", "profit", "coordinated"] else "balanced"
	rng.seed = seed_value
	actors.clear(); teams.clear(); vehicles.clear(); fobs.clear(); events.clear(); ledger.clear(); history.clear(); _all_events.clear()
	time = 0.0; winner = -1; finished = false; _tick_index = 0; _accumulator = 0.0; _last_score = 0.0; _last_cash = 0.0
	hot_radius = float(config.get("hot_radius",250.0))
	hot_center = Vector2(3000,3000)
	var names: Array = ["VALKYRA", "LONESTAR", "MANTICORE"]
	var colors: Array = ["ef6478", "58a6ff", "56d9ac"]
	for t in range(3):
		teams.append({"id":t,"name":names[t],"color":colors[t],"score":0,"presence":0,"weighted_presence":0.0,"earned":0.0,"spent":0.0,"kills":0,"deaths":0,"revives":0,"deliveries":0})
		var size: int = clampi(int(config.team_sizes[t]),1,100)
		for j in range(size):
			var role: String = _pick_role(j,t)
			var id: int = actors.size()
			var cash: float = float(carry_cash[id]) if id < carry_cash.size() else float(config.starting_cash)
			var a: Dictionary = {"id":id,"name":"%s-%02d" % [names[t].left(3), j+1],"team":t,"role":role,"pos":base_positions[t],"hp":100.0,"state":"active","action":"整备出发","reason":"根据角色与前线态势选择目标","target":base_positions[t],"cash":maxf(0,cash),"initial_cash":maxf(0,cash),"earned":0.0,"spent":0.0,"kills":0,"deaths":0,"revives":0,"deliveries":0,"zone_seconds":0.0,"vehicle":-1,"income":{},"costs":{},"trail":[],"next_decision":0.0,"target_actor":-1,"task_timer":0.0,"respawn_at":0.0,"bleedout_at":0.0,"attacker":-1,"invulnerable_until":0.0,"last_heal":-100.0,"last_recon":-100.0,"fob_cargo":false,"supply_cargo":0,"hammer":false,"skill":rng.randf_range(0.7,1.25),"aggression":rng.randf_range(0.7,1.3),"life":0,"spawn":base_positions[t],"last_damage":-100.0,"rally":Vector2.ZERO}
			actors.append(a)
	# Create every actor before purchasing vehicles so seating always references real IDs.
	for a in actors:
		a["entered_zone"] = false
		a["last_fob_supply"] = -100.0
		a["kill_attacker_pos"] = Vector2.ZERO
		a["kill_multiplier"] = 1.0
		_spawn_actor(a, true)
	_event(-1,-1,"新局开始：%d 名玩家；%s 场景；现金与装备按模型参数结算" % [actors.size(),scenario],"match")
	_update_presence()
	_record_history()

func _merge(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if source[key] is Dictionary and target.get(key) is Dictionary:
			_merge(target[key],source[key])
		else:
			target[key] = source[key]

func _pick_role(index: int, team: int) -> String:
	var roster: Array = ["transport","engineer","assault","medic","assault","armor","assault","sniper","opportunist","assault","medic","assault","transport","engineer","assault","medic","sniper","assault","opportunist","armor","assault","medic","assault","opportunist","sniper","assault","engineer","medic","assault","opportunist","assault","sniper","opportunist","assault"]
	if scenario == "profit" and index % 3 != 0 and index > 3:
		return "opportunist"
	if scenario == "coordinated" and team == 0:
		var coordinated: Array = ["transport","engineer","assault","medic","assault","assault","medic","assault","armor","assault","assault","sniper"]
		return str(coordinated[index % coordinated.size()])
	return str(roster[index % roster.size()])

func role_name(role: String) -> String:
	return str(ROLE_NAMES.get(role,role))

func get_actor(id: int) -> Dictionary:
	return actors[id] if id >= 0 and id < actors.size() else {}

func step(dt: float) -> void:
	if finished or dt <= 0.0:
		return
	_accumulator += dt
	while _accumulator + 0.000001 >= FIXED_STEP and not finished:
		_accumulator -= FIXED_STEP
		_fixed_step()

func _fixed_step() -> void:
	time += FIXED_STEP
	_tick_index += 1
	var angle: float = time / float(config.hot_period) * TAU
	hot_center = Vector2(3000.0 + sin(angle) * 530.0, 3000.0 + cos(angle * 0.75) * 470.0)
	for a in actors:
		if a.state == "dead":
			if time >= float(a.respawn_at): _spawn_actor(a)
			continue
		if a.state == "downed":
			if time >= float(a.bleedout_at): _die(a)
			continue
		if a.state == "embarked": continue
		if int(a.vehicle) >= 0: continue
		if time >= float(a.next_decision):
			_decide(a)
			a.next_decision = time + 3.0 + float(a.id % 9) * 0.25
		_move_actor(a)
		_work(a)
	for v in vehicles:
		if v.state != "destroyed": _move_vehicle(v)
	if _tick_index % 4 == 0:
		_build_spatial()
		_combat()
		_update_presence()
		for a in actors:
			if _alive(a) and control_zone.has_point(a.pos):
				a.zone_seconds += 1.0
				if not bool(a.entered_zone):
					a.entered_zone = true
					_reward(a,"enter_zone",float(config.rewards.get("enter_zone",250.0)),{"fixed_multiplier":1.0})
		_update_fob_resupply()
	if _tick_index % 12 == 0:
		for a in actors:
			if _alive(a):
				a.trail.append(a.pos)
				if a.trail.size() > 50: a.trail.pop_front()
	if time - _last_score + 0.0001 >= float(config.score_interval):
		_last_score = time
		_score_tick()
	if not finished and time - _last_cash + 0.0001 >= float(config.get("cash_interval",24.0)):
		_last_cash = time
		_cash_tick()
	if not finished and time >= float(config.time_limit):
		finished = true
		_event(-1,-1,"达到沙盘时间上限；无人达胜利分数，结果截尾/未决", "timeout")

func _alive(a: Dictionary) -> bool:
	return a.state in ["active", "embarked"] and float(a.hp) > 0.0

func _spawn_actor(a: Dictionary, initial: bool = false) -> void:
	var team: int = int(a.team)
	var spawn: Vector2 = base_positions[team]
	# Forward spawning consumes real FOB supply. Vehicle drivers need the main-base vendor.
	if bool(config.get("enable_fob_respawn",false)) and not initial and not a.role in ["transport","armor"]:
		for f in fobs:
			if int(f.team) == team and float(f.hp) > 0 and int(f.supply) >= int(config.fob_respawn_supply):
				spawn = f.pos
				f.supply -= int(config.fob_respawn_supply)
				break
	a.pos = spawn + Vector2(rng.randf_range(-70,70), rng.randf_range(-70,70))
	a.spawn = spawn; a.hp = 100.0; a.state = "active"; a.vehicle = -1; a.target_actor = -1
	a.life += 1; a.next_decision = time; a.task_timer = 0.0; a.invulnerable_until = time + 7.0
	a.hammer = false; a.fob_cargo = false; a.supply_cargo = 0
	var price: float = float(config.loadout_cost.get(a.role,500))
	if _spend(a,price,"loadout",{"life":a.life}):
		a.action = "购买装备出击"
	else:
		a.action = "免费基础包出击"
		a.reason = "余额不足；假设免费基本步兵包防止破产死锁"
		_event(team,a.id,"余额不足，领取免费基础包", "economy")
	if a.role == "transport":
		var owned_transports: int = 0
		for v in vehicles:
			if int(v.team)==team and v.kind in ["transport","helicopter"]: owned_transports+=1
		var kind: String = "helicopter" if owned_transports%2==1 and float(a.cash)>=float(config.vehicles.helicopter.cost) else "transport"
		_purchase_vehicle(a,kind)
	elif a.role == "armor":
		_purchase_vehicle(a,"armor")
	if a.role == "engineer" and spawn.distance_to(base_positions[team]) < 250.0:
		a.hammer = _spend(a,float(config.hammer_cost),"hammer",{"assumes_permanent_unlock":true})
		var allocated: int = 0
		for f in fobs:
			if int(f.team) == team and float(f.hp) > 0: allocated += 1
		for other in actors:
			if int(other.team) == team and bool(other.fob_cargo): allocated += 1
		if bool(a.hammer) and allocated < int(config.fob_max_per_team):
			a.fob_cargo = _spend(a,float(config.fob_cost),"fob",{"life":a.life})
		if not a.fob_cargo and _spend(a,float(config.supply_cost),"supplies",{}):
			a.supply_cargo = int(config.supply_amount)
	a.target = _objective(a)

func _purchase_vehicle(a: Dictionary, kind: String) -> void:
	var spec: Dictionary = config.vehicles[kind]
	if not _spend(a,float(spec.cost),"vehicle",{"kind":kind}): return
	var id: int = vehicles.size()
	var v: Dictionary = {"id":id,"team":int(a.team),"kind":kind,"pos":a.pos,"hp":float(spec.hp),"max_hp":float(spec.hp),"driver":int(a.id),"passengers":[],"state":"loading" if kind in ["transport","helicopter"] else "combat","speed":float(spec.speed),"seats":int(spec.seats),"target":_entry_point(int(a.team)),"wait_until":time + 14.0,"pickups":{},"delivered":0,"distance":0.0,"last_repair":-100.0}
	vehicles.append(v)
	a.vehicle = id; a.action = "等待战友登车" if kind in ["transport","helicopter"] else "驾驶装甲前出"

func _entry_point(team: int) -> Vector2:
	var center: Vector2 = Vector2(3000,3000)
	return center + (Vector2(base_positions[team]) - center).normalized() * 760.0

func _objective(a: Dictionary) -> Vector2:
	var team: int = int(a.team)
	var coordinated: bool = scenario == "coordinated" and team == 0
	var center: Vector2 = hot_center
	var spread: float = 540.0
	if a.role == "opportunist": spread = 130.0
	elif a.role == "sniper":
		center = hot_center + (Vector2(base_positions[team]) - hot_center).normalized() * 390.0
		spread = 180.0
	elif a.role == "medic": spread = 360.0
	elif coordinated:
		spread = 190.0
		center = hot_center + (Vector2(base_positions[team]) - hot_center).normalized() * 110.0
	var p: Vector2 = center + Vector2(rng.randf_range(-spread,spread),rng.randf_range(-spread,spread))
	return Vector2(clampf(p.x,2050,3950),clampf(p.y,2050,3950))

func _decide(a: Dictionary) -> void:
	a.target_actor = -1
	if a.role == "medic":
		var patient: Dictionary = _find_patient(a,480.0)
		if not patient.is_empty():
			a.target_actor = patient.id; a.target = patient.pos
			a.action = "接近倒地队友" if patient.state == "downed" else "接近伤员治疗"
			a.reason = "救援真实伤员可恢复前线人数并赚取医疗奖励"
			return
	if a.role == "engineer":
		if bool(a.fob_cargo):
			a.target = _entry_point(int(a.team)) + (Vector2(base_positions[int(a.team)]) - Vector2(3000,3000)).normalized() * 240.0
			a.action = "运送并架设前沿基地"; a.reason = "已购买 FOB 与大型锤；抵达前沿后建造"
			return
		if int(a.supply_cargo) > 0:
			for f in fobs:
				if int(f.team) == int(a.team) and float(f.hp)>0 and int(f.supply)<200:
					a.target = f.pos; a.action = "前往 FOB 补给"; a.reason = "已携带实物补给；交付后补充基地有限支援物资"
					return
		else:
			for f in fobs:
				if int(f.team) == int(a.team) and float(f.hp)>0 and int(f.supply)<200 and float(a.cash)>=float(config.supply_cost):
					a.target = base_positions[int(a.team)]; a.action = "返回基地购买实物补给"; a.reason = "FOB 存量减少，需要实际采购和搬运"
					return
		for v in vehicles:
			if int(v.team) == int(a.team) and v.state != "destroyed" and float(v.hp) < float(v.max_hp)*0.7 and Vector2(v.pos).distance_to(a.pos)<300:
				a.target = v.pos; a.action = "抢修受损载具"; a.reason = "修复真实受损载具以延长车组生存时间"
				return
	if a.role == "opportunist":
		var patient: Dictionary = _find_patient(a,90.0)
		if not patient.is_empty() and patient.state == "downed":
			a.target_actor = patient.id; a.target = patient.pos; a.action = "顺路施救赚钱"; a.reason = "邻近复活的预计收益高于继续赶路"
			return
	if float(a.hp) < 30.0 and a.role in ["sniper","opportunist"] and time-float(a.last_damage)<12.0:
		a.target = _entry_point(int(a.team)); a.action = "脱离火线保本"; a.reason = "生命值偏低，避免死亡后重购装备损失"
		return
	if Vector2(a.pos).distance_to(a.target) < 55.0 or (a.role == "opportunist" and Vector2(a.target).distance_to(hot_center)>hot_radius):
		a.target = _objective(a)
	a.action = "争夺双倍收益热区" if a.role == "opportunist" else "推进并维持占区人数"
	if a.role == "sniper": a.action = "游走侦察与远距火力"
	if a.role == "engineer": a.action = "伴随步兵守区与工程支援"
	a.reason = "热区现金与占区权重均翻倍" if a.role == "opportunist" else "控制区每 30 秒按加权人数决定队伍得分"
	if scenario == "coordinated" and int(a.team)==0:
		a.reason = "协调策略：集中热区、优先救援与队友协同"

func _find_patient(a: Dictionary, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = radius
	for other in actors:
		if other.id == a.id or int(other.team) != int(a.team) or not other.state in ["active","downed"] or int(other.vehicle)>=0: continue
		if other.state != "downed" and float(other.hp)>55.0: continue
		var d: float = Vector2(a.pos).distance_to(other.pos)
		var effective: float = d * (0.55 if other.state == "downed" else 1.0)
		if d <= radius and effective < best_distance:
			best = other; best_distance = effective
	return best

func _move_actor(a: Dictionary) -> void:
	if int(a.target_actor) >= 0:
		var patient: Dictionary = actors[int(a.target_actor)]
		if patient.state in ["active","downed"]: a.target = patient.pos
	var speed: float = float(config.walk_speed)
	if float(a.hp) < 35.0: speed *= 0.7
	if a.role == "sniper": speed *= 0.9
	a.pos = Vector2(a.pos).move_toward(a.target,speed*FIXED_STEP)

func _work(a: Dictionary) -> void:
	if int(a.target_actor)>=0:
		var patient: Dictionary = actors[int(a.target_actor)]
		if Vector2(a.pos).distance_to(patient.pos) <= 18.0:
			a.task_timer += FIXED_STEP
			a.action = "正在救援" if patient.state=="downed" else "正在治疗"
			if float(a.task_timer)>=4.0:
				a.task_timer = 0.0
				if patient.state == "downed": _revive(a,patient)
				elif _alive(patient) and float(patient.hp)<90.0 and time-float(a.last_heal)>=20.0:
					var restored: float = minf(35.0,100.0-float(patient.hp))
					patient.hp += restored; a.last_heal = time
					_reward(a,"heal",float(config.rewards.heal),{"patient":patient.id,"hp_restored":restored,"distance":Vector2(a.pos).distance_to(patient.pos)})
				a.target_actor = -1; a.next_decision = time
		else: a.task_timer = 0.0
		return
	if a.role != "engineer": return
	if bool(a.fob_cargo) and Vector2(a.pos).distance_to(a.target)<25.0:
		a.task_timer += FIXED_STEP; a.action = "正在建造前沿基地"
		if float(a.task_timer)>=12.0:
			fobs.append({"id":fobs.size(),"team":int(a.team),"pos":a.pos,"supply":int(config.fob_supply),"hp":1400.0,"max_hp":1400.0,"owner":int(a.id),"built_at":time})
			a.fob_cargo = false; a.task_timer = 0.0; a.next_decision = time
			_event(a.team,a.id,"架设 FOB：为附近伤员提供有限补给（模型假设）", "build")
		return
	for f in fobs:
		if int(f.team)==int(a.team) and float(f.hp)>0 and Vector2(a.pos).distance_to(f.pos)<30.0 and int(a.supply_cargo)>0 and int(f.supply)<200:
			var supplied: int = int(a.supply_cargo)
			f.supply += supplied; a.supply_cargo = 0
			_reward(a,"supply",float(config.rewards.supply),{"fob":f.id,"amount":supplied})
			_event(a.team,a.id,"交付 %d 单位 FOB 补给" % supplied,"supply")
	for v in vehicles:
		if int(v.team)==int(a.team) and v.state!="destroyed" and Vector2(a.pos).distance_to(v.pos)<25.0:
			v.hp = minf(float(v.max_hp),float(v.hp)+14.0*FIXED_STEP)
	# Replenishment requires returning to the main-base vendor.
	if int(a.supply_cargo)==0 and Vector2(a.pos).distance_to(base_positions[int(a.team)])<120.0 and _spend(a,float(config.supply_cost),"supplies",{}):
		a.supply_cargo = int(config.supply_amount)

func _revive(medic: Dictionary, patient: Dictionary) -> bool:
	var distance: float = Vector2(medic.pos).distance_to(patient.pos)
	if not _alive(medic) or patient.state!="downed" or int(medic.team)!=int(patient.team) or distance>18.0: return false
	patient.state = "active"; patient.hp = 55.0; patient.next_decision = time; patient.invulnerable_until = time + 4.0
	patient.attacker = -1; patient.action = "获救后重新加入战斗"
	medic.revives += 1; teams[int(medic.team)].revives += 1
	_reward(medic,"revive",float(config.rewards.revive),{"patient":patient.id,"distance":distance,"before_state":"downed","after_state":"active"})
	_event(medic.team,medic.id,"救活 %s，恢复一名前线队友" % patient.name,"revive")
	return true

func _update_fob_resupply() -> void:
	# Experimental support model: actual wounded recipients consume finite stock.
	for f in fobs:
		if float(f.hp)<=0 or int(f.supply)<10: continue
		for a in actors:
			if not _alive(a) or int(a.team)!=int(f.team) or float(a.hp)>=90.0: continue
			if Vector2(a.pos).distance_to(f.pos)>300.0 or time-float(a.last_fob_supply)<30.0: continue
			if int(f.supply)<10: break
			f.supply-=10; a.hp=minf(100.0,float(a.hp)+15.0); a.last_fob_supply=time

func _move_vehicle(v: Dictionary) -> void:
	var driver: Dictionary = actors[int(v.driver)]
	if not _alive(driver): _destroy_vehicle(v,-1); return
	if v.kind in ["transport","helicopter"]:
		if v.state=="loading":
			_load_passengers(v)
			if time>=float(v.wait_until) and v.passengers.size()>0:
				v.state="outbound"; v.target=_entry_point(int(v.team)); driver.action="运送 %d 名真实乘客" % v.passengers.size(); driver.reason="抵达前线并卸载后按实际乘客结算"
			elif time>=float(v.wait_until)+28.0 and v.passengers.is_empty():
				v.state="outbound"; v.target=_entry_point(int(v.team)); driver.action="空车向前线巡回接驳"; driver.reason="无乘客时没有运输收入"
		elif v.state=="outbound" and Vector2(v.pos).distance_to(v.target)<30.0:
			_unload_passengers(v)
			v.state="returning"; v.target=base_positions[int(v.team)]; driver.action="返回主基地接驳"; driver.reason="前一批乘客已下车；返程没有虚构乘客收益"
		elif v.state=="returning" and Vector2(v.pos).distance_to(v.target)<50.0:
			v.state="loading"; v.wait_until=time+12.0; driver.action="等待新乘客登车"
	else:
		if Vector2(v.pos).distance_to(v.target)<55.0 or (_tick_index+int(v.id))%80==0:
			v.target=_objective(driver)
		driver.action="驾驶装甲支援占区"; driver.reason="火力与装甲提升交战能力，但损失需要重新购买"
	if v.state!="loading":
		var old_pos: Vector2 = v.pos
		v.pos=old_pos.move_toward(v.target,float(v.speed)*FIXED_STEP)
		v.distance += old_pos.distance_to(v.pos)
	driver.pos=v.pos; driver.target=v.target
	for id in v.passengers:
		var passenger: Dictionary = actors[int(id)]
		passenger.pos=v.pos; passenger.target=v.target

func _load_passengers(v: Dictionary) -> void:
	for a in actors:
		if v.passengers.size()>=int(v.seats): break
		if int(a.team)!=int(v.team) or a.state!="active" or int(a.vehicle)>=0 or a.id==v.driver: continue
		if Vector2(a.pos).distance_to(v.pos)>140.0: continue
		if control_zone.has_point(a.pos): continue
		a.state="embarked"; a.vehicle=v.id; a.action="乘车前往前线"; a.reason="占用真实乘客座位，抵达后下车"
		v.passengers.append(int(a.id)); v.pickups[str(a.id)]={"pos":a.pos,"time":time,"life":a.life,"distance":v.distance}

func _unload_passengers(v: Dictionary) -> void:
	var driver: Dictionary = actors[int(v.driver)]
	var valid_ids: Array = []
	var trips: Array = []
	var delivered_count: int = 0
	for id in v.passengers.duplicate():
		var a: Dictionary = actors[int(id)]
		var pickup: Dictionary = v.pickups.get(str(id),{})
		if a.state!="embarked" or int(a.vehicle)!=int(v.id): continue
		a.state="active"; a.vehicle=-1; a.pos=Vector2(v.pos)+Vector2(rng.randf_range(-25,25),rng.randf_range(-25,25)); a.next_decision=time
		a.action="下车进入战区"
		var distance: float = Vector2(pickup.get("pos",v.pos)).distance_to(v.pos)
		# A real living passenger, same life, meaningful displacement, and frontline arrival are mandatory.
		if _alive(a) and int(pickup.get("life",-1))==int(a.life) and distance>=float(config.minimum_transport_distance) and control_zone.has_point(v.pos):
			delivered_count+=1; valid_ids.append(int(id)); trips.append({"passenger":id,"pickup":pickup.pos,"dropoff":v.pos,"distance":distance,"pickup_time":pickup.time,"life":a.life})
			_reward(driver,"transport",float(config.rewards.transport),{"passengers":[int(id)],"pickup":pickup.pos,"dropoff":v.pos,"distance":distance,"trips":[trips.back()]})
	v.passengers.clear(); v.pickups.clear()
	if delivered_count>0:
		driver.deliveries+=delivered_count; teams[int(v.team)].deliveries+=delivered_count; v.delivered+=delivered_count
		_event(v.team,driver.id,"将 %d 名队友运抵战区，逐人结算运输收益" % delivered_count,"transport")

func _build_spatial() -> void:
	_spatial.clear()
	for a in actors:
		if not _alive(a): continue
		var cell: Vector2i = Vector2i(floori(float(a.pos.x)/350.0),floori(float(a.pos.y)/350.0))
		if not _spatial.has(cell): _spatial[cell]=[]
		_spatial[cell].append(a.id)

func _combat() -> void:
	# One-second weapon abstraction; spatial bins avoid N-squared scans at every .25s tick.
	for a in actors:
		if not _alive(a) or a.state=="embarked" or time<float(a.invulnerable_until): continue
		if int(a.vehicle)>=0 and vehicles[int(a.vehicle)].kind in ["transport","helicopter"]: continue
		var armored: bool = int(a.vehicle)>=0 and vehicles[int(a.vehicle)].kind=="armor"
		var radius: float = 610.0 if armored else (540.0 if a.role=="sniper" else 320.0)
		var opponent: Dictionary = _nearest_enemy(a,radius)
		if not opponent.is_empty():
			var distance: float = Vector2(a.pos).distance_to(opponent.pos)
			var chance: float = clampf((1.0-distance/(radius*1.4))*float(a.skill)*0.48,0.08,0.75)
			if rng.randf()<chance:
				var damage: float = rng.randf_range(17.0,30.0) if not armored else rng.randf_range(34.0,62.0)
				if a.role=="sniper": damage*=1.5
				_hit(opponent,damage,int(a.id))
			if a.role=="sniper" and time-float(a.last_recon)>=40.0:
				a.last_recon=time
				_reward(a,"recon",float(config.rewards.recon),{"enemy":opponent.id,"distance":distance})
		# Infantry/armor can damage nearby FOBs; no cash is fabricated for empty repair loops.
		if armored or a.role in ["assault","engineer"]:
			for f in fobs:
				if int(f.team)!=int(a.team) and float(f.hp)>0 and Vector2(a.pos).distance_to(f.pos)<260.0:
					f.hp=maxf(0,float(f.hp)-(18.0 if armored else 4.0))
					if float(f.hp)<=0: _event(a.team,a.id,"摧毁敌方 FOB，切断其前沿出生", "combat")

func _nearest_enemy(a: Dictionary, radius: float) -> Dictionary:
	var cell: Vector2i=Vector2i(floori(float(a.pos.x)/350.0),floori(float(a.pos.y)/350.0))
	var best: Dictionary={}
	var best_dist: float=radius*radius
	for x in range(-2,3):
		for y in range(-2,3):
			for id in _spatial.get(cell+Vector2i(x,y),[]):
				var enemy: Dictionary=actors[int(id)]
				if int(enemy.team)==int(a.team) or not _alive(enemy) or time<float(enemy.invulnerable_until): continue
				var d: float=Vector2(a.pos).distance_squared_to(enemy.pos)
				if d<best_dist: best_dist=d; best=enemy
	return best

func _hit(victim: Dictionary, damage: float, attacker: int) -> void:
	if not _alive(victim) or time<float(victim.invulnerable_until): return
	victim.last_damage=time
	if int(victim.vehicle)>=0:
		var v: Dictionary=vehicles[int(victim.vehicle)]
		v.hp-=damage*(1.5 if actors[attacker].role=="engineer" else 1.0)
		if float(v.hp)<=0: _destroy_vehicle(v,attacker)
		return
	victim.hp=maxf(0.0,float(victim.hp)-damage)
	if float(victim.hp)<=0:
		victim.state="downed"; victim.bleedout_at=time+float(config.bleedout_seconds); victim.attacker=attacker
		victim.kill_attacker_pos=actors[attacker].pos
		victim.kill_multiplier=(_kill_location_multiplier(victim.kill_attacker_pos)+_kill_location_multiplier(victim.pos))*0.5
		victim.action="倒地等待救援"; victim.reason="倒计时结束死亡；附近队友实际接近才能复活"
		_event(victim.team,victim.id,"倒地，等待队友救援", "downed")

func _destroy_vehicle(v: Dictionary, attacker: int) -> void:
	if v.state=="destroyed": return
	v.state="destroyed"; v.hp=0.0
	var occupants: Array=v.passengers.duplicate()
	occupants.append(int(v.driver))
	v.passengers.clear(); v.pickups.clear()
	for id in occupants:
		var a: Dictionary=actors[int(id)]
		if not _alive(a): continue
		a.vehicle=-1; a.pos=Vector2(v.pos)+Vector2(rng.randf_range(-25,25),rng.randf_range(-25,25)); a.hp=0.0
		a.state="downed"; a.bleedout_at=time+float(config.bleedout_seconds); a.attacker=attacker; a.action="载具被毁，等待救援"
		a.kill_attacker_pos=actors[attacker].pos if attacker>=0 else v.pos
		a.kill_multiplier=(_kill_location_multiplier(a.kill_attacker_pos)+_kill_location_multiplier(a.pos))*0.5
	if attacker>=0 and int(actors[attacker].team)!=int(v.team):
		_reward(actors[attacker],"vehicle_destroyed",float(config.rewards.vehicle_destroyed),{"vehicle":v.id,"kind":v.kind})
	_event(v.team,v.driver,"%s 被摧毁，购车支出成为沉没成本" % str(config.vehicles[v.kind].label),"vehicle_loss")

func _die(a: Dictionary) -> void:
	if a.state=="dead": return
	a.deaths+=1; teams[int(a.team)].deaths+=1
	if int(a.attacker)>=0:
		var killer: Dictionary=actors[int(a.attacker)]
		if int(killer.team)!=int(a.team):
			killer.kills+=1; teams[int(killer.team)].kills+=1
			var multiplier: float=float(a.get("kill_multiplier",1.0))
			_reward(killer,"kill",float(config.rewards.kill),{"victim":a.id,"victim_life":a.life,"kill_position":a.pos,"attacker_position":a.kill_attacker_pos,"fixed_multiplier":multiplier})
	a.hp=0.0; a.state="dead"; a.vehicle=-1; a.fob_cargo=false; a.supply_cargo=0; a.hammer=false
	a.respawn_at=time+float(config.respawn_seconds); a.action="阵亡等待重新部署"; a.reason="当前命装备丢失，复活时重新购买；账户余额保留"
	_event(a.team,a.id,"阵亡；%d 秒后重新购装部署" % int(config.respawn_seconds),"death")

func _update_presence() -> void:
	for t in teams: t.presence=0; t.weighted_presence=0.0
	for a in actors:
		if _alive(a) and control_zone.has_point(a.pos):
			teams[int(a.team)].presence+=1
			teams[int(a.team)].weighted_presence+=float(config.hot_presence_multiplier) if _in_hot(a.pos) else 1.0

func _score_tick() -> void:
	if finished: return
	_update_presence()
	var best: float=0.0
	var leading: Array=[]
	for t in range(3):
		var presence: float=float(teams[t].weighted_presence)
		if presence>best: best=presence; leading=[t]
		elif is_equal_approx(presence,best): leading.append(t)
	if best>0.0 and leading.size()==1:
		var lead: int=int(leading[0])
		teams[lead].score+=1
		_event(lead,-1,"控制区加权人数领先 +1 分（%s）" % str(teams[lead].weighted_presence),"score")
		if int(teams[lead].score)>=int(config.score_target):
			winner=lead; finished=true
			_event(lead,-1,"%s 先达 %d 分，赢得本局" % [teams[lead].name,int(config.score_target)],"victory")
	else:
		_event(-1,-1,"控制区人数持平或无人；本轮不加分（平局规则为模型假设）","score")
	_record_history()

func _cash_tick() -> void:
	for a in actors:
		if _alive(a) and control_zone.has_point(a.pos):
			_reward(a,"zone",float(config.rewards.zone),{"cash_tick":time,"in_hot":_in_hot(a.pos)})

func _kill_location_multiplier(pos: Vector2) -> float:
	if _in_hot(pos): return float(config.get("zone_kill_multiplier",5.0))*float(config.hot_cash_multiplier)
	return float(config.get("zone_kill_multiplier",5.0)) if control_zone.has_point(pos) else 1.0

func _in_hot(pos: Vector2) -> bool:
	return control_zone.has_point(pos) and pos.distance_squared_to(hot_center)<=hot_radius*hot_radius

func _reward(a: Dictionary, kind: String, base_amount: float, context: Dictionary = {}) -> void:
	if base_amount<=0.0: return
	var multiplier: float=float(config.hot_cash_multiplier) if _in_hot(a.pos) else 1.0
	if context.has("fixed_multiplier"): multiplier=float(context.fixed_multiplier)
	var amount: float=snappedf(base_amount*multiplier,0.01)
	a.cash+=amount; a.earned+=amount; a.income[kind]=float(a.income.get(kind,0.0))+amount
	teams[int(a.team)].earned+=amount
	var ctx: Dictionary=context.duplicate(true)
	ctx["multiplier"]=multiplier; ctx["base_amount"]=base_amount; ctx["reward_position"]=a.pos
	ledger.append({"time":time,"actor":int(a.id),"team":int(a.team),"kind":kind,"amount":amount,"balance":a.cash,"source":"community_observed:MetaForge" if kind in ["kill","zone","enter_zone"] else "assumption:config.rewards.%s" % kind,"context":ctx})

func _spend(a: Dictionary, amount: float, kind: String, context: Dictionary = {}) -> bool:
	if amount<0.0 or float(a.cash)+0.0001<amount: return false
	if amount==0.0: return true
	a.cash-=amount; a.spent+=amount; a.costs[kind]=float(a.costs.get(kind,0.0))+amount
	teams[int(a.team)].spent+=amount
	ledger.append({"time":time,"actor":int(a.id),"team":int(a.team),"kind":kind,"amount":-amount,"balance":a.cash,"source":"official_s1_vendor" if kind in ["fob","hammer"] else "assumption:purchase_price","context":context.duplicate(true)})
	return true

func _event(team: int, actor: int, text: String, kind: String) -> void:
	var event: Dictionary={"time":time,"team":team,"actor":actor,"text":text,"kind":kind}
	events.append(event); _all_events.append(event)
	if events.size()>300: events.pop_front()

func _record_history() -> void:
	var scores: Array=[]; var cash: Array=[0.0,0.0,0.0]; var presence: Array=[]; var weighted: Array=[]
	for t in teams: scores.append(t.score); presence.append(t.presence); weighted.append(t.weighted_presence)
	for a in actors: cash[int(a.team)]+=float(a.cash)
	history.append({"time":time,"scores":scores,"cash":cash,"presence":presence,"weighted_presence":weighted})

func get_summary() -> Dictionary:
	var balances: Array=[]; var totals: Array=[]; var role_totals: Dictionary={}
	for t in teams:
		var row: Dictionary=t.duplicate(true)
		row["cash"]=0.0; row["initial_cash"]=0.0; row["net"]=float(t.earned)-float(t.spent); row["alive"]=0
		for a in actors:
			if int(a.team)==int(t.id):
				row.cash+=float(a.cash); row.initial_cash+=float(a.initial_cash)
				if _alive(a): row.alive+=1
		totals.append(row)
	for a in actors:
		balances.append(a.cash)
		if not role_totals.has(a.role): role_totals[a.role]={"count":0,"earned":0.0,"spent":0.0,"kills":0,"deaths":0,"revives":0,"deliveries":0,"zone_seconds":0.0}
		var r: Dictionary=role_totals[a.role]
		r.count+=1
		for key in ["earned","spent","kills","deaths","revives","deliveries","zone_seconds"]: r[key]+=a[key]
	return {"seed":seed_value,"scenario":scenario,"time":time,"winner":winner,"finished":finished,"outcome":"winner" if winner>=0 else ("censored" if finished else "running"),"teams":totals,"roles":role_totals,"carry_cash":balances,"transactions":ledger.size(),"assumptions":"Synthetic policies and abstract combat; unverified prices/rewards are tunable. Equipment assumed permanently unlocked; no XP/unlock progression, end-match bonuses or population payout scaling. FOB spawning disabled by default; support resupply is experimental. 6x6 km local crop; not official telemetry or outcome predictions."}

func export_run(directory: String) -> String:
	var path: String=directory.path_join("wardogs_%s_seed%d_%ds" % [scenario,seed_value,int(time)])
	if DirAccess.make_dir_recursive_absolute(path)!=OK: return ""
	_write_json(path.path_join("summary.json"),get_summary())
	_write_json(path.path_join("rules.json"),config)
	_write_json(path.path_join("history.json"),history)
	_write_json(path.path_join("actors.json"),actors)
	_write_json(path.path_join("ledger.json"),ledger)
	_write_json(path.path_join("events.json"),_all_events)
	var csv: FileAccess=FileAccess.open(path.path_join("players.csv"),FileAccess.WRITE)
	if csv:
		csv.store_csv_line(PackedStringArray(["id","name","team","role","cash","initial_cash","earned","spent","net","kills","deaths","revives","delivered_players","zone_seconds"]))
		for a in actors:
			csv.store_csv_line(PackedStringArray([str(a.id),str(a.name),str(a.team),str(a.role),str(a.cash),str(a.initial_cash),str(a.earned),str(a.spent),str(float(a.earned)-float(a.spent)),str(a.kills),str(a.deaths),str(a.revives),str(a.deliveries),str(a.zone_seconds)]))
	return path

func _write_json(path: String, value: Variant) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(_json_safe(value),"  "))

func _json_safe(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Color: return value.to_html()
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[str(key)]=_json_safe(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(_json_safe(item))
		return result
	return value
