# Function-level GDScript profile of a game run (self/total time per function) without the editor.
# Usage: powershell -File tools/profile.ps1 -A "--autoplay --gen=java_26_3 --fresh --seed=12345 --fpsbench=A" [-Out file.json]
# Uses $env:GODOT (default: Steam x86-64 build). Starts tools/profiler_server.gd, launches the game with --remote-debug.
param([string]$A = "--autoplay --gen=java_26_3 --fresh --seed=12345 --fpsbench=A", [string]$Out = "", [int]$Timeout = 600, [int]$Port = 6007)
$g = $env:GODOT
if (-not $g) { $g = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" }
if (-not $Out) { $Out = Join-Path $env:TEMP "rc_profile.json" }
$raw = Join-Path $env:TEMP "rc_profile_raw.txt"
Remove-Item $Out, $raw -ErrorAction SilentlyContinue
$so = Join-Path $env:TEMP "rc_prof_srv.txt"
$srv = Start-Process -FilePath $g -ArgumentList "--headless --path . --script res://tools/profiler_server.gd -- --port=$Port --out=`"$Out`" --raw=`"$raw`"" -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError (Join-Path $env:TEMP "rc_prof_srv_err.txt")
Start-Sleep -Seconds 3
& powershell -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "gd.ps1") -A "--path . --remote-debug tcp://127.0.0.1:$Port -- $A" -Filter "\[fps\]|SCRIPT ERROR|at: [a-z_]+ \(res" -Timeout $Timeout
if (-not $srv.WaitForExit(20000)) { $srv.Kill(); "profiler server killed" }
Get-Content $so | Select-Object -Last 5
"profile: $Out"
