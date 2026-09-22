param([switch]$Verify)
$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
$candidates = @(
    'D:\software\Godot\Godot_v4.6.3-stable_win64_console.exe',
    "$env:USERPROFILE\Downloads\godot.windows.editor.x86_64.exe"
)
$discovered = Get-Command godot.exe,godot4.exe,Godot_v4.6.3-stable_win64_console.exe -ErrorAction SilentlyContinue
if ($discovered) { $candidates += $discovered.Source }
$engine = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $engine) {
    Write-Host 'Godot 4.6 was not found. Open project.godot in Godot, or add Godot to PATH.'
    exit 1
}
if ($Verify) {
    & $engine --headless --path $projectPath --editor --import
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine --headless --path $projectPath --check-only --script res://scripts/main.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine --headless --path $projectPath --script res://tests/test_simulation.gd
    exit $LASTEXITCODE
}
& $engine --path $projectPath
