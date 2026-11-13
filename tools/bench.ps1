# Export the release build (unless -NoExport) and run an FPS benchmark scenario; prints a compact summary.
# Usage: powershell -File tools/bench.ps1 [-Scen F|A] [-Arch arm64|x86_64] [-NoExport] [-Extra "--fsecs=30"]
param([string]$Scen = "F", [string]$Arch = "arm64", [switch]$NoExport, [string]$Extra = "", [string]$Pre = "", [int]$Cool = 0)
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
$editor = "$env:LOCALAPPDATA\Recraft2Tools\godot-4.7.2-arm64\Godot_v4.7.2-stable_windows_arm64_console.exe"
$preset = if ($Arch -eq "arm64") { "Windows ARM64" } else { "Windows x86_64" }
$exe = "build/windows-$Arch/Recraft2.exe"
if (-not $NoExport) {
	New-Item -ItemType Directory -Force "build/windows-$Arch" | Out-Null
	$p = Start-Process -FilePath $editor -ArgumentList "--headless --path . --export-release `"$preset`" $exe" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\rc_exp_out.txt" -RedirectStandardError "$env:TEMP\rc_exp_err.txt"
	if (-not $p.WaitForExit(900000)) { $p.Kill(); "EXPORT TIMEOUT"; exit 1 }
	$errs = Get-Content "$env:TEMP\rc_exp_err.txt" | Select-String -Pattern "ERROR" | Select-Object -First 5
	if ($errs) { $errs | ForEach-Object { "export: " + $_.Line } }
}
if ($Cool -gt 0) { Start-Sleep -Seconds $Cool }   # let the laptop cool between runs (thermal drift)
$out = Join-Path $env:TEMP "rc_bench_out.txt"
$p = Start-Process -FilePath (Resolve-Path $exe).Path -ArgumentList "$Pre -- --autoplay --gen=java_26_3 --fresh --seed=12345 --fpsbench=$Scen $Extra" -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError (Join-Path $env:TEMP "rc_bench_err.txt")
if (-not $p.WaitForExit(600000)) { $p.Kill(); "RUN TIMEOUT" }
Get-Content $out, (Join-Path $env:TEMP "rc_bench_err.txt") | Select-String -Pattern "SCRIPT ERROR|at: [a-z_]+ \(res" | Select-Object -First 5 | ForEach-Object { $_.Line }
$d = Get-ChildItem "$env:APPDATA\Godot\app_userdata\Recraft 2\perf" -Directory -Filter "fps_*" | Sort-Object LastWriteTime | Select-Object -Last 1
$j = Get-Content (Join-Path $d.FullName "summary.json") -Raw | ConvertFrom-Json
$f = $j.frames
"{0} {1} {2}: avg {3} med {4} 1%low {5} 0.1%low {6} | >16.7ms {7} >33ms {8} max {9} | p95 {10} p99 {11}" -f $Scen, $j.arch, $j.window, $f.fps_avg, $f.fps_median, $f.fps_1pct_low, $f.fps_0_1pct_low, $f.frames_over_16_7ms, $f.frames_over_33ms, $f.ms_max, $f.ms_p95, $f.ms_p99
"render: gpu {0} ms, render cpu {1} ms, draws {2}, prims {3}" -f $j.render.render_gpu, $j.render.render_cpu, [int]$j.render.draw_calls, [int]$j.render.primitives
if ($j.avg_frame_phases_ms) { "phases: " + ($j.avg_frame_phases_ms | ConvertTo-Json -Compress) }
if ($j.streaming) { "stream: gen/s {0} r4inc {1}% r8inc {2}% frozen {3}s wait p90 {4}" -f $j.streaming.generated_per_s, $j.streaming.ring4_incomplete_pct, $j.streaming.ring8_incomplete_pct, $j.streaming.frozen_at_unloaded_s, $j.streaming.ring4_wait_ms_p90 }
if ($j.slow_frames_over_25ms) { "slow>25ms: $($j.slow_frames_over_25ms.count) phases " + ($j.slow_frame_phases_ms | ConvertTo-Json -Compress) }
$m = $j.main_ms_per_frame
"main/frame (only with --trace=1): proc {0} ticks {1} cm {2} (disp {3} commit {4} upload {5}) berender {6}" -f $m.process_total, $m.ticks, $m.chunk_manager, $m.'cm.dispatch', $m.'cm.commit', $m.'cm.  upload', $m.berender
