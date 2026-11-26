param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Output,
    [string]$ApiBaseUrl = 'http://localhost:8000',
    [switch]$PromptForAdminKey
)
$ErrorActionPreference = 'Stop'
$api = [Uri]$ApiBaseUrl
if ($api.Scheme -ne 'https' -and -not ($api.Scheme -eq 'http' -and $api.IsLoopback)) {
    throw 'Use HTTPS for a remote API, or HTTP on localhost for local testing.'
}
if ($PromptForAdminKey) {
    $secret = Read-Host 'Admin key server' -AsSecureString
    $credential = [PSCredential]::new('admin', $secret)
    $key = $credential.GetNetworkCredential().Password
}
else {
    $key = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '.secrets/admin_api_key')).Trim()
}
$requestUrl = $ApiBaseUrl.TrimEnd('/') + '/mp3?url=' + [Uri]::EscapeDataString($Url)
Add-Type -AssemblyName System.Net.Http
$temporaryFile = [System.IO.Path]::GetTempFileName()
try {
    $response = Invoke-WebRequest -Uri $requestUrl -Headers @{ Authorization = "Bearer $key" } -OutFile $temporaryFile -PassThru -UseBasicParsing -TimeoutSec 600
    if (-not $Output) {
        $filename = 'audio.mp3'
        $header = [string]($response.Headers['Content-Disposition'] | Select-Object -First 1)
        if ($header) {
            $disposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::Parse($header)
            if ($disposition.FileNameStar) { $filename = $disposition.FileNameStar }
            elseif ($disposition.FileName) { $filename = $disposition.FileName.Trim('"') }
        }
        $filename = [System.IO.Path]::GetFileName($filename)
        foreach ($invalidCharacter in [System.IO.Path]::GetInvalidFileNameChars()) {
            $filename = $filename.Replace([string]$invalidCharacter, '_')
        }
        if ([string]::IsNullOrWhiteSpace($filename)) { $filename = 'audio.mp3' }
        $Output = Join-Path (Get-Location).Path $filename
        $counter = 1
        while (Test-Path -LiteralPath $Output) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($filename)
            $Output = Join-Path (Get-Location).Path ("$name ($counter).mp3")
            $counter++
        }
    }
    Move-Item -LiteralPath $temporaryFile -Destination $Output
    Write-Host "Saved MP3 to $Output"
}
finally {
    if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile -Force }
}
