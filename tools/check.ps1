# Refreshes the Godot class cache (headless editor scan) then compile-checks every script.
# Usage: powershell -ExecutionPolicy Bypass -File tools/check.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& powershell -ExecutionPolicy Bypass -File "$here\gd.ps1" -A "--headless --path . --editor --quit" -Filter "Parse Error|SCRIPT ERROR" | Where-Object { $_ -notmatch "Identifier not found: MCNoise" } | Select-Object -First 10
& powershell -ExecutionPolicy Bypass -File "$here\gd.ps1" -A "--headless --path . -- --check" -Filter "FAIL|CHECKED|Parse Error|SCRIPT ERROR|at: GDScript" | Select-Object -First 60
