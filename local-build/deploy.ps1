# Installs the output of build.ps1 into the File Converter install folder (asks for administrator rights once).
#
# Copies FileConverter.exe, Settings.default.xml and the NetOffice DLLs (the official 2.2 installer omits them, which
# breaks Word/Excel/PowerPoint conversions). Every replaced file is backed up to ..\backups first.
# Then it refreshes the built-in presets in your user settings, as the official installer does after an install:
# custom presets are kept, edits made to built-in presets are reset. Use -SkipPresetRefresh to keep them.
#
# Usage:  .\deploy.ps1  [-SkipPresetRefresh]
param(
    [string]$InstallDir = "C:\Program Files\File Converter",
    [switch]$SkipPresetRefresh,
    # Internal: set when the script re-launches itself with administrator rights.
    [string]$ElevatedLog
)
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$output = Join-Path $env:TEMP "FileConverter-local-build\FileConverter\bin\Release\net48"
$files = [ordered]@{
    (Join-Path $output "FileConverter.exe") = "FileConverter.exe"
    (Join-Path $repo "Application\FileConverter\Settings.default.xml") = "Settings.default.xml"
    (Join-Path $output "NetOffice.dll") = "NetOffice.dll"
    (Join-Path $output "OfficeApi.dll") = "OfficeApi.dll"
    (Join-Path $output "VBIDEApi.dll") = "VBIDEApi.dll"
    (Join-Path $output "ExcelApi.dll") = "ExcelApi.dll"
    (Join-Path $output "WordApi.dll") = "WordApi.dll"
    (Join-Path $output "PowerPointApi.dll") = "PowerPointApi.dll"
}

if ($ElevatedLog) {
    # Administrator part: back up, copy, verify. Output goes to the log because this window closes on exit.
    function Log([string]$message) { Add-Content -LiteralPath $ElevatedLog -Value $message }
    try {
        $backup = Join-Path $repo ("backups\FileConverter_install_before_deploy_" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        foreach ($name in $files.Values) {
            $target = Join-Path $InstallDir $name
            if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $backup $name) }
        }
        Log "Backed up the replaced files to $backup"
        foreach ($entry in $files.GetEnumerator()) {
            $target = Join-Path $InstallDir $entry.Value
            Copy-Item -LiteralPath $entry.Key -Destination $target -Force
            if ((Get-FileHash -LiteralPath $entry.Key).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Copy mismatch: $($entry.Value)" }
            Log "Installed $($entry.Value)"
        }
        Log "RESULT: SUCCESS"
        exit 0
    }
    catch {
        Log "ERROR: $($_.Exception.Message)"
        Log "RESULT: FAILED"
        exit 1
    }
}

# Normal-user part.
foreach ($source in $files.Keys) {
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing $source - run .\build.ps1 first." }
}
if (Get-Process -Name FileConverter -ErrorAction SilentlyContinue) {
    throw "File Converter is running (a conversion or settings window is open). Close it, then run deploy again."
}

$log = Join-Path $env:TEMP ("FileConverter-local-build\deploy-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
New-Item -ItemType File -Force -Path $log | Out-Null
$arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-InstallDir", "`"$InstallDir`"", "-ElevatedLog", "`"$log`"")
$elevated = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $arguments -Wait -PassThru
Get-Content -LiteralPath $log
if ($elevated.ExitCode -ne 0) { throw "Deploy failed - see the log above." }

if (-not $SkipPresetRefresh) {
    $userSettings = Join-Path $env:LOCALAPPDATA "FileConverter\Settings.user.xml"
    if (Test-Path -LiteralPath $userSettings) {
        $settingsBackup = Join-Path $repo ("backups\Settings.user_before_preset_refresh_" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".xml")
        Copy-Item -LiteralPath $userSettings -Destination $settingsBackup
        Write-Host "Backed up your settings to $settingsBackup"
    }
    Start-Process -FilePath (Join-Path $InstallDir "FileConverter.exe") -ArgumentList "--post-install-init" -Wait
    Write-Host "Built-in presets refreshed (custom presets kept, edits to built-in presets reset)."
}
Write-Host "Done."
