# ClassPages: builds the upload zip without the BigWigs packager (for a manual CurseForge / Wago upload).
# Runs the checks first, copies the addon folder, writes the version into the TOC and zips it with a single
# root folder "ClassPages". Usage: .\tools\package.ps1 -Version 1.0.0 [-SkipCheck]
# Output: .\.release\ClassPages-<version>.zip (ignored by git)
param([Parameter(Mandatory = $true)][string]$Version, [switch]$SkipCheck)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $SkipCheck) {
  & powershell -NoProfile -File (Join-Path $PSScriptRoot "check.ps1") | Select-Object -Last 3
  if ($LASTEXITCODE -ne 0) { Write-Host "PACKAGE FAILED: checks are not green"; exit 1 }
}
$release = Join-Path $root ".release"
$stage = Join-Path $release "ClassPages"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $release | Out-Null
Copy-Item -Recurse (Join-Path $root "ClassPages") $stage
Copy-Item (Join-Path $root "LICENSE") (Join-Path $stage "LICENSE.txt")
$toc = Join-Path $stage "ClassPages.toc"
$text = [IO.File]::ReadAllText($toc)
if ($text -notmatch "@project-version@") { Write-Host "PACKAGE FAILED: version token missing in the TOC"; exit 1 }
[IO.File]::WriteAllText($toc, $text.Replace("@project-version@", $Version), (New-Object Text.UTF8Encoding($false)))
$zip = Join-Path $release "ClassPages-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
Remove-Item -Recurse -Force $stage
$size = [math]::Round((Get-Item $zip).Length / 1KB)
Write-Host "PACKAGE OK: $zip ($size KB)"
