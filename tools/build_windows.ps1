param(
    [string]$Godot = $env:GODOT_PATH,
    [string]$Output = ''
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $Godot = $command.Source }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    throw 'Set GODOT_PATH or pass -Godot pointing to Godot 4.6.3. Install matching Windows export templates.'
}
if (-not $Output) { $Output = Join-Path $projectPath 'build\WARDOGS_Sandbox.exe' }
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null
& $Godot --headless --path $projectPath --editor --import
if ($LASTEXITCODE -ne 0) { throw 'Godot resource import failed.' }
& $Godot --headless --path $projectPath --export-release 'Windows Desktop' $Output
if ($LASTEXITCODE -ne 0) { throw 'Godot Windows export failed.' }
if (-not (Test-Path -LiteralPath $Output) -or -not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($Output,'.pck')))) {
    throw 'Windows executable or resource pack missing.'
}
Write-Output "Built $Output"
