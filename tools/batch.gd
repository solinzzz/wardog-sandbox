extends SceneTree
## Paired-seed experiments; every run starts from new accounts.
const Simulation = preload("res://scripts/simulation.gd")
var seeds: int = 3
var first_seed: int = 42
var max_seconds: float = 10800.0
var output_dir: String = "res://artifacts/batch"
var scenarios: Array = ["balanced","profit","coordinated"]
var overrides: Dictionary = {}
var failed: bool = false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair: PackedStringArray=arg.split("=",true,1)
		if pair.size()!=2: continue
		match pair[0]:
			"--seeds": seeds=clampi(int(pair[1]),1,1000)
			"--start-seed": first_seed=int(pair[1])
			"--max-seconds": max_seconds=maxf(0.25,float(pair[1]))
			"--output": output_dir=pair[1]
			"--scenarios": scenarios=Array(pair[1].split(",",false))
			"--config":
				var config_value: Variant=JSON.parse_string(FileAccess.get_file_as_string(pair[1]))
				if config_value is Dictionary: overrides=config_value
				else: push_error("Invalid JSON override file"); quit(2); return
	for scenario in scenarios:
		if not str(scenario) in ["balanced","profit","coordinated"]:
			push_error("Unknown scenario: "+str(scenario)); quit(2); return
	call_deferred("_run")

func _csv(path: String, rows: Array) -> void:
	var file=FileAccess.open(output_dir.path_join(path),FileAccess.WRITE)
	if not file: failed=true; push_error("Cannot write "+path); return
	for row in rows:
		var columns=PackedStringArray()
		for value in row: columns.append(str(value))
		file.store_csv_line(columns)

func _json(path: String, value: Variant) -> void:
	var file=FileAccess.open(output_dir.path_join(path),FileAccess.WRITE)
	if not file: failed=true; push_error("Cannot write "+path); return
	file.store_string(JSON.stringify(value,"  "))

func _run() -> void:
	var started: int=Time.get_ticks_msec()
	if DirAccess.make_dir_recursive_absolute(output_dir)!=OK:
		push_error("Cannot create output directory"); quit(2); return
	var runs: Array=[]
	var csv: Array=[["scenario","seed","outcome","winner_team","seconds","red_score","blue_score","green_score","earned","spent","net","kills","deaths","revives","delivered_players","transactions"]]
	var roles: Array=[["scenario","seed","role","count","earned_per_actor","spent_per_actor","net_per_actor","kills_per_actor","deaths_per_actor","revives_per_actor","delivered_players_per_actor","zone_seconds_per_actor"]]
	var aggregates: Dictionary={}
	var first_config: Dictionary={}
	for seed_index in range(seeds):
		for scenario in scenarios:
			var sim=Simulation.new()
			sim.setup(first_seed+seed_index,str(scenario),overrides)
			if first_config.is_empty(): first_config=sim.config.duplicate(true)
			while not sim.finished and sim.time+0.0001<max_seconds:
				sim.step(minf(10.0,max_seconds-float(sim.time)))
			var result: Dictionary=sim.get_summary()
			var resolved: bool=sim.finished and int(sim.winner)>=0
			var outcome: String="winner" if resolved else "censored"
			result["outcome"]=outcome
			result["censor_reason"]="" if resolved else ("model_time_limit" if sim.finished else "batch_time_limit")
			result["observed_seconds"]=sim.time
			result["ledger_balance_ok"]=true
			result.erase("carry_cash")
			var total_earned: float=0.0
			var total_spent: float=0.0
			var kills: int=0
			var deaths: int=0
			var revives: int=0
			var deliveries: int=0
			for a in sim.actors:
				total_earned+=float(a.earned); total_spent+=float(a.spent)
				kills+=int(a.kills); deaths+=int(a.deaths); revives+=int(a.revives); deliveries+=int(a.deliveries)
				if float(a.cash)<-0.001 or absf(float(a.cash)-(float(a.initial_cash)+float(a.earned)-float(a.spent)))>0.02:
					result.ledger_balance_ok=false; failed=true
			csv.append([scenario,sim.seed_value,outcome,sim.winner,sim.time,sim.teams[0].score,sim.teams[1].score,sim.teams[2].score,total_earned,total_spent,total_earned-total_spent,kills,deaths,revives,deliveries,sim.ledger.size()])
			for role in result.roles:
				var r: Dictionary=result.roles[role]
				var n: float=float(r.count)
				roles.append([scenario,sim.seed_value,role,r.count,float(r.earned)/n,float(r.spent)/n,(float(r.earned)-float(r.spent))/n,float(r.kills)/n,float(r.deaths)/n,float(r.revives)/n,float(r.deliveries)/n,float(r.zone_seconds)/n])
			if not aggregates.has(scenario): aggregates[scenario]={"runs":0,"resolved":0,"censored":0,"wins":[0,0,0],"sum_seconds":0.0,"sum_net":0.0}
			var group: Dictionary=aggregates[scenario]
			group.runs+=1; group.sum_seconds+=float(sim.time); group.sum_net+=total_earned-total_spent
			if resolved: group.resolved+=1; group.wins[int(sim.winner)]+=1
			else: group.censored+=1
			runs.append(result)
			print("RUN %d/%d %s seed=%d %s winner=%d t=%.0f scores=%s ledger=%d" % [runs.size(),seeds*scenarios.size(),scenario,sim.seed_value,outcome,sim.winner,sim.time,str([sim.teams[0].score,sim.teams[1].score,sim.teams[2].score]),sim.ledger.size()])
			# Compact incremental summaries survive a stopped batch without huge per-run ledgers.
			_json("runs.json",runs)
			_csv("runs.csv",csv)
			_csv("roles.csv",roles)
			sim=null
	var metadata: Dictionary={"seeds":seeds,"first_seed":first_seed,"scenarios":scenarios,"paired_seeds":true,"independent_fresh_accounts":true,"max_seconds":max_seconds,"overrides":overrides,"wall_seconds":float(Time.get_ticks_msec()-started)/1000.0,"note":"Synthetic policies, abstract combat and partially unverified economy. Observed win counts are model outcomes, not predictions of real player win rates. Censored matches are not victories or draws."}
	_json("metadata.json",metadata)
	_json("rules_snapshot.json",first_config)
	_json("aggregate.json",aggregates)
	var report: String="# 配对种子批量推演\n\n本次 "+str(runs.size())+" 局；每场从独立初始账户开始。相同种子横向比较 balanced / profit / coordinated；每个场景内的角色配置会改变随机数消费，因此这是可复现的场景对照，不是严格共同随机数实验。\n\n| 场景 | 场次 | 已决 | 截尾未决 | 红/蓝/绿胜场 | 平均观察秒数 | 平均全体净收益 |\n|---|---:|---:|---:|---|---:|---:|\n"
	for scenario in aggregates:
		var g: Dictionary=aggregates[scenario]
		report+="| %s | %d | %d | %d | %s | %.0f | %.0f |\n" % [scenario,g.runs,g.resolved,g.censored,str(g.wins),float(g.sum_seconds)/float(g.runs),float(g.sum_net)/float(g.runs)]
	report+="\n角色均值和各场观察长度见 roles.csv；未决局收入尚未完成，不宜直接与完整局总收入比较。所有结果只描述当前策略与参数模型，样本数较小，不代表真实游戏胜率。官方、社区观察与假设参数见 rules_snapshot.json 和 ../../docs/RULE_SOURCES.md。完整逐笔日志应通过交互界面按需导出，本批量仅保留紧凑汇总。\n"
	var file=FileAccess.open(output_dir.path_join("REPORT.md"),FileAccess.WRITE)
	if file: file.store_string(report)
	else: failed=true
	print("BATCH COMPLETE: "+ProjectSettings.globalize_path(output_dir)+" wall_seconds="+str(metadata.wall_seconds))
	quit(1 if failed else 0)
