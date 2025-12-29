# ExportXml launcher script for zabbix_vbr_job.ps1 with nowait parameter
# This script starts the ExportXml jobs asynchronously and returns immediately
# to meet Zabbix agent timeout requirements
#
# Usage: Called by zabbix_vbr_job.ps1 when exportxml nowait is requested
# The main script (zabbix_vbr_job.ps1) detects nowait and calls this script
# to launch the ExportXml work in a background process

# Suppress errors and warnings
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

# Get the script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainScript = Join-Path $scriptDir "zabbix_vbr_job.ps1"

# Verify main script exists
if (-not (Test-Path $mainScript)) {
    Write-Error "Main script not found: $mainScript"
    exit 1
}

# Start the main script in a background process using Start-Process
# Use -WindowStyle Hidden to run in background, but don't wait for it
# The main script will handle starting all the ExportXml jobs
# NOTE: Call with just "exportxml" (without "nowait") so the background process
# actually does the work instead of calling this launcher script again
$process = Start-Process -FilePath "pwsh.exe" `
    -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$mainScript`"",
        "exportxml"
    ) `
    -WindowStyle Hidden `
    -PassThru `
    -ErrorAction SilentlyContinue

# Verify process started
if ($null -eq $process) {
    Write-Error "Failed to start background process"
    exit 1
}

# Return success immediately
# Zabbix expects "1" for success
Write-Output "1"

# Exit immediately - don't wait for the process or jobs
exit 0


