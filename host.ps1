# Hosts a GameSync room that friends can join over the internet.
# Starts the server, opens a free Cloudflare quick tunnel to it,
# and copies an invite code to your clipboard.

Set-Location $PSScriptRoot
$port = 8787

function Stop-With($msg) {
    Write-Host ""
    Write-Host $msg -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Stop-With "Node.js isn't installed. Get the LTS version from nodejs.org, then run HOST.bat again."
}

if (-not (Test-Path "server\node_modules\ws")) {
    Write-Host "Installing server parts (one time)..."
    npm install --prefix server --silent
}

if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    Write-Host "Installing cloudflared, Cloudflare's free tunnel tool (one time)..."
    winget install --id Cloudflare.cloudflared -e --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
        Stop-With "cloudflared didn't install. Close this window, open a new one and run HOST.bat again."
    }
}

$log = Join-Path $env:TEMP "gamesync-tunnel.log"
Remove-Item $log -ErrorAction SilentlyContinue

Write-Host "Starting server..."
$server = Start-Process node -ArgumentList "server\server.js" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 1

Write-Host "Opening tunnel (can take ~10 seconds)..."
$tunnel = Start-Process cloudflared -ArgumentList "tunnel --no-autoupdate --url http://localhost:$port" -PassThru -WindowStyle Hidden -RedirectStandardError $log

$url = $null
for ($i = 0; $i -lt 45 -and -not $url; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $log) {
        $m = Select-String -Path $log -Pattern 'https://([a-z0-9-]+)\.trycloudflare\.com' -AllMatches |
            ForEach-Object { $_.Matches } | Where-Object { $_.Groups[1].Value -ne "api" } | Select-Object -First 1
        if ($m) { $url = $m.Value }
    }
}

if (-not $url) {
    Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
    Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue
    Stop-With "Couldn't open the tunnel. Check your internet and try again. Details: $log"
}

$room = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
$invite = ($url -replace '^https://', '') + "/" + $room
Set-Clipboard -Value $invite

Write-Host ""
Write-Host "  Invite code (copied):" -ForegroundColor Green
Write-Host ""
Write-Host "    $invite" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Paste it in the GameSync panel in Godot, type your name, press Join."
Write-Host "  2. Send the same code to your friends."
Write-Host "  Only share it with people you trust: they can change your project's files."
Write-Host ""
Read-Host "Keep this window open while you work. Press Enter to stop hosting"

Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue
Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
