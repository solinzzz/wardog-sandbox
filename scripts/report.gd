extends RefCounted

static func make(sim) -> String:
	var summary: Dictionary = sim.get_summary()
	var minutes := float(sim.time) / 60.0
	var result := "进行中快照"
	if sim.finished:
		result = "%s 获胜" % sim.teams[sim.winner].name if sim.winner >= 0 else "达到模型时限：未决 / 截尾"
	var lines := PackedStringArray([
		"WARDOGS 战局推演报告",
		"种子 %d | 场景 %s | 游戏时间 %.1f 分钟 | %s" % [sim.seed_value,sim.scenario,minutes,result],
		"",
		"本报告是给定规则与行为假设下的模拟输出，不是实际服务器统计或胜率预测。",
		"",
		"一、三方战局"
	])
	for team in summary.teams:
		var count := 0
		var zone_seconds := 0.0
		for a in sim.actors:
			if int(a.team) == int(team.id):
				count += 1
				zone_seconds += float(a.zone_seconds)
		var participation := zone_seconds / maxf(1.0,sim.time * count) * 100.0
		lines.append("%s：%d 分；现金 $%.0f；净变化 $%.0f；占区参与时间 %.1f%%；击杀 %d / 死亡 %d / 复活 %d / 运送 %d 人。" % [team.name,team.score,team.cash,team.net,participation,team.kills,team.deaths,team.revives,team.deliveries])
	lines.append("")
	lines.append("二、不同玩家倾向的赚钱与贡献（按人均净收益排序）")
	var rows := []
	for role in summary.roles:
		var row: Dictionary = summary.roles[role].duplicate()
		row["role"] = role
		row["mean_net"] = (row.earned-row.spent)/maxf(1,row.count)
		rows.append(row)
	rows.sort_custom(func(a,b): return a.mean_net > b.mean_net)
	for row in rows:
		var rate: float = float(row.mean_net) / maxf(minutes / 60.0, 0.001)
		lines.append("%s（%d 人）：人均净收益 $%.0f，折算 $%.0f / 小时；总收入 $%.0f，支出 $%.0f；占区 %.1f 玩家分钟；救援 %d 次，送达 %d 人。" % [sim.role_name(row.role),row.count,row.mean_net,rate,row.earned,row.spent,row.zone_seconds/60.0,row.revives,row.deliveries])
	lines.append("短时快照的小时收益只作标准化比较，不能视为长局稳定收益；角色数量与行为分布影响总量。")
	lines.append("")
	lines.append("三、经济收支")
	var income := {}
	var cost := {}
	var names := {"kill":"击杀","zone":"占区驻留","zone_entry":"首次进入控制区","enter_zone":"首次进入控制区","revive":"复活队友","heal":"治疗","transport":"运送真实乘员","supply":"补给交付","recon":"侦察标记","vehicle_destroyed":"摧毁载具","loadout":"每命装备","vehicle":"载具购买","hammer":"工程工具","fob":"FOB购买","supplies":"补给采购"}
	for a in sim.actors:
		for key in a.income:
			income[key] = float(income.get(key,0.0)) + float(a.income[key])
		for key in a.costs:
			cost[key] = float(cost.get(key,0.0)) + float(a.costs[key])
	for key in income:
		lines.append("收入 / %s：$%.0f" % [names.get(key,key),income[key]])
	for key in cost:
		lines.append("支出 / %s：$%.0f" % [names.get(key,key),cost[key]])
	lines.append("装备或载具购买时已经扣款；阵亡/损毁不再次重复扣除购买成本。现金守恒：期末 = 期初 + 收入 − 支出。")
	lines.append("")
	lines.append("四、解读与复现")
	lines.append("得分只取决于计分时区域内的有效人数；个人收入、击杀数与团队胜利并非同一个指标。请结合占区时间、救援、乘员交付和逐笔账本解释差异。")
	lines.append("使用相同随机种子比较场景；一次胜负只是一条样本。批量工具记录未决局，不能把截尾领先者算作获胜。")
	lines.append("rules.json 保存本局实际参数；players.csv 是全员账本汇总；ledger.json 包含每笔交易及乘客/救援对象；history.json 为时间序列。")
	lines.append("来源见工程 docs/RULE_SOURCES.md。官方值、社区观测、历史载具数据与模型假设必须分别解读；本模型未实现全部武器、弹道、地形遮挡、破坏与等级解锁；局内净收益未计局末排名奖金、永久解锁费及服务器人数收入缩放。")
	return "\n".join(lines)
