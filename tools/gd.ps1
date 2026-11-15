# Runs the installed Godot 4.7.2 with given args, capturing output; prints only error/warning lines + tail.
# Usage: powershell -File tools/gd.ps1 -A "--headless --path . -- --check" [-Tail 20] [-Filter regex]
param([string]$A = "--headless --path . -- --check", [string]$Filter = "ERROR|SCRIPT ERROR|Parse Error|WARNING|FAIL|PASS|CHECKED|RESULT|BENCH|at: ", [int]$Tail = 0, [int]$Timeout = 600)
$g = $env:GODOT
if (-not $g) { $g = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" }
$out = Join-Path $env:TEMP "rc_gd_out_$PID.txt"   # per invocation: parallel runs must not share the capture files
$err = Join-Path $env:TEMP "rc_gd_err_$PID.txt"
$p = Start-Process -FilePath $g -ArgumentList $A -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $p.WaitForExit($Timeout * 1000)) { $p.Kill(); "TIMEOUT after $Timeout s" }
$lines = @(Get-Content $out, $err -ErrorAction SilentlyContinue)
$lines | Where-Object { $_ -match $Filter } | Select-Object -First 80
if ($Tail -gt 0) { "---- tail"; $lines | Select-Object -Last $Tail }
"exit=$($p.ExitCode)"
Remove-Item $out, $err -ErrorAction SilentlyContinue
