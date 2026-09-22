param(
    [ValidateSet('Play', 'Editor', 'Test', 'Batch')][string]$Mode = 'Play',
    [string]$Godot = $env:GODOT_PATH,
    [int]$Seeds = 3,
    [int]$StartSeed = 42,
    [double]$MaxSeconds = 10800,
    [string]$Output = 'res://artifacts/batch',
    [string]$Config = ''
)
$ErrorActionPreference = 'Stop'
$ProjectPath = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $BundledCandidate = 'D:\software\Godot\Godot_v4.6.3-stable_win64_console.exe'
    if (Test-Path -LiteralPath $BundledCandidate) { $Godot = $BundledCandidate }
    else {
        $GodotCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($GodotCommand) { $Godot = $GodotCommand.Source }
    }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    throw '未找到 Godot 4.6。请设置 GODOT_PATH，或使用 -Godot C:\path\godot.exe。'
}
$LaunchArguments = @('--path', $ProjectPath)
switch ($Mode) {
    'Editor' { $LaunchArguments += '--editor' }
    'Test' { $LaunchArguments += @('--headless', '--script', 'res://tests/test_simulation.gd') }
    'Batch' {
        $LaunchArguments += @('--headless', '--script', 'res://tools/batch.gd', '--', "--seeds=$Seeds", "--start-seed=$StartSeed", "--max-seconds=$MaxSeconds", "--output=$Output")
        if ($Config) { $LaunchArguments += "--config=$Config" }
    }
}
& $Godot @LaunchArguments
exit $LASTEXITCODE
