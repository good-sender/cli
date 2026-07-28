# Installs the GoodSender CLI binary for Windows from the latest
# good-sender/mcp release (fat binaries.zip).
$ErrorActionPreference = "Stop"

$Repo = "good-sender/mcp"
$Bin = "goodsender.exe"
$InstallDir = if ($env:GOODSENDER_INSTALL_DIR) { $env:GOODSENDER_INSTALL_DIR } else {
  Join-Path $env:LOCALAPPDATA "goodsender\bin"
}

$arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
  "Arm64" { "arm64" }
  "X64" { "amd64" }
  default { throw "unsupported arch: $_" }
}

$asset = "goodsender-windows-$arch.exe"
$url = "https://github.com/$Repo/releases/latest/download/binaries.zip"
$dest = Join-Path $InstallDir $Bin
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("goodsender-install-" + [guid]::NewGuid().ToString())

Write-Host "Downloading binaries.zip ($asset)..."
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $zip = Join-Path $tmp "binaries.zip"
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $src = Join-Path $tmp $asset
  if (-not (Test-Path $src)) { throw "asset not found in binaries.zip: $asset" }
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Move-Item -Force $src $dest
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $InstallDir) {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
  $env:Path = "$env:Path;$InstallDir"
  Write-Host "Added $InstallDir to your user PATH (restart the terminal if needed)."
}

Write-Host "Installed $Bin to $dest"
