# ClassPages: syntax check, lint and headless tests. Run from the repo root: .\tools\check.ps1
# Toolchain: LuaJIT (Lua 5.1 compatible, winget DEVCOM.LuaJIT) and the standalone luacheck.exe
# (https://github.com/lunarmodules/luacheck/releases) in %LOCALAPPDATA%\Programs\luacheck.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$addon = Join-Path $root "ClassPages"
$failed = $false
$ran = 0

# Make the default install locations available even in a shell started before the PATH change.
$env:Path += ";$env:LOCALAPPDATA\Programs\LuaJIT\bin;$env:LOCALAPPDATA\Programs\luacheck"

# Lua interpreter: prefer real 5.1, then LuaJIT (5.1 semantics). Lua 5.4 would accept syntax WoW rejects.
$lua = $null
foreach ($name in "lua5.1", "luajit", "lua51") {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { $lua = $cmd.Source; break }
}

if ($lua) {
  $bad = 0
  Get-ChildItem -Path $addon -Recurse -Filter *.lua | ForEach-Object {
    $path = $_.FullName -replace "\\", "/"
    & $lua -e "local f, e = loadfile([[$path]]); if not f then io.stderr:write(e, '\n'); os.exit(1) end"
    if ($LASTEXITCODE -ne 0) { Write-Host "SYNTAX: $($_.FullName)"; $bad++ }
  }
  $count = (Get-ChildItem -Path $addon -Recurse -Filter *.lua).Count
  Write-Host "syntax ($(Split-Path -Leaf $lua)): $count files, $bad errors"
  if ($bad -gt 0) { $failed = $true }
  $ran++
} else {
  Write-Host "no Lua 5.1 interpreter found: winget install --id DEVCOM.LuaJIT"
}

$luacheck = Get-Command luacheck -ErrorAction SilentlyContinue
if ($luacheck) {
  & $luacheck.Source $addon --config (Join-Path $root ".luacheckrc") --no-color
  if ($LASTEXITCODE -ne 0) { $failed = $true }
  $ran++
} else {
  Write-Host "luacheck not found: download luacheck.exe from https://github.com/lunarmodules/luacheck/releases"
}

if ($lua) {
  & $lua (Join-Path $root "tools\tests\run.lua") $root
  if ($LASTEXITCODE -ne 0) { $failed = $true }
  $ran++
}

# whole-addon session simulation (every TOC file, simulated client, two template modes)
if ($lua) {
  & $lua (Join-Path $root "tools\tests\sim.lua") $root
  if ($LASTEXITCODE -ne 0) { $failed = $true }
  $ran++
}

if ($ran -eq 0) { Write-Host "CHECK FAILED: no tool available"; exit 2 }
if ($failed) { Write-Host "CHECK FAILED"; exit 1 } else { Write-Host "CHECK OK ($ran steps)"; exit 0 }
