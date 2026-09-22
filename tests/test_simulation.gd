extends SceneTree
## Run: godot --headless --path . --script res://tests/test_simulation.gd
const Simulation = preload("res://scripts/simulation.gd")
var checks: Array = []
var failures: int = 0
var started: int = 0

func _initialize() -> void:
	started = Time.get_ticks_msec()
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks.append({"name":label,"passed":condition})
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func new_sim(seed: int = 42, scenario: String = "balanced", overrides: Dictionary = {}) -> RefCounted:
	var sim = Simulation.new()
	sim.setup(seed,scenario,overrides)
	return sim

func park(sim: RefCounted) -> void:
	sim.vehicles.clear()
	for a in sim.actors:
		a.state = "dead"
		a.hp = 0.0
		a.vehicle = -1
		a.respawn_at = 1000000000.0
		a.next_decision = 1000000000.0
		a.invulnerable_until = 1000000000.0

func activate(sim: RefCounted, id: int, pos: Vector2) -> void:
	var a: Dictionary = sim.actors[id]
	a.state = "active"
	a.hp = 100.0
	a.pos = pos
	a.target = pos

func snapshot(sim: RefCounted) -> String:
	return JSON.stringify(sim._json_safe({"summary":sim.get_summary(),"actors":sim.actors,"vehicles":sim.vehicles,"history":sim.history,"ledger":sim.ledger}))

func ledger_valid(sim: RefCounted) -> bool:
	var balances: Dictionary = {}
	var earned: Dictionary = {}
	var spent: Dictionary = {}
	for a in sim.actors:
		balances[int(a.id)] = float(a.initial_cash)
		earned[int(a.id)] = 0.0
		spent[int(a.id)] = 0.0
	for row in sim.ledger:
		var id: int = int(row.actor)
		if not balances.has(id): return false
		var amount: float = float(row.amount)
		balances[id] += amount
		if amount > 0: earned[id] += amount
		else: spent[id] -= amount
		if absf(float(row.balance)-float(balances[id])) > 0.02 or float(row.balance) < -0.001: return false
		if str(row.get("source","")).is_empty(): return false
	for a in sim.actors:
		if absf(float(a.cash)-(float(a.initial_cash)+float(a.earned)-float(a.spent))) > 0.02: return false
		if absf(float(a.cash)-float(balances[int(a.id)])) > 0.02 or float(a.cash) < -0.001: return false
		if absf(float(a.earned)-float(earned[int(a.id)])) > 0.02: return false
		if absf(float(a.spent)-float(spent[int(a.id)])) > 0.02: return false
	for team in sim.teams:
		var total_earned: float = 0.0
		var total_spent: float = 0.0
		for a in sim.actors:
			if int(a.team) == int(team.id):
				total_earned += float(a.earned)
				total_spent += float(a.spent)
		if absf(total_earned-float(team.earned)) > 0.02 or absf(total_spent-float(team.spent)) > 0.02: return false
	return true

func _run() -> void:
	var sim = new_sim()
	var population: Array = [0,0,0]
	for a in sim.actors: population[int(a.team)] += 1
	check(sim.actors.size()==100 and population==[34,33,33],"100 actors allocated 34/33/33")
	check(float(sim.config.starting_cash)==10000.0 and int(sim.config.score_target)==100 and float(sim.config.score_interval)==30.0,"Public base cash, score interval and victory threshold")
	check(not bool(sim.config.enable_fob_respawn),"Unverified FOB spawning disabled by default")
	check(ledger_valid(sim),"Initial equipment and vehicle purchases balance")

	var same_a = new_sim(101)
	var same_b = new_sim(101)
	same_a.step(90.0)
	for i in range(360): same_b.step(0.25)
	check(snapshot(same_a)==snapshot(same_b),"Fixed ticks: same seed remains identical across playback step sizes")
	var different = new_sim(102)
	check(float(different.actors[0].skill)!=float(new_sim(101).actors[0].skill),"Different seed changes sampled actor parameters")

	var scoring = new_sim(42,"balanced",{"walk_speed":0.0})
	park(scoring)
	activate(scoring,0,Vector2(2150,2150))
	scoring.step(29.75)
	check(scoring.teams[0].score==0,"No team point before 30 seconds")
	scoring.step(0.25)
	check(scoring.teams[0].score==1,"Unique presence leader receives one point at 30 seconds")
	activate(scoring,34,Vector2(2200,2150))
	scoring.step(30.0)
	check(scoring.teams[0].score==1 and scoring.teams[1].score==0,"Tied presence receives no point")
	var before_cash: float = float(scoring.actors[0].cash)
	scoring._score_tick()
	check(is_equal_approx(float(scoring.actors[0].cash),before_cash),"Team point calculation does not mint zone cash")
	park(scoring)
	activate(scoring,0,scoring.hot_center)
	activate(scoring,34,Vector2(2150,2150))
	activate(scoring,35,Vector2(2150,2200))
	scoring._score_tick()
	check(scoring.teams[0].weighted_presence==2.0 and scoring.teams[1].weighted_presence==2.0 and scoring.teams[0].score==1,"Hot-zone presence counts twice; weighted tie still receives no point")
	scoring.actors[35].state="downed"
	scoring.actors[35].hp=0.0
	scoring._score_tick()
	check(scoring.teams[0].score==2 and scoring.teams[1].presence==1,"Downed actors do not count toward control")
	scoring.teams[0].score=99
	scoring._score_tick()
	check(scoring.finished and scoring.winner==0 and scoring.teams[0].score==100,"First team to 100 stops the match")
	var final_state: String=snapshot(scoring)
	scoring.step(600.0)
	check(snapshot(scoring)==final_state,"Finished match cannot accrue time, income or scores")

	var clock_test = new_sim(42,"balanced",{"walk_speed":0.0})
	park(clock_test)
	activate(clock_test,0,Vector2(2150,2150))
	clock_test.step(23.75)
	check(float(clock_test.actors[0].income.get("zone",0.0))==0.0,"Zone stipend has not paid before its independent 24-second clock")
	clock_test.step(0.25)
	check(float(clock_test.actors[0].income.get("zone",0.0))==160.0 and clock_test.teams[0].score==0,"24-second zone stipend is independent from 30-second team score")
	check(float(clock_test.actors[0].income.get("enter_zone",0.0))==250.0,"First zone entry pays once")
	clock_test.step(48.0)
	check(float(clock_test.actors[0].income.get("enter_zone",0.0))==250.0,"Standing in zone does not repeatedly pay first-entry reward")

	var medical = new_sim()
	var medic: Dictionary=medical.actors[3]
	var patient: Dictionary=medical.actors[2]
	medic.pos=Vector2(2100,2100); medic.vehicle=-1
	patient.pos=Vector2(2200,2100); patient.vehicle=-1; patient.state="downed"; patient.hp=0.0
	var earned_before: float=medic.earned
	check(not medical._revive(medic,patient) and float(medic.earned)==earned_before,"Remote revive cannot generate money")
	patient.pos=medic.pos+Vector2(10,0)
	check(medical._revive(medic,patient) and patient.state=="active" and float(patient.hp)>0 and medic.revives==1,"Nearby downed teammate is actually revived")
	var after_revive: float=medic.earned
	check(not medical._revive(medic,patient) and float(medic.earned)==after_revive,"Same living patient cannot farm repeated revive rewards")
	patient.state="downed"; patient.hp=0.0; patient.team=1
	check(not medical._revive(medic,patient),"Enemy cannot be revived for friendly reward")
	patient.team=0
	var revive_record: Dictionary=medical.ledger.back()
	check(revive_record.kind=="revive" and revive_record.context.patient==patient.id and float(revive_record.context.distance)<=18.0,"Revive ledger records real patient and range")
	check(ledger_valid(medical),"Medical rewards preserve account and team ledgers")

	var transport = new_sim()
	var v: Dictionary=transport.vehicles[0]
	var driver: Dictionary=transport.actors[int(v.driver)]
	for a in transport.actors:
		if int(a.id)!=int(driver.id): a.state="dead"; a.hp=0.0
	var passenger: Dictionary=transport.actors[2]
	passenger.state="active"; passenger.hp=100.0; passenger.vehicle=-1; passenger.pos=v.pos
	var transport_before: float=driver.earned
	transport._unload_passengers(v)
	check(float(driver.earned)==transport_before,"Empty vehicle earns no delivery money")
	transport._load_passengers(v)
	check(v.passengers==[passenger.id] and passenger.state=="embarked" and passenger.vehicle==v.id,"Boarding consumes a seat occupied by a real teammate")
	transport._unload_passengers(v)
	check(float(driver.earned)==transport_before and driver.deliveries==0,"Stationary unloading earns no delivery money")
	passenger.pos=v.pos
	transport._load_passengers(v)
	v.pos=Vector2(2350,2350); driver.pos=v.pos
	transport._unload_passengers(v)
	check(driver.deliveries==1 and passenger.state=="active" and passenger.vehicle==-1 and float(driver.earned)>transport_before,"Long-distance delivery into control zone pays for an actual disembarked passenger")
	var paid: float=driver.earned
	transport._unload_passengers(v)
	check(float(driver.earned)==paid,"Duplicate unloading cannot duplicate transport reward")
	var transport_record: Dictionary=transport.ledger.back()
	check(transport_record.kind=="transport" and transport_record.context.passengers==[passenger.id] and float(transport_record.context.distance)>=600.0,"Transport ledger retains passenger, pickup, dropoff and displacement")
	check(ledger_valid(transport),"Transport rewards preserve ledger balance")

	var natural = new_sim(42)
	natural.step(600.0)
	check(ledger_valid(natural),"Ten-minute natural run preserves every transaction, player and team balance")
	var causal: bool=true
	var transport_rows: int=0
	var revive_rows: int=0
	for row in natural.ledger:
		if row.kind=="transport":
			transport_rows+=1
			causal=causal and row.context.passengers.size()>0 and float(row.context.distance)>=float(natural.config.minimum_transport_distance) and natural.control_zone.has_point(row.context.dropoff)
		if row.kind=="revive":
			revive_rows+=1
			causal=causal and float(row.context.distance)<=18.0 and row.context.before_state=="downed" and row.context.after_state=="active"
	check(causal and transport_rows>0 and revive_rows>0,"Natural run contains traceable real deliveries and revives")

	var timeout = new_sim(42,"balanced",{"time_limit":60.0})
	park(timeout)
	timeout.step(120.0)
	check(timeout.finished and timeout.winner==-1 and timeout.time==60.0 and timeout.get_summary().outcome=="censored","Time limit truncates an unresolved match without inventing a winner")
	var long_match = new_sim(42,"balanced",{"walk_speed":0.0})
	park(long_match)
	activate(long_match,0,Vector2(2150,2150))
	long_match.step(10800.0)
	check(long_match.finished and long_match.winner==0 and long_match.time==3000.0,"Unopposed full-length match ends exactly at its 100th 30-second point")

	var carried = new_sim()
	var balances: Array=[]
	for a in carried.actors: balances.append(a.cash)
	carried.setup(42,"balanced",{},balances)
	check(float(carried.actors[0].initial_cash)==float(balances[0]),"Explicit carry-over uses previous cash instead of another starter grant")
	var clean = new_sim()
	check(float(clean.actors[0].initial_cash)==10000.0,"Fresh simulations do not read or contaminate carry-over accounts")

	var report: Dictionary={"passed":failures==0,"checks":checks,"failures":failures,"duration_seconds":float(Time.get_ticks_msec()-started)/1000.0,"natural_run_transport_transactions":transport_rows,"natural_run_revive_transactions":revive_rows}
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var output=FileAccess.open("res://artifacts/test_report.json",FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(report,"  "))
	print("RESULT: %d/%d checks passed in %.2fs" % [checks.size()-failures,checks.size(),report.duration_seconds])
	quit(0 if failures==0 else 1)
