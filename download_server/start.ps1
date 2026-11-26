param([switch]$RotateAdminKey)
$ErrorActionPreference = 'Stop'
$secretDirectory = Join-Path $PSScriptRoot '.secrets'
$keyPath = Join-Path $secretDirectory 'admin_api_key'
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
if ($RotateAdminKey -or -not (Test-Path -LiteralPath $keyPath)) {
    $keyBytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($keyBytes) } finally { $rng.Dispose() }
    $key = [Convert]::ToBase64String($keyBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    [System.IO.File]::WriteAllText($keyPath, $key, [System.Text.Encoding]::ASCII)
    Write-Host 'Created a new admin key in .secrets/admin_api_key (not printed).'
}
& docker compose --project-directory $PSScriptRoot -f (Join-Path $PSScriptRoot 'compose.yaml') up --build -d --force-recreate
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed.' }
