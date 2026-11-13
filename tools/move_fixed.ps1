# Moves every "- [x]" item (with its indented continuation lines) out of PROGRESS.md into fixed.md, right below
# fixed.md's first "## Fixed" heading, keeping each item's section name ("Worldgen:", ...) as a prefix.
# Usage: powershell -ExecutionPolicy Bypass -File tools/move_fixed.ps1
$root = Split-Path -Parent $PSScriptRoot
$enc = New-Object System.Text.UTF8Encoding($false)
$pp = Join-Path $root "PROGRESS.md"
$fp = Join-Path $root "fixed.md"
$prog = [System.IO.File]::ReadAllText($pp, [System.Text.Encoding]::UTF8)
$nl = if ($prog.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $prog -split "`r?`n"
$keep = New-Object System.Collections.Generic.List[string]
$moved = New-Object System.Collections.Generic.List[string]
$section = ""
$inx = $false
foreach ($l in $lines) {
	if ($l -match '^[A-Z][A-Za-z /]+:$') { $section = $l.TrimEnd(':'); $inx = $false; $keep.Add($l); continue }
	if ($l -match '^- \[x\]') {
		$inx = $true
		$moved.Add(($l -replace '^- \[x\] ', ("- [x] " + ($(if ($section) { "($section) " } else { "" })))))
		continue
	}
	if ($inx -and $l -match '^\s{4,}\S') { $moved.Add($l); continue }
	$inx = $false
	$keep.Add($l)
}
if ($moved.Count -eq 0) { "nothing to move"; exit 0 }
[System.IO.File]::WriteAllText($pp, ($keep -join $nl), $enc)
$fixed = [System.IO.File]::ReadAllText($fp, [System.Text.Encoding]::UTF8)
$fl = [System.Collections.Generic.List[string]]($fixed -split "`r?`n")
$h = -1
for ($i = 0; $i -lt $fl.Count; $i++) { if ($fl[$i].StartsWith("## Fixed")) { $h = $i; break } }
if ($h -lt 0) { $fl.Insert(0, "## Fixed"); $h = 0 }
$fl.InsertRange($h + 1, $moved)
[System.IO.File]::WriteAllText($fp, ($fl -join $nl), $enc)
"moved $(@($moved | Where-Object { $_ -match '^- \[x\]' }).Count) item(s) to fixed.md"
