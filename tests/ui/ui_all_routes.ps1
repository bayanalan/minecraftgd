# UI smoke test: opens every out-of-game --ui route in the exported build, fails on SCRIPT ERROR or a missing
# screenshot. Usage: powershell -File tests/ui/ui_all_routes.ps1 [-Exe builds/windows-arm64/Recraft2.exe]
param([string]$Exe = "builds/windows-arm64/Recraft2.exe")
$routes = @("title", "world_list", "edit_world", "delete_world", "create_world", "create_world_world", "create_world_more",
  "game_rules", "flat", "presets", "single_biome", "options", "options_video", "options_sounds", "options_controls",
  "options_keybinds", "options_language", "options_packs", "options_access", "options_online", "multiplayer")
$shots = Join-Path $env:APPDATA "Godot\app_userdata\Recraft 2\autoplay"
$fail = 0
foreach ($r in $routes) {
  $before = Get-Date
  $p = Start-Process -FilePath (Resolve-Path $Exe).Path -ArgumentList "-- --ui=$r" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ui_t_out.txt" -RedirectStandardError "$env:TEMP\ui_t_err.txt"
  if (-not $p.WaitForExit(120000)) { $p.Kill(); Write-Output "FAIL $r timeout"; $fail++; continue }
  $errs = @(Get-Content "$env:TEMP\ui_t_err.txt" | Select-String -Pattern "SCRIPT ERROR")
  $shot = Get-ChildItem $shots -Filter "ui_*.png" | Where-Object { $_.LastWriteTime -gt $before } | Select-Object -First 1
  if ($errs.Count -gt 0) { Write-Output "FAIL $r : $($errs[0].Line)"; $fail++ }
  elseif ($shot -eq $null) { Write-Output "FAIL $r : no screenshot"; $fail++ }
  else { Write-Output "ok   $r" }
}
Write-Output "UI ROUTES: $($routes.Count - $fail)/$($routes.Count) passed"
exit $fail