# ClassPages: layout preview without the game. Runs the session simulator with CP_RENDER, which redraws every window
# tab, the edit toolbar and the popover from the addon's real layout as HTML, then screenshots each page with Edge
# (headless). Usage: .\tools\preview.ps1 [-Out <folder>]   (default: .\scratch\preview, ignored by git)
param([string]$Out = (Join-Path (Split-Path -Parent $PSScriptRoot) "scratch\preview"))
$root = Split-Path -Parent $PSScriptRoot
$env:Path += ";$env:LOCALAPPDATA\Programs\LuaJIT\bin"
New-Item -ItemType Directory -Force $Out | Out-Null
$env:CP_RENDER = ($Out -replace "\\", "/")
& luajit (Join-Path $root "tools\tests\sim.lua") $root | Select-Object -Last 1
Remove-Item Env:\CP_RENDER
$edge = @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", "C:\Program Files\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { Write-Host "Edge not found: open the HTML files in $Out manually."; exit 0 }
Get-ChildItem $Out -Filter *.html | ForEach-Object {
  $png = [IO.Path]::ChangeExtension($_.FullName, ".png")
  & $edge --headless=new --disable-gpu --hide-scrollbars --window-size=840,690 "--screenshot=$png" ("file:///" + ($_.FullName -replace "\\", "/")) 2>$null | Out-Null
}
Get-ChildItem $Out -Filter *.png | Select-Object -ExpandProperty Name
