# Windows PC 版 v0.1.0

目标平台：Windows x64，OpenGL 3.3 兼容渲染。使用 Godot 4.6.3 Release 模板构建。

## 下载与运行

从本仓库的 `wardogs-sandbox-v0.1.0` Release 下载 `WARDOGS_Sandbox_v0.1.0_Windows_x64.zip`，完整解压后双击 **WARDOGS_Sandbox.exe**。无需安装 Godot，无需联网。

`WARDOGS_Sandbox.exe` 与 `WARDOGS_Sandbox.pck` 必须放在同一目录。发行包还包含操作说明、规则来源和 Godot 许可声明。

程序未进行代码签名。本机构建后的 EXE 被 Windows 应用控制策略阻止，未完成独立 EXE 直接启动验收。已通过开发运行时的界面测试，并使用已安装的 Godot 4.6.3 成功加载实际导出的 PCK，验证了中文界面、100 人模拟、选人、缩放、跟随与报告导出。启用严格应用控制的设备可能需要受信任的签名版本或管理员批准。

## 主要操作

- 空格：暂停或继续；速度菜单：0.25 / 1 / 4 / 10 / 30 / 100 倍。
- 鼠标滚轮：缩放；右键或中键拖动 / WASD：平移；Home：全图。
- 左键点击单位 / Tab / 玩家下拉框：选人；F：跟随。
- 右侧查看玩家行为、战绩、载具与个人收益明细。
- 底部走势菜单切换团队得分、现金余额和区域人数。
- 可打开全员净收益排行、修改场景与参数、导出中文复盘报告。

## 数据与报告

报告默认保存到 `%APPDATA%\Godot\app_userdata\WARDOGS 战局推演实验室\reports`，点击“查看最近报告”可打开实际目录。

发行版界面可修改场景、随机种子、初始账户与行为奖励倍率。完整规则配置打包在 PCK 内；修改 `data/rules.json` 后需要重新构建。该模型区分官方明确规则、社区观测与模拟假设，不能作为真人游戏胜率预测。资料基线日期为 2026-09-18。

## 从源码构建

安装 Godot 4.6.3 及匹配的 Windows 导出模板，然后在工程目录执行：

```powershell
.\tools\build_windows.ps1 -Godot "C:\Tools\Godot\Godot_v4.6.3-stable_win64_console.exe"
```

默认输出 `build/WARDOGS_Sandbox.exe` 与同名 PCK。可用 `-Output` 指定 EXE 的绝对路径。

模拟测试：`tools/run.ps1 -Mode Test`。界面验收：`godot --path . -- --ui-test`。

已有逻辑验证为 37/37 项通过，批量验收包含 9 局完整推演。当前发布中额外核验了实际导出资源包的界面与报告功能。
