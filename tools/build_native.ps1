# Builds native/bin/recraft_native.<arch>.dll with the installed Visual Studio 2022 MSVC.
# Usage: powershell -File tools/build_native.ps1 [-Arch x86_64|arm64|all] [-Debug] [-OutDir <folder>]
# -OutDir writes the DLL elsewhere (e.g. when native\bin\ is locked by a running Godot that loaded it).
param([string]$Arch = "all", [switch]$Debug, [string]$OutDir = "")
$vs = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $vs)) { "vcvarsall.bat not found"; exit 1 }
$root = Split-Path -Parent $PSScriptRoot
$targets = @()
if ($Arch -eq "all" -or $Arch -eq "x86_64") { $targets += ,@("x86_64", "arm64_amd64") }
if ($Arch -eq "all" -or $Arch -eq "arm64") { $targets += ,@("arm64", "arm64") }
$opt = if ($Debug) { "/Od /Zi" } else { "/O2 /Oi /GL /fp:precise" }
$link = if ($Debug) { "/DEBUG" } else { "/LTCG /OPT:REF /OPT:ICF" }
$ok = $true
foreach ($t in $targets) {
	$name = $t[0]; $va = $t[1]
	$obj = Join-Path $root "native\obj\$name"
	New-Item -ItemType Directory -Force $obj | Out-Null
	$outDir = if ($OutDir -ne "") { $OutDir } else { Join-Path $root "native\bin" }
	New-Item -ItemType Directory -Force $outDir | Out-Null
	$out = Join-Path $outDir "recraft_native.$name.dll"
	$cmd = "call `"$vs`" $va >nul && cd /d `"$root`" && cl /nologo /std:c++17 /EHsc /MD /W3 /wd4244 /wd4267 /wd4305 $opt /Inative\include native\src\*.cpp /LD /Fo`"$obj\\`" /Fe`"$out`" /link $link"
	$log = Join-Path $obj "build.log"
	cmd /c $cmd > $log 2>&1
	$code = $LASTEXITCODE
	$errs = Get-Content $log | Where-Object { $_ -match "error|warning C4[0-9]{3}|fatal" } | Select-Object -First 30
	if ($code -ne 0 -or -not (Test-Path $out)) { "BUILD FAILED $name (exit $code)"; $errs; $ok = $false } else { "BUILT $name -> $out ($((Get-Item $out).Length) bytes)"; $errs }
}
if (-not $ok) { exit 1 }
