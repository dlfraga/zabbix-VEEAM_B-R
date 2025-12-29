# Script: zabbix_vbr_job
# Author: Romainsi
# Description: Query Veeam job information
# This script is intended for use with Zabbix > 3.X
#
# USAGE:
#
#   as a script:    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" <ITEM_TO_QUERY> <JOBID>or<JOBNAME> <TRIGGERLEVEL>
#                    (For Veeam 13+, use pwsh.exe. For Veeam 12, use powershell.exe)
#   as an item:     vbr[<ITEM_TO_QUERY>,<JOBID>or<JOBNAME>,<TRIGGERLEVEL>]
#
#
# ITEMS availables (Switch) :
# - DiscoveryBackupJobs
# - DiscoveryBackupSyncJobs
# - DiscoveryTapeJobs
# - DiscoveryEndpointJobs
# - DiscoveryReplicaJobs
# - DiscoveryRepo
# - DiscoveryBackupVmsByJobs
# - ExportXml
# - JobsCount
# - RunningJob
#
# Examples:
# pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" DiscoveryBackupJobs
# Return a Json Value with all Backups Name and JobID 
# Xml must be present in 'C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam\*.xml', if not, you can launch manually : pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" ExportXml
#
# ITEMS availables (Switch) with JOBID Mandatory :
# - ResultBackup
# - ResultBackupSync
# - ResultTape
# - ResultEndpoint
# - ResultReplica
# - VmResultBackup
# - VmResultBackupSync
# - RepoCapacity
# - RepoFree
# - RunStatus
# - VmCount
# - VmCountResultBackup
# - VmCountResultBackupSync
# - Type
# - NextRunTime
# - LastEndTime          Returns Unix timestamp of when backup metadata was last updated (from backupbackup.xml MetaUpdateTime)
# - LastRunTime          Returns Unix timestamp of when the job last completed/finished (from backupsession.xml EndTime)
#
# Examples:
# pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" ResultBackup "2fd246be-b32a-4c65-be3e-1ca5546ef225"
# Return the value of result (see the veeam-replace function for correspondence)
# or
# pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" VmCountResultBackup "BackupJob1" "Warning"
#
# Xml must be present in 'C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam\*.xml', if not, you can launch manually : pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" ExportXml
#
#
#
# Add to Zabbix Agent
#   For Veeam 13+: UserParameter=vbr[*],"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" "$1" "$2" "$3"
#   For Veeam 12:  UserParameter=vbr[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" "$1" "$2" "$3"
#
# NOTE: Veeam 13 requires PowerShell 7.0 or higher. If you're using Veeam 13, you MUST use pwsh.exe instead of powershell.exe

# Check PowerShell version - Veeam 13 requires PowerShell 7.0+
if ($PSVersionTable.PSVersion.Major -lt 7) {
	$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
	if (Test-Path $pwshPath) {
		# Relaunch with PowerShell 7
		& $pwshPath -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path $args
		exit $LASTEXITCODE
	} else {
		Write-Error "Veeam 13 requires PowerShell 7.0 or higher. Current version: $($PSVersionTable.PSVersion). Please install PowerShell 7 or update your Zabbix agent configuration to use pwsh.exe instead of powershell.exe."
		exit 1
	}
}

# If you change the pathxml modify also the item Result Export XML with the new location in zabbix template
$pathxml = 'C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam'

# ONLY FOR VMs RESULTS :
# Ajust the start date for retrieve backup vms history
#
# Example : If you have a backup job that runs every 30 days this value must be at least '-31' days
# but if you have only daily job ajust to '-2' days.
# ! This request can consume a lot of cpu resources, adjust carefully !
# 
$days = '-3'

# Function convert return Json String to html
function convertto-encoding
{
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline = $true)]
		[string]$item,
		[Parameter(Mandatory = $true)]
		[string]$switch
	)
	if ($switch -like "in")
	{
		$item.replace('&', '&amp;').replace('à', '&agrave;').replace('â', '&acirc;').replace('è', '&egrave;').replace('é', '&eacute;').replace('ê', '&ecirc;')
	}
	if ($switch -like "out")
	{
		$item.replace('&amp;', '&').replace('&agrave;', 'à').replace('&acirc;', 'â').replace('&egrave;', 'è').replace('&eacute;', 'é').replace('&ecirc;', 'ê')
	}
}

$ITEM = [string]$args[0]
$ID = [string]$args[1] | convertto-encoding -switch out
$ID0 = [string]$args[2] | convertto-encoding -switch out

# Function to test Veeam PowerShell module loading and connection
function Test-VeeamHealth
{
	[CmdletBinding()]
	Param()
	
	$errors = @()
	$warnings = @()
	
	Write-Host "=== Veeam PowerShell Health Check ===" -ForegroundColor Cyan
	Write-Host ""
	
	# Check PowerShell version
	Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor White
	if ($PSVersionTable.PSVersion.Major -lt 7) {
		$warnings += "PowerShell version is below 7.0. Veeam 13+ requires PowerShell 7.0 or higher."
		Write-Host "  WARNING: PowerShell version is below 7.0" -ForegroundColor Yellow
	} else {
		Write-Host "  OK: PowerShell version is 7.0 or higher" -ForegroundColor Green
	}
	Write-Host ""
	
	# Test module loading
	Write-Host "Testing Veeam PowerShell Module Loading..." -ForegroundColor White
	$moduleLoaded = $false
	$moduleName = $null
	
	# Try Veeam 13+ module first
	if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
		try {
			Import-Module Veeam.Backup.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
			if (Get-Module -Name Veeam.Backup.PowerShell) {
				$moduleLoaded = $true
				$moduleName = "Veeam.Backup.PowerShell (Module)"
				Write-Host "  OK: Veeam.Backup.PowerShell module loaded successfully" -ForegroundColor Green
			}
		} catch {
			$errors += "Failed to import Veeam.Backup.PowerShell module: $($_.Exception.Message)"
			Write-Host "  ERROR: Failed to import module - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	
	# Try direct paths
	if (-not $moduleLoaded) {
		$possiblePaths = @(
			"C:\Program Files\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell",
			"C:\Program Files (x86)\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell"
		)
		
		foreach ($path in $possiblePaths) {
			if (Test-Path (Join-Path $path "Veeam.Backup.PowerShell.psd1")) {
				try {
					Import-Module $path -ErrorAction Stop -WarningAction SilentlyContinue
					if (Get-Module -Name Veeam.Backup.PowerShell) {
						$moduleLoaded = $true
						$moduleName = "Veeam.Backup.PowerShell (Module from $path)"
						Write-Host "  OK: Veeam.Backup.PowerShell module loaded from $path" -ForegroundColor Green
						break
					}
				} catch {
					$errors += "Failed to import Veeam.Backup.PowerShell module from $path : $($_.Exception.Message)"
					Write-Host "  ERROR: Failed to import from $path - $($_.Exception.Message)" -ForegroundColor Red
				}
			}
		}
	}
	
	# Try snapin (Veeam 12)
	if (-not $moduleLoaded) {
		try {
			Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction Stop
			$moduleLoaded = $true
			$moduleName = "VeeamPSSnapIn (Snapin)"
			Write-Host "  OK: VeeamPSSnapIn snapin loaded successfully" -ForegroundColor Green
		} catch {
			$errors += "Failed to load VeeamPSSnapIn snapin: $($_.Exception.Message)"
			Write-Host "  ERROR: Failed to load snapin - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	
	if (-not $moduleLoaded) {
		$errors += "Could not load Veeam PowerShell module or snapin. Veeam may not be installed or module path is incorrect."
		Write-Host "  ERROR: Could not load Veeam PowerShell module or snapin" -ForegroundColor Red
		Write-Host ""
		Write-Host "=== Health Check FAILED ===" -ForegroundColor Red
		Write-Host ""
		return $false
	}
	
	Write-Host "  Module Type: $moduleName" -ForegroundColor Gray
	Write-Host ""
	
	# Test Veeam connection
	# Note: Connect-VBRServer may return $null even when connection is successful
	# So we test the connection by actually using a Veeam cmdlet
	Write-Host "Testing Veeam Server Connection..." -ForegroundColor White
	try {
		$null = Connect-VBRServer -ErrorAction Stop
		# Test connection by trying to execute a simple Veeam cmdlet
		$connectionTest = Get-VBRJob -ErrorAction Stop | Select-Object -First 1
		Write-Host "  OK: Successfully connected to Veeam Backup Server" -ForegroundColor Green
	} catch {
		$errors += "Failed to connect to Veeam Backup Server: $($_.Exception.Message)"
		Write-Host "  ERROR: Connection failed - $($_.Exception.Message)" -ForegroundColor Red
		Write-Host ""
		Write-Host "=== Health Check FAILED ===" -ForegroundColor Red
		Write-Host ""
		return $false
	}
	Write-Host ""
	
	# Test basic Veeam cmdlets
	Write-Host "Testing Veeam Cmdlets..." -ForegroundColor White
	$cmdletTests = @(
		@{ Name = "Get-VBRJob"; Test = { Get-VBRJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackupSession"; Test = { Get-VBRBackupSession -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackup"; Test = { Get-VBRBackup -ErrorAction Stop | Select-Object -First 1 } }
	)
	
	$cmdletErrors = 0
	foreach ($cmdlet in $cmdletTests) {
		try {
			$result = & $cmdlet.Test
			Write-Host "  OK: $($cmdlet.Name) executed successfully" -ForegroundColor Green
		} catch {
			$cmdletErrors++
			$errors += "$($cmdlet.Name) failed: $($_.Exception.Message)"
			Write-Host "  ERROR: $($cmdlet.Name) failed - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	Write-Host ""
	
	# Test ExportXml data retrieval - verify all cmdlets used by ExportXml can return data
	Write-Host "Testing ExportXml Data Retrieval..." -ForegroundColor White
	$exportXmlTests = @(
		@{ Name = "Get-VBRBackupSession (for backupsession.xml)"; Test = { Get-VBRBackupSession -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRJob (for backupjob.xml)"; Test = { Get-VBRJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackup (for backupbackup.xml)"; Test = { Get-VBRBackup -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRTapeJob (for backuptape.xml)"; Test = { Get-VBRTapeJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBREPJob (for backupendpoint.xml)"; Test = { Get-VBREPJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRJob with Backup filter (for backupvmbyjob.xml)"; Test = { Get-VBRJob -ErrorAction Stop | Where-Object { $_.JobType -eq "Backup" } | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackupCopyJob (for backupsyncvmbyjob.xml)"; Test = { Get-VBRBackupCopyJob -ErrorAction Stop | Select-Object -First 1 } }
	)
	
	$exportXmlErrors = 0
	foreach ($test in $exportXmlTests) {
		try {
			$result = & $test.Test
			if ($null -eq $result) {
				Write-Host "  WARNING: $($test.Name) returned no data (may be expected if no jobs exist)" -ForegroundColor Yellow
			} else {
				Write-Host "  OK: $($test.Name) returned data" -ForegroundColor Green
			}
		} catch {
			$exportXmlErrors++
			$errors += "$($test.Name) failed: $($_.Exception.Message)"
			Write-Host "  ERROR: $($test.Name) failed - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	Write-Host ""
	
	# Test XML serialization and directory write access
	Write-Host "Testing XML Export Capabilities..." -ForegroundColor White
	try {
		# Test if XML directory exists and is writable
		$testPath = 'C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam'
		if (-not (Test-Path $testPath)) {
			try {
				New-Item -ItemType Directory -Force -Path $testPath -ErrorAction Stop | Out-Null
				Write-Host "  OK: XML directory created: $testPath" -ForegroundColor Green
			} catch {
				$errors += "Cannot create XML directory $testPath : $($_.Exception.Message)"
				Write-Host "  ERROR: Cannot create XML directory - $($_.Exception.Message)" -ForegroundColor Red
			}
		} else {
			Write-Host "  OK: XML directory exists: $testPath" -ForegroundColor Green
		}
		
		# Test if we can write to the directory
		$testFile = Join-Path $testPath "healthcheck_test.xml"
		try {
			$testData = Get-VBRJob -ErrorAction Stop | Select-Object -First 1
			if ($testData) {
				$testData | Export-Clixml $testFile -ErrorAction Stop
				if (Test-Path $testFile) {
					Write-Host "  OK: XML serialization test successful" -ForegroundColor Green
					Remove-Item $testFile -ErrorAction SilentlyContinue
				} else {
					$errors += "XML file was not created during test"
					Write-Host "  ERROR: XML file was not created" -ForegroundColor Red
				}
			} else {
				Write-Host "  WARNING: No data available for XML serialization test" -ForegroundColor Yellow
			}
		} catch {
			$errors += "XML serialization test failed: $($_.Exception.Message)"
			Write-Host "  ERROR: XML serialization test failed - $($_.Exception.Message)" -ForegroundColor Red
		}
	} catch {
		$errors += "XML export capability test failed: $($_.Exception.Message)"
		Write-Host "  ERROR: XML export capability test failed - $($_.Exception.Message)" -ForegroundColor Red
	}
	Write-Host ""
	
	# Disconnect
	try {
		Disconnect-VBRServer -ErrorAction SilentlyContinue
	} catch {
		# Ignore disconnect errors
	}
	
	# Summary
	if ($errors.Count -eq 0) {
		Write-Host "=== Health Check PASSED ===" -ForegroundColor Green
		Write-Host ""
		return $true
	} else {
		Write-Host "=== Health Check FAILED ===" -ForegroundColor Red
		Write-Host ""
		Write-Host "Errors found:" -ForegroundColor Red
		foreach ($error in $errors) {
			Write-Host "  - $error" -ForegroundColor Red
		}
		Write-Host ""
		return $false
	}
}

# Function to test Veeam PowerShell module loading and connection
function Test-VeeamHealth
{
	[CmdletBinding()]
	Param()
	
	$errors = @()
	$warnings = @()
	
	Write-Host "=== Veeam PowerShell Health Check ===" -ForegroundColor Cyan
	Write-Host ""
	
	# Check PowerShell version
	Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor White
	if ($PSVersionTable.PSVersion.Major -lt 7) {
		$warnings += "PowerShell version is below 7.0. Veeam 13+ requires PowerShell 7.0 or higher."
		Write-Host "  WARNING: PowerShell version is below 7.0" -ForegroundColor Yellow
	} else {
		Write-Host "  OK: PowerShell version is 7.0 or higher" -ForegroundColor Green
	}
	Write-Host ""
	
	# Test module loading
	Write-Host "Testing Veeam PowerShell Module Loading..." -ForegroundColor White
	$moduleLoaded = $false
	$moduleName = $null
	
	# Try Veeam 13+ module first
	if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
		try {
			Import-Module Veeam.Backup.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
			if (Get-Module -Name Veeam.Backup.PowerShell) {
				$moduleLoaded = $true
				$moduleName = "Veeam.Backup.PowerShell (Module)"
				Write-Host "  OK: Veeam.Backup.PowerShell module loaded successfully" -ForegroundColor Green
			}
		} catch {
			$errors += "Failed to import Veeam.Backup.PowerShell module: $($_.Exception.Message)"
			Write-Host "  ERROR: Failed to import module - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	
	# Try direct paths
	if (-not $moduleLoaded) {
		$possiblePaths = @(
			"C:\Program Files\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell",
			"C:\Program Files (x86)\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell"
		)
		
		foreach ($path in $possiblePaths) {
			if (Test-Path (Join-Path $path "Veeam.Backup.PowerShell.psd1")) {
				try {
					Import-Module $path -ErrorAction Stop -WarningAction SilentlyContinue
					if (Get-Module -Name Veeam.Backup.PowerShell) {
						$moduleLoaded = $true
						$moduleName = "Veeam.Backup.PowerShell (Module from $path)"
						Write-Host "  OK: Veeam.Backup.PowerShell module loaded from $path" -ForegroundColor Green
						break
					}
				} catch {
					$errors += "Failed to import Veeam.Backup.PowerShell module from $path : $($_.Exception.Message)"
					Write-Host "  ERROR: Failed to import from $path - $($_.Exception.Message)" -ForegroundColor Red
				}
			}
		}
	}
	
	# Try snapin (Veeam 12)
	if (-not $moduleLoaded) {
		try {
			Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction Stop
			$moduleLoaded = $true
			$moduleName = "VeeamPSSnapIn (Snapin)"
			Write-Host "  OK: VeeamPSSnapIn snapin loaded successfully" -ForegroundColor Green
		} catch {
			$errors += "Failed to load VeeamPSSnapIn snapin: $($_.Exception.Message)"
			Write-Host "  ERROR: Failed to load snapin - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	
	if (-not $moduleLoaded) {
		$errors += "Could not load Veeam PowerShell module or snapin. Veeam may not be installed or module path is incorrect."
		Write-Host "  ERROR: Could not load Veeam PowerShell module or snapin" -ForegroundColor Red
		Write-Host ""
		Write-Host "=== Health Check FAILED ===" -ForegroundColor Red
		Write-Host ""
		return $false
	}
	
	Write-Host "  Module Type: $moduleName" -ForegroundColor Gray
	Write-Host ""
	
	# Test Veeam connection
	# Note: Connect-VBRServer may return $null even when connection is successful
	# So we test the connection by actually using a Veeam cmdlet
	Write-Host "Testing Veeam Server Connection..." -ForegroundColor White
	try {
		$null = Connect-VBRServer -ErrorAction Stop
		# Test connection by trying to execute a simple Veeam cmdlet
		$connectionTest = Get-VBRJob -ErrorAction Stop | Select-Object -First 1
		Write-Host "  OK: Successfully connected to Veeam Backup Server" -ForegroundColor Green
	} catch {
		$errors += "Failed to connect to Veeam Backup Server: $($_.Exception.Message)"
		Write-Host "  ERROR: Connection failed - $($_.Exception.Message)" -ForegroundColor Red
		Write-Host ""
		Write-Host "=== Health Check FAILED ===" -ForegroundColor Red
		Write-Host ""
		return $false
	}
	Write-Host ""
	
	# Test basic Veeam cmdlets
	Write-Host "Testing Veeam Cmdlets..." -ForegroundColor White
	$cmdletTests = @(
		@{ Name = "Get-VBRJob"; Test = { Get-VBRJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackupSession"; Test = { Get-VBRBackupSession -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackup"; Test = { Get-VBRBackup -ErrorAction Stop | Select-Object -First 1 } }
	)
	
	$cmdletErrors = 0
	foreach ($cmdlet in $cmdletTests) {
		try {
			$result = & $cmdlet.Test
			Write-Host "  OK: $($cmdlet.Name) executed successfully" -ForegroundColor Green
		} catch {
			$cmdletErrors++
			$errors += "$($cmdlet.Name) failed: $($_.Exception.Message)"
			Write-Host "  ERROR: $($cmdlet.Name) failed - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	Write-Host ""
	
	# Test ExportXml data retrieval - verify all cmdlets used by ExportXml can return data
	Write-Host "Testing ExportXml Data Retrieval..." -ForegroundColor White
	$exportXmlTests = @(
		@{ Name = "Get-VBRBackupSession (for backupsession.xml)"; Test = { Get-VBRBackupSession -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRJob (for backupjob.xml)"; Test = { Get-VBRJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackup (for backupbackup.xml)"; Test = { Get-VBRBackup -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRTapeJob (for backuptape.xml)"; Test = { Get-VBRTapeJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBREPJob (for backupendpoint.xml)"; Test = { Get-VBREPJob -ErrorAction Stop | Select-Object -First 1 } },
		@{ Name = "Get-VBRJob with Backup filter (for backupvmbyjob.xml)"; Test = { Get-VBRJob -ErrorAction Stop | Where-Object { $_.JobType -eq "Backup" } | Select-Object -First 1 } },
		@{ Name = "Get-VBRBackupCopyJob (for backupsyncvmbyjob.xml)"; Test = { Get-VBRBackupCopyJob -ErrorAction Stop | Select-Object -First 1 } }
	)
	
	$exportXmlErrors = 0
	foreach ($test in $exportXmlTests) {
		try {
			$result = & $test.Test
			if ($null -eq $result) {
				Write-Host "  WARNING: $($test.Name) returned no data (may be expected if no jobs exist)" -ForegroundColor Yellow
			} else {
				Write-Host "  OK: $($test.Name) returned data" -ForegroundColor Green
			}
		} catch {
			$exportXmlErrors++
			$errors += "$($test.Name) failed: $($_.Exception.Message)"
			Write-Host "  ERROR: $($test.Name) failed - $($_.Exception.Message)" -ForegroundColor Red
		}
	}
	Write-Host ""
	
	# Test XML serialization and directory write access
	Write-Host "Testing XML Export Capabilities..." -ForegroundColor White
	try {
		# Test if XML directory exists and is writable
		$testPath = 'C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam'
		if (-not (Test-Path $testPath)) {
			try {
				New-Item -ItemType Directory -Force -Path $testPath -ErrorAction Stop | Out-Null
				Write-Host "  OK: XML directory created: $testPath" -ForegroundColor Green
			} catch {
				$errors += "Cannot create XML directory $testPath : $($_.Exception.Message)"
				Write-Host "  ERROR: Cannot create XML directory - $($_.Exception.Message)" -ForegroundColor Red
			}
		} else {
			Write-Host "  OK: XML directory exists: $testPath" -ForegroundColor Green
		}
		
		# Test if we can write to the directory
		$testFile = Join-Path $testPath "healthcheck_test.xml"
		try {
			$testData = Get-VBRJob -ErrorAction Stop | Select-Object -First 1
			if ($testData) {
				$testData | Export-Clixml $testFile -ErrorAction Stop
				if (Test-Path $testFile) {
					Write-Host "  OK: XML serialization test successful" -ForegroundColor Green
					Remove-Item $testFile -ErrorAction SilentlyContinue
				} else {
					$errors += "XML file was not created during test"
					Write-Host "  ERROR: XML file was not created" -ForegroundColor Red
				}
			} else {
				Write-Host "  WARNING: No data available for XML serialization test" -ForegroundColor Yellow
			}
		} catch {
			$errors += "XML serialization test failed: $($_.Exception.Message)"
			Write-Host "  ERROR: XML serialization test failed - $($_.Exception.Message)" -ForegroundColor Red
		}
	} catch {
		$errors += "XML export capability test failed: $($_.Exception.Message)"
		Write-Host "  ERROR: XML export capability test failed - $($_.Exception.Message)" -ForegroundColor Red
	}
	Write-Host ""
	
	# Disconnect
	try {
		Disconnect-VBRServer -ErrorAction SilentlyContinue
	} catch {
		# Ignore disconnect errors
	}
	
	# Summary
	if ($errors.Count -eq 0) {
		Write-Host "=== Health Check PASSED ===" -ForegroundColor Green
		Write-Host ""
		return $true
	} else {
		Write-Host "=== Health Check FAILED ===" -ForegroundColor Red
		Write-Host ""
		Write-Host "Errors found:" -ForegroundColor Red
		foreach ($error in $errors) {
			Write-Host "  - $error" -ForegroundColor Red
		}
		Write-Host ""
		return $false
	}
}

# Cache for discovered Veeam module path (performance optimization)
$script:VeeamModulePath = $null
$script:VeeamModuleType = $null

# Function to discover and cache Veeam PowerShell module path
function Get-VeeamModulePath
{
	[CmdletBinding()]
	Param()
	
	# Return cached path if already discovered
	if ($script:VeeamModulePath) {
		return @{
			Path = $script:VeeamModulePath
			Type = $script:VeeamModuleType
		}
	}
	
	# Try to import from standard module paths (Veeam 13+)
	if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
		$script:VeeamModulePath = "Veeam.Backup.PowerShell"
		$script:VeeamModuleType = "Module"
		return @{
			Path = $script:VeeamModulePath
			Type = $script:VeeamModuleType
		}
	}
	
	# Try common installation paths
	$possiblePaths = @(
		"C:\Program Files\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell",
		"C:\Program Files (x86)\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell"
	)
	
	# Try to get from registry
	try {
		$installDir = (Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication" -Name "InstallDir" -ErrorAction SilentlyContinue).InstallDir
		if ($installDir) {
			$modulePathFromReg = Join-Path $installDir "Backup\BackupClient\Veeam.Backup.PowerShell"
			if (Test-Path $modulePathFromReg) {
				$possiblePaths = @($modulePathFromReg) + $possiblePaths
			}
		}
	} catch {}
	
	foreach ($path in $possiblePaths) {
		if (Test-Path (Join-Path $path "Veeam.Backup.PowerShell.psd1")) {
			$script:VeeamModulePath = $path
			$script:VeeamModuleType = "Module"
			return @{
				Path = $script:VeeamModulePath
				Type = $script:VeeamModuleType
			}
		}
	}
	
	# Fall back to snapin (Veeam 12 and earlier)
	$script:VeeamModulePath = "VeeamPSSnapIn"
	$script:VeeamModuleType = "Snapin"
	return @{
		Path = $script:VeeamModulePath
		Type = $script:VeeamModuleType
	}
}

# Function to load Veeam PowerShell module or snapin
function Load-VeeamPowerShell
{
	[CmdletBinding()]
	Param()
	
	$moduleInfo = Get-VeeamModulePath
	$moduleLoaded = $false
	
	if ($moduleInfo.Type -eq "Module") {
		if ($moduleInfo.Path -eq "Veeam.Backup.PowerShell") {
			# Standard module path
			Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
			if (Get-Module -Name Veeam.Backup.PowerShell) {
				$moduleLoaded = $true
			}
		} else {
			# Direct path
			Import-Module $moduleInfo.Path -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
			if (Get-Module -Name Veeam.Backup.PowerShell) {
				$moduleLoaded = $true
			}
		}
	} else {
		# Snapin
		Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue
		$moduleLoaded = $true
	}
}

# Function Multiprocess ExportXml
function ExportXml
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[string]$switch,
		[Parameter(Mandatory = $true)]
		[string]$name,
		[Parameter(Mandatory = $false)]
		[string]$command,
		[Parameter(Mandatory = $false)]
		[string]$type,
		[Parameter(Mandatory = $false)]
		[hashtable]$moduleInfoOverride = $null
	)
	
	PROCESS
	{
		# Write directly to final location (performance optimization - no temp file needed)
		$newpath = "$pathxml\$name" + ".xml"
		
		if ($switch -like "normal")
		{
			# Get cached module path (performance optimization)
			# Use override if provided (for nowait mode to skip discovery)
			# For nowait mode, moduleInfoOverride will have Path=$null, but we still use it to skip Get-VeeamModulePath
			if ($null -ne $moduleInfoOverride) {
				$moduleInfo = $moduleInfoOverride
			} else {
				$moduleInfo = Get-VeeamModulePath
			}
			
			Start-Job -Name $name -ScriptBlock {
				# Suppress warnings but allow errors to be captured
				$WarningPreference = 'SilentlyContinue'
				$ErrorActionPreference = 'Stop'
				
				try {
					# Load Veeam PowerShell module or snapin
					# If moduleInfo is null/empty (nowait mode), discover module path ourselves
					$moduleLoaded = $false
					if ($null -eq $args[4] -or $null -eq $args[4].Type -or [string]::IsNullOrEmpty($args[4].Path)) {
						# No moduleInfo provided - discover it ourselves (nowait mode)
						if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
							Import-Module Veeam.Backup.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
							if (Get-Module -Name Veeam.Backup.PowerShell) {
								$moduleLoaded = $true
							}
						} else {
							# Try common paths
							$possiblePaths = @(
								"C:\Program Files\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell",
								"C:\Program Files (x86)\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell"
							)
							foreach ($path in $possiblePaths) {
								if (Test-Path (Join-Path $path "Veeam.Backup.PowerShell.psd1")) {
									Import-Module $path -ErrorAction Stop -WarningAction SilentlyContinue
									if (Get-Module -Name Veeam.Backup.PowerShell) {
										$moduleLoaded = $true
										break
									}
								}
							}
							if (-not $moduleLoaded) {
								Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction Stop
								$moduleLoaded = $true
							}
						}
					} elseif ($args[4].Type -eq "Module") {
						# Use provided moduleInfo
						if ($args[4].Path -eq "Veeam.Backup.PowerShell") {
							Import-Module Veeam.Backup.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
						} else {
							Import-Module $args[4].Path -ErrorAction Stop -WarningAction SilentlyContinue
						}
						if (Get-Module -Name Veeam.Backup.PowerShell) {
							$moduleLoaded = $true
						} else {
							throw "Failed to load Veeam PowerShell module"
						}
					} else {
						Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction Stop
						$moduleLoaded = $true
					}
					
					if (-not $moduleLoaded) {
						throw "Veeam PowerShell module/snapin was not loaded"
					}
					
					$connectVeeam = Connect-VBRServer
					if ($null -eq $connectVeeam) {
						# Test connection by trying a cmdlet
						$testConnection = Get-VBRJob -ErrorAction Stop | Select-Object -First 1
					}
					
					# Execute command based on command string (avoid script block serialization issues)
					# Use direct cmdlet calls for better performance and reliability
					$result = switch ($args[0]) {
						"Get-VBRBackupSession" { Get-VBRBackupSession }
						"Get-VBRJob" { Get-VBRJob }
						"Get-VBRBackup" { Get-VBRBackup }
						"Get-VBRTapeJob" { Get-VBRTapeJob }
						"Get-VBREPJob" { Get-VBREPJob }
						default { throw "Unknown command: $($args[0])" }
					}
					
					if ($null -eq $result) {
						# Empty result is OK for some cmdlets (e.g., Get-VBRTapeJob if no tape jobs exist)
						# Create empty array to ensure XML file is created
						$result = @()
					}
					
					$result | Export-Clixml $args[1] -ErrorAction Stop
					$disconnectVeeam = Disconnect-VBRServer
				} catch {
					# Write error to output so it can be captured by Receive-Job
					Write-Error "Job '$($args[2])' failed: $($_.Exception.Message)" -ErrorAction Continue
					throw
				}
			} -ArgumentList "$command", "$newpath", "$name", "$newpath", $moduleInfo
		}
		
		
		if ($switch -like "byvm")
		{
			# Get cached module path (performance optimization)
			# Use override if provided (for nowait mode to skip discovery)
			# For nowait mode, moduleInfoOverride will have Path=$null, but we still use it to skip Get-VeeamModulePath
			if ($null -ne $moduleInfoOverride) {
				$moduleInfo = $moduleInfoOverride
			} else {
				$moduleInfo = Get-VeeamModulePath
			}
			
			# Phase 2 optimization: Create optimized script blocks instead of string commands
			if ($type -eq "BackupSync") {
				# For Veeam 13+, use Get-VBRBackupCopyJob directly
				$byvmScriptBlock = {
					Get-VBRBackupCopyJob | ForEach-Object {
						$JobName = $_.Name
						$_ | Get-VBRJobObject | Where-Object { $_.Object.Type -eq "VM" } | Select-Object @{ L = "Job"; E = { $JobName } }, Name | Sort-Object -Property Job, Name
					}
				}
			} else {
				# For Backup type, filter Get-VBRJob
				$byvmScriptBlock = {
					Get-VBRJob | Where-Object { $_.JobType -eq $args[0] } | ForEach-Object {
						$JobName = $_.Name
						$_ | Get-VBRJobObject | Where-Object { $_.Object.Type -eq "VM" } | Select-Object @{ L = "Job"; E = { $JobName } }, Name | Sort-Object -Property Job, Name
					}
				}
			}
			
			Start-Job -Name $name -ScriptBlock {
				# Suppress warnings and errors
				$ErrorActionPreference = 'SilentlyContinue'
				$WarningPreference = 'SilentlyContinue'
				
				# Load Veeam PowerShell module or snapin using cached path
				# Handle null/empty moduleInfo (nowait mode)
				$moduleLoaded = $false
				if ($null -eq $args[4] -or $null -eq $args[4].Type -or [string]::IsNullOrEmpty($args[4].Path)) {
					# No moduleInfo provided - discover it ourselves (nowait mode)
					if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
						Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
						if (Get-Module -Name Veeam.Backup.PowerShell) {
							$moduleLoaded = $true
						}
					} else {
						# Try common paths
						$possiblePaths = @(
							"C:\Program Files\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell",
							"C:\Program Files (x86)\Veeam\Backup and Replication\Backup\BackupClient\Veeam.Backup.PowerShell"
						)
						foreach ($path in $possiblePaths) {
							if (Test-Path (Join-Path $path "Veeam.Backup.PowerShell.psd1")) {
								Import-Module $path -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
								if (Get-Module -Name Veeam.Backup.PowerShell) {
									$moduleLoaded = $true
									break
								}
							}
						}
						if (-not $moduleLoaded) {
							Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue
							$moduleLoaded = $true
						}
					}
				} elseif ($args[4].Type -eq "Module") {
					if ($args[4].Path -eq "Veeam.Backup.PowerShell") {
						Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
					} else {
						Import-Module $args[4].Path -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
					}
					if (Get-Module -Name Veeam.Backup.PowerShell) {
						$moduleLoaded = $true
					}
				} else {
					Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue
					$moduleLoaded = $true
				}
				
				$connectVeeam = Connect-VBRServer
				# Phase 2 optimization: Use script block instead of Invoke-Expression
				if ($args[5]) {
					# Use script block with type parameter if needed
					$BackupVmByJob = & $args[5] $args[6]
				} else {
					# Fallback (should not happen)
					$BackupVmByJob = @()
				}
				# Write directly to final location (performance optimization)
				$BackupVmByJob | Export-Clixml $args[1]
				$disconnectVeeam = Disconnect-VBRServer
			} -ArgumentList $null, "$newpath", "$name", "$newpath", $moduleInfo, $byvmScriptBlock, $type
		}
		
		if ($switch -like "bytaskswithretry")
		{
			# Get cached module path (performance optimization)
			# Use override if provided (for nowait mode to skip discovery)
			# For nowait mode, moduleInfoOverride will have Path=$null, but we still use it to skip Get-VeeamModulePath
			if ($null -ne $moduleInfoOverride) {
				$moduleInfo = $moduleInfoOverride
			} else {
				$moduleInfo = Get-VeeamModulePath
			}
			
			Start-Job -Name $name -ScriptBlock {
				# Suppress warnings and errors
				$ErrorActionPreference = 'SilentlyContinue'
				$WarningPreference = 'SilentlyContinue'
				
				# Load Veeam PowerShell module or snapin using cached path
				$moduleLoaded = $false
				if ($args[5].Type -eq "Module") {
					if ($args[5].Path -eq "Veeam.Backup.PowerShell") {
						Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
					} else {
						Import-Module $args[5].Path -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
					}
					if (Get-Module -Name Veeam.Backup.PowerShell) {
						$moduleLoaded = $true
					}
				} else {
					Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue
					$moduleLoaded = $true
				}
				
				$connectVeeam = Connect-VBRServer
				$StartDate = (Get-Date).adddays($args[4])
				# Deduplication optimization: Retrieve all sessions ONCE, then filter in memory
				# This eliminates duplicate Get-VBRBackupSession call (saves ~30-40% of job time)
				$AllBackupSessions = Get-VBRBackupSession | Where-Object { $_.CreationTime -ge $StartDate }
				# Filter in memory (no additional Veeam API call)
				$BackupSessions = $AllBackupSessions | Where-Object { $_.IsRetryMode -eq $false } | Sort-Object JobName, CreationTime
				# Get retry sessions separately for failed sessions only
				$RetrySessionsMap = @{}
				$AllRetrySessions = $AllBackupSessions | Where-Object { $_.IsRetryMode -eq $true }
				foreach ($retry in $AllRetrySessions) {
					if (-not $RetrySessionsMap.ContainsKey($retry.OriginalSessionId)) {
						$RetrySessionsMap[$retry.OriginalSessionId] = @()
					}
					$RetrySessionsMap[$retry.OriginalSessionId] += $retry
				}
				
				$Result = & {
					ForEach ($BackupSession in $BackupSessions)
					{
						[System.Collections.ArrayList]$TaskSessions = @($BackupSession | Get-VBRTaskSession)
						If ($BackupSession.Result -eq "Failed" -and $RetrySessionsMap.ContainsKey($BackupSession.Id))
						{
							ForEach ($RetrySession in $RetrySessionsMap[$BackupSession.Id])
							{
								[System.Collections.ArrayList]$RetryTaskSessions = @($RetrySession | Get-VBRTaskSession)
								ForEach ($RetryTaskSession in $RetryTaskSessions)
								{
									$PriorTaskSession = $TaskSessions | Where-Object { $_.Name -eq $RetryTaskSession.Name }
									If ($PriorTaskSession) { $TaskSessions.Remove($PriorTaskSession) }
									$TaskSessions.Add($RetryTaskSession) | Out-Null
								}
							}
						}
						$TaskSessions | Select-Object @{ N = "JobName"; E = { $BackupSession.JobName } }, @{ N = "JobId"; E = { $BackupSession.JobId } }, @{ N = "SessionName"; E = { $_.JobSess.Name } }, @{ N = "JobResult"; E = { $_.JobSess.Result } }, @{ N = "JobStart"; E = { $_.JobSess.CreationTime } }, @{ N = "JobEnd"; E = { $_.JobSess.EndTime } }, @{ N = "Date"; E = { $_.JobSess.CreationTime.ToString("yyyy-MM-dd") } }, name, status
					}
				}
				# Write directly to final location (performance optimization)
				$Result | Export-Clixml $args[1]
				$disconnectVeeam = Disconnect-VBRServer
			} -ArgumentList "$commandnew", "$newpath", "$name", "$newpath", "$days", $moduleInfo
		}
		
		# Phase 3 optimization: Efficient job cleanup - remove all completed/failed jobs in one operation
		Get-Job | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' } | Remove-Job -ErrorAction SilentlyContinue
	}
}



# Converts an object to a JSON-formatted string
$GlobalConstant = @{
	'ZabbixJsonHost' = 'host'
	'ZabbixJsonKey' = 'key'
	'ZabbixJsonValue' = 'value'
	'ZabbixJsonTimestamp' = 'clock'
	'ZabbixJsonRequest' = 'request'
	'ZabbixJsonData' = 'data'
	'ZabbixJsonSenderData' = 'sender data'
	'ZabbixJsonDiscoveryKey' = '{{#{0}}}'
}

$GlobalConstant += @{
	'ZabbixMappingProperty' = 'Property'
	'ZabbixMappingKey' = 'Key'
	'ZabbixMappingKeyProperty' = 'KeyProperty'
}

foreach ($Constant in $GlobalConstant.GetEnumerator())
{
	Set-Variable -Scope Global -Option ReadOnly -Name $Constant.Key -Value $Constant.Value -Force
}

$ExportFunction = ('ConvertTo-ZabbixDiscoveryJson')

if ($Host.Version.Major -le 2)
{
	$ExportFunction += ('ConvertTo-Json', 'ConvertFrom-Json')
}

function ConvertTo-ZabbixDiscoveryJson
{
	[CmdletBinding()]
	param
	(
		[Parameter(ValueFromPipeline = $true)]
		$InputObject,
		[Parameter(Position = 0)]
		[String[]]$Property = "#JOBID"
	)
	
	begin
	{
		$Result = @()
	}
	
	process
	{
		if ($InputObject)
		{
			$Result += foreach ($Obj in $InputObject)
			{
				if ($Obj)
				{
					$Element = @{ }
					foreach ($P in $Property)
					{
						$Key = $ZabbixJsonDiscoveryKey -f $P.ToUpper()
						$Element[$Key] = [String]$Obj.$P
					}
					$Element
				}
			}
		}
	}
	end
	{
		$Result = @{ $ZabbixJsonData = $Result }
		return $Result | ConvertTo-Json -Compress | ForEach-Object { [System.Text.RegularExpressions.Regex]::Unescape($_) }
	}
}

# Function import xml with check & delay time if copy process running
function ImportXml
{
	[CmdletBinding()]
	Param ([Parameter(ValueFromPipeline = $true)]
		$item)
	
	$path = "$pathxml\$item" + ".xml"
	$result = Test-Path -Path $path
	if ($result -like 'False')
	{
		start-sleep -Seconds 1
	}
	
	$err = $null
	try
	{
		$xmlquery = Import-Clixml "$path"
	}
	catch
	{
		$err = $_
	}
	If ($err -ne $null)
	{
		Start-Sleep -Seconds 1
		$xmlquery = Import-Clixml "$path"
	}
	$xmlquery
}

# Replace Function for Veeam Correlation
function veeam-replace
{
	[CmdletBinding()]
	Param ([Parameter(ValueFromPipeline = $true)]
		$item)
	$item.replace('Failed', '0').replace('Warning', '1').replace('Success', '2').replace('None', '2').replace('idle', '3').replace('InProgress', '5').replace('Pending', '6')
}

# Function Sort-Object VMs by jobs on last backup (with unique name if retry)
function veeam-backuptask-unique
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		$jobtype,
		[Parameter(Mandatory = $true)]
		$ID
	)
	$xml1 = ImportXml -item backuptaskswithretry | Where-Object { $_.$jobtype -like "$ID" }
	$unique = $xml1.Name | Sort-Object -Unique
	
	$output = & {
		foreach ($object in $unique)
		{
			$query = $xml1 | Where-Object { $_.Name -like $object } | Sort-Object JobStart -Descending | Select-Object -First 1
			foreach ($object1 in $query)
			{
				$query | Select-Object @{ N = "JobName"; E = { $object1.JobName } }, @{ N = "JobId"; E = { $object1.JobId } }, @{ N = "SessionName"; E = { $object1.SessionName } }, @{ N = "JobResult"; E = { $object1.JobResult } }, @{ N = "JobStart"; E = { $object1.JobStart } }, @{ N = "JobEnd"; E = { $object1.JobEnd } }, @{ N = "Date"; E = { $object1.Date.ToString("yyyy-MM-dd") } }, @{ N = "Name"; E = { $object1.Name } }, @{ N = "Status"; E = { $object1.Status } }
			}
		}
	}
	$output
}

# Suppress warnings globally for clean Zabbix output
$WarningPreference = 'SilentlyContinue'

# If no parameters provided, run health check
if ([string]::IsNullOrWhiteSpace($ITEM)) {
	$healthCheckResult = Test-VeeamHealth
	if ($healthCheckResult) {
		exit 0
	} else {
		exit 1
	}
}

# Check if this is ExportXml with nowait - if so, skip module loading for faster return
# Module will be loaded by background jobs themselves
$isExportXmlNowait = ($ITEM -like "ExportXml" -or $ITEM -like "exportxml") -and $args.Count -gt 1 -and [string]$args[1] -like "nowait"

# Load Veeam Module (try Veeam 13+ module first, then fall back to Veeam 12 snapin)
# Skip for ExportXml with nowait to return faster
if (-not $isExportXmlNowait) {
	Load-VeeamPowerShell
}

switch ($ITEM)
{
	"DiscoveryBackupJobs" {
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.IsScheduleEnabled -eq "true" -and $_.JobType -like "Backup" } | Select-Object @{ N = "JOBID"; E = { $_.ID | convertto-encoding -switch in } }, @{ N = "JOBNAME"; E = { $_.NAME | convertto-encoding -switch in } }
		$query | ConvertTo-ZabbixDiscoveryJson JOBNAME, JOBID
	}
	
	"DiscoveryBackupSyncJobs" {
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.IsScheduleEnabled -eq "true" -and $_.JobType -like "BackupSync" } | Select-Object @{ N = "JOBBSID"; E = { $_.ID | convertto-encoding -switch in } }, @{ N = "JOBBSNAME"; E = { $_.NAME | convertto-encoding -switch in } }
		$query | ConvertTo-ZabbixDiscoveryJson JOBBSNAME, JOBBSID
	}
	
	"DiscoveryTapeJobs" {
		$xml1 = ImportXml -item backuptape
		$query = $xml1 | Select-Object @{ N = "JOBTAPEID"; E = { $_.ID | convertto-encoding -switch in } }, @{ N = "JOBTAPENAME"; E = { $_.NAME | convertto-encoding -switch in } }
		$query | ConvertTo-ZabbixDiscoveryJson JOBTAPENAME, JOBTAPEID
	}
	
	"DiscoveryEndpointJobs" {
		$xml1 = ImportXml -item backupendpoint
		$query = $xml1 | Select-Object Id, Name | Select-Object @{ N = "JOBENDPOINTID"; E = { $_.ID | convertto-encoding -switch in } }, @{ N = "JOBENDPOINTNAME"; E = { $_.NAME | convertto-encoding -switch in } }
		$query | ConvertTo-ZabbixDiscoveryJson JOBENDPOINTNAME, JOBENDPOINTID
	}
	
	"DiscoveryReplicaJobs" {
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.IsScheduleEnabled -eq "true" -and $_.JobType -like "Replica" } | Select-Object @{ N = "JOBREPLICAID"; E = { $_.ID | convertto-encoding -switch in } }, @{ N = "JOBREPLICANAME"; E = { $_.NAME | convertto-encoding -switch in } }
		$query | ConvertTo-ZabbixDiscoveryJson JOBREPLICANAME, JOBREPLICAID
	}
	
	"DiscoveryRepo" {
		$query = Get-CimInstance -Class Repository -ComputerName $env:COMPUTERNAME -Namespace ROOT\VeeamBS -ErrorAction SilentlyContinue | Select-Object @{ N = "REPONAME"; E = { $_.NAME | convertto-encoding -switch in } }
		$query | ConvertTo-ZabbixDiscoveryJson REPONAME
	}
	
	"DiscoveryBackupVmsByJobs" {
		if ($ID -like "BackupSync")
		{
			ImportXml -item backupsyncvmbyjob | Select-Object @{ N = "JOBNAME"; E = { $_.Job | convertto-encoding -switch in } }, @{ N = "JOBVMNAME"; E = { $_.NAME | convertto-encoding -switch in } } | ConvertTo-ZabbixDiscoveryJson JOBVMNAME, JOBNAME
		}
		else
		{
			ImportXml -item backupvmbyjob | Select-Object @{ N = "JOBNAME"; E = { $_.Job | convertto-encoding -switch in } }, @{ N = "JOBVMNAME"; E = { $_.NAME | convertto-encoding -switch in } } | ConvertTo-ZabbixDiscoveryJson JOBVMNAME, JOBNAME
		}
	}
	
	"ExportXml" {
		
		# Check if "nowait" parameter is provided FIRST (before any heavy operations)
		# This allows immediate return for Zabbix agent timeout requirements
		$nowait = $false
		if ($args.Count -gt 1 -and [string]$args[1] -like "nowait") {
			$nowait = $true
		}
		
		# For nowait mode: Use the ExportXml launcher script to launch in background
		# This allows immediate return to Zabbix agent while work continues in background
		if ($nowait) {
			# Get the script directory
			$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
			$exportXmlScript = Join-Path $scriptDir "zabbix_vbr_exportxml.ps1"
			
			# Verify ExportXml launcher script exists
			if (-not (Test-Path $exportXmlScript)) {
				Write-Error "ExportXml launcher script not found: $exportXmlScript"
				exit 1
			}
			
			# Call the ExportXml launcher script - it will handle launching the exportxml work in background
			# and return immediately
			& $exportXmlScript
			return
		}
		
		$test = Test-Path -Path "$pathxml"
		if ($test -like "False")
		{
			$query = New-Item -ItemType Directory -Force -Path "$pathxml"
		}
		
		# Pre-discover and cache module path ONCE for all background jobs (performance optimization)
		# For blocking mode, discover once and cache for all jobs
		$sharedModuleInfo = Get-VeeamModulePath
		
		# For blocking mode, start jobs normally (sequential but that's OK since we wait anyway)
		$job = ExportXml -command Get-VBRBackupSession -name backupsession -switch normal -moduleInfoOverride $sharedModuleInfo
		$job0 = ExportXml -command Get-VBRJob -name backupjob -switch normal -moduleInfoOverride $sharedModuleInfo
		$job1 = ExportXml -command Get-VBRBackup -name backupbackup -switch normal -moduleInfoOverride $sharedModuleInfo
		$job2 = ExportXml -command Get-VBRTapeJob -name backuptape -switch normal -moduleInfoOverride $sharedModuleInfo
		$job3 = ExportXml -command Get-VBREPJob -name backupendpoint -switch normal -moduleInfoOverride $sharedModuleInfo
		$job4 = ExportXml -command Get-VBRJob -name backupvmbyjob -switch byvm -type Backup -moduleInfoOverride $sharedModuleInfo
		$job5 = ExportXml -command Get-VBRJob -name backupsyncvmbyjob -switch byvm -type BackupSync -moduleInfoOverride $sharedModuleInfo
		$job6 = ExportXml -name backuptaskswithretry -switch bytaskswithretry -moduleInfoOverride $sharedModuleInfo
		
		# Blocking mode: Wait for all jobs to complete (original behavior)
		# Phase 3 optimization: Wait for jobs with timeout and efficient cleanup
		$jobs = Get-Job
		$jobs | Wait-Job -Timeout 600 | Out-Null
		
		# Check job status and report any failures
		$failedJobs = Get-Job | Where-Object { $_.State -eq 'Failed' }
		$runningJobs = Get-Job | Where-Object { $_.State -eq 'Running' }
		
		if ($failedJobs) {
			foreach ($job in $failedJobs) {
				$errorOutput = $job | Receive-Job -ErrorAction SilentlyContinue -ErrorVariable jobErrors 2>&1
				Write-Error "Job '$($job.Name)' (ID: $($job.Id)) FAILED. Error: $($jobErrors.Exception.Message)"
			}
		}
		
		if ($runningJobs) {
			foreach ($job in $runningJobs) {
				Write-Warning "Job '$($job.Name)' (ID: $($job.Id)) is still RUNNING after timeout - may not have completed successfully"
			}
		}
		
		# Verify XML files were created/updated
		$expectedFiles = @(
			@{ Name = "backupsession"; Job = "backupsession" },
			@{ Name = "backupjob"; Job = "backupjob" },
			@{ Name = "backupbackup"; Job = "backupbackup" },
			@{ Name = "backuptape"; Job = "backuptape" },
			@{ Name = "backupendpoint"; Job = "backupendpoint" },
			@{ Name = "backupvmbyjob"; Job = "backupvmbyjob" },
			@{ Name = "backupsyncvmbyjob"; Job = "backupsyncvmbyjob" },
			@{ Name = "backuptaskswithretry"; Job = "backuptaskswithretry" }
		)
		
		$beforeTime = Get-Date
		$missingFiles = @()
		foreach ($file in $expectedFiles) {
			$filePath = Join-Path $pathxml "$($file.Name).xml"
			if (-not (Test-Path $filePath)) {
				$missingFiles += $file.Name
				Write-Warning "XML file '$($file.Name).xml' was not created"
			} else {
				$fileInfo = Get-Item $filePath
				# Check if file was updated in the last 2 minutes (should be recent)
				$timeSinceUpdate = (Get-Date) - $fileInfo.LastWriteTime
				if ($timeSinceUpdate.TotalMinutes -gt 2) {
					Write-Warning "XML file '$($file.Name).xml' was not updated in this run (last updated: $($fileInfo.LastWriteTime))"
				}
			}
		}
		
		if ($missingFiles.Count -gt 0) {
			Write-Error "The following XML files were not created: $($missingFiles -join ', ')"
		}
		
		# Phase 3: Clean up all jobs (completed and failed) in single operation
		Get-Job | Remove-Job -ErrorAction SilentlyContinue
		
		# Output 1 to indicate success (Zabbix expects a return value)
		Write-Output "1"
	}
	
	"ResultBackup"  {
		$xml = ImportXml -item backuptaskswithretry
		$query1 = $xml | Where-Object { $_.jobId -like "$ID" } | Sort-Object JobStart -Descending | Select-Object -First 1
		$query2 = $query1.JobResult
		if (!$query2.value)
		{
			write-output "4" # If empty Send 4 : First Backup (or no history)
		}
		else
		{
			$query3 = $query2.value
			$query4 = "$query3" | veeam-replace
			write-output "$query4"
		}
	}
	
	"ResultBackupSync"  {
		$xml = ImportXml -item backupjob | Where-Object { $_.Id -like $ID }
		$result = veeam-backuptask-unique -ID $xml.name -jobtype jobname
		$query = $result | Measure-Object
		$count = $query.count
		$success = ($Result.Status | Where-Object { $_.Value -like "*Success*" }).count
		$warning = ($Result.Status | Where-Object { $_.Value -like "*Warning*" }).count
		$failed = ($Result.Status | Where-Object { $_.Value -like "*Failed*" }).count
		$pending = ($Result.Status | Where-Object { $_.Value -like "*Pending*" }).count
		$InProgress = ($Result.Status | Where-Object { $_.Value -like "*InProgress*" }).count
		if ($count -eq $success) { write-output "2" }
		else
		{
			if ($failed -gt 0) { write-output "0" }
			else
			{
				if ($warning -gt 0) { write-output "1" }
				else
				{
					
					if ($InProgress -gt 0) { write-output "5" }
					else
					{
						if ($pending -gt 0)
						{
							$xml2 = ImportXml -item backupsession
							$query1 = $xml2 | Where-Object { $_.jobId -like "*$ID*" } | Sort-Object creationtime -Descending | Select-Object -First 2 | Select-Object -Index 1
							if (!$query1.Result.Value) { write-output "4" }
							else
							{
								$query2 = $query1.Result.Value | veeam-replace
								write-output "$query2"
							}
						}
					}
				}
			}
		}
	}
	
	"ResultTape"  {
		if (!$ID)
		{
			write-output "-- ERROR --   Switch 'ResultTape' need ID of the Veeam task"
			write-output ""
			write-output "Example : ./zabbix_vbr_job.ps1 ResultTape 'c333cedf-db4a-44ed-8623-17633300d7fe'"
		}
		else
		{
			$xml1 = ImportXml -item backuptape
			$query = $xml1 | Where-Object { $_.Id -like "*$ID*" } | Sort-Object creationtime -Descending | Select-Object -First 1
			$query2 = $query.LastResult.Value
			if (!$query2)
			{
				# Retrieve version veeam
				$corePath = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\" -Name "CorePath"
				$depDLLPath = Join-Path -Path $corePath.CorePath -ChildPath "Packages\VeeamDeploymentDll.dll" -Resolve
				$file = Get-Item -Path $depDLLPath
				$version = $file.VersionInfo.ProductVersion
				if ($version -lt "8")
				{
					$query = Get-VBRTapeJob | Where-Object { $_.Id -like "*$ID*" }
					$query1 = $query.GetLastResult()
					$query2 = "$query1" | veeam-replace
					write-output "$query2"
				}
				else
				{
					write-output "4"
				}
			}
			else
			{
				if (($query.LastState.Value -like "WaitingTape") -and ($query2 -like "None"))
				{
					write-output "1"
				}
				else
				{
					$query3 = $query2 | veeam-replace
					write-output "$query3"
				}
			}
		}
	}
	
	"ResultEndpoint"  {
		if (!$ID)
		{
			write-output "-- ERROR --   Switch 'ResultEndpoint' need ID of the Veeam Endpoint Task"
			write-output ""
			write-output "Example : ./zabbix_vbr_job.ps1 ResultEndpoint 'c333cedf-db4a-44ed-8623-17633300d7fe'"
		}
		else
		{
			$xml3 = ImportXml -item backupendpoint
			$query = $xml3 | Where-Object { $_.Id -like "*$ID*" }
			$query1 = $query | Where-Object { $_.Id -eq $query.Id } | Sort-Object creationtime -Descending | Select-Object -First 1
			$query2 = $query1.LastResult
			# If empty Send 4 : First Backup (or no history)
			if (!$query2)
			{
				write-output "4"
			}
			else
			{
				$query4 = $query2.value
				$query3 = $query4 | veeam-replace
				write-output "$query3"
			}
		}
	}
	
	"ResultReplica"  {
		$xml = ImportXml -item backupsession
		$query1 = $xml | Where-Object { $_.jobId -like "$ID" } | Sort-Object creationtime -Descending | Select-Object -First 1
		$query2 = $query1.Result
		if (!$query2.value)
		{
			write-output "4" # If empty Send 4 : First Backup (or no history)
		}
		else
		{
			$query3 = $query2.value
			$query4 = "$query3" | veeam-replace
			write-output "$query4"
		}
	}
	
	"VmResultBackup" {
		$query = veeam-backuptask-unique -ID $ID0 -jobtype jobname
		$result = $query | Where-Object { $_.Name -like "$ID" }
		if (!$result)
		{
			write-output "4" # If empty Send 4 : First Backup (or no history)
		}
		else
		{
			$query3 = $Result.Status.Value
			$query4 = $query3 | veeam-replace
			[string]$query4
		}
	}
	
	"VmResultBackupSync" {
		$query = veeam-backuptask-unique -ID $ID0 -jobtype jobname
		$result = $query | Where-Object { $_.Name -like "$ID" }
		if (!$result)
		{
			write-output "4" # If empty Send 4 : First Backup (or no history)
		}
		else
		{
			$query3 = $Result.Status.Value
			$query4 = $query3 | veeam-replace
			[string]$query4
		}
	}
	"RepoCapacity" {
		$query = Get-CimInstance -Class Repository -ComputerName $env:COMPUTERNAME -Namespace ROOT\VeeamBS -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "$ID" }
		$query | Select-Object -ExpandProperty Capacity
	}
	
	"RepoFree" {
		$query = Get-CimInstance -Class Repository -ComputerName $env:COMPUTERNAME -Namespace ROOT\VeeamBS -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "$ID" }
		$query | Select-Object -ExpandProperty FreeSpace
	}
	
	"RunStatus" {
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.Id -like "*$ID*" }
		if ($query.IsRunning) { return "1" }
		else { return "0" }
	}
	
	"IncludedSize"{
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.Id -like "*$ID*" }
		[string]$query.Info.IncludedSize
	}
	
	"ExcludedSize"{
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.Id -like "*$ID*" }
		[string]$query.Info.ExcludedSize
	}
	
	"JobsCount" {
		$xml1 = ImportXml -item backupjob | Measure-Object
		[string]$xml1.Count
	}
	
	"VmCount" {
		$result = veeam-backuptask-unique -ID $ID -jobtype jobname | Measure-Object
		[string]$result.count
	}
	
	"VmCountResultBackup" {
		$query = veeam-backuptask-unique -ID $ID -jobtype jobname
		$result = $query | Where-Object { $_.Status -like $ID0 } | Measure-Object
		[string]$result.count
	}
	
	"VmCountResultBackupSync" {
		$query = veeam-backuptask-unique -ID $ID -jobtype jobname
		$result = $query | Where-Object { $_.Status -like $ID0 } | Measure-Object
		[string]$result.count
	}
	
	"Type" {
		$xml1 = ImportXml -item backupbackup
		if (!$xml1) { $xml1 = ImportXml -item backupsession }
		# Get-VBRBackup objects have JobId nested in Info property, Get-VBRBackupSession has JobId directly
		if ($xml1 -is [Array]) {
			$query = $xml1 | Where-Object { 
				if ($_.Info -and $_.Info.JobId) { 
					$_.Info.JobId.ToString() -like "$ID" 
				} else { 
					$_.JobId -like "$ID" 
				}
			} | Select-Object -First 1
		} else {
			if ($xml1 -and $xml1.Info -and $xml1.Info.JobId -and $xml1.Info.JobId.ToString() -like "$ID") {
				$query = $xml1
			} elseif ($xml1 -and $xml1.JobId -and $xml1.JobId -like "$ID") {
				$query = $xml1
			} else {
				$query = $null
			}
		}
		if ($query) {
			if ($query.Info -and $query.Info.JobType) {
				[string]$query.Info.JobType
			} elseif ($query.JobType) {
				[string]$query.JobType
			} else {
				[string]$query.AttachedJobType
			}
		} else {
			Write-Output ""
		}
	}
	
	"LastRunTime" {
		# LastRunTime returns the Unix timestamp of when the backup job last completed/finished
		# This is the EndTime of the most recent completed backup session
		# Use case in Zabbix: 
		#   - SLA monitoring: Calculate time since last successful backup
		#   - Alerting: Trigger if backup hasn't completed in X hours/days
		#   - Backup frequency tracking: Monitor backup schedule compliance
		# Use backupsession.xml to get the most recent completed session's EndTime
		# Do not fallback to backupbackup.xml - better to return 0 than wrong values
		$xml2 = ImportXml -item backupsession
		$lastPointTime = $null
		
		if ($xml2) {
			$sessionArray = @($xml2)
			if ($sessionArray.Count -gt 0) {
				# Get the most recent completed session sorted by EndTime (when job finished)
				# Filter for sessions with EndTime (completed sessions) - check for non-null EndTime
				$sessionQuery = $sessionArray | Where-Object { 
					$_.JobId -like "*$ID*" -and $null -ne $_.EndTime -and $_.EndTime -ne [DateTime]::MinValue
				} | Sort-Object EndTime -Descending | Select-Object -First 1
				# Use EndTime (when job finished) - this is the "Last End Time"
				if ($sessionQuery -and $sessionQuery.EndTime -and $sessionQuery.EndTime -ne [DateTime]::MinValue) {
					$lastPointTime = $sessionQuery.EndTime
				}
			}
		}
		if ($lastPointTime) {
			# Handle DateTime object or string
			if ($lastPointTime -is [DateTime]) {
				$dateTime = $lastPointTime
			} else {
				[string]$query1 = $lastPointTime
				if ([string]::IsNullOrWhiteSpace($query1)) {
					Write-Output "0"
					return
				}
				$result1 = $nextdate, $nexttime = $query1.Split(" ")
				if ($result1.Count -ge 2) {
					$newdateString = "$($nextdate -replace "(\d{2})-(\d{2})", "`$2-`$1") $nexttime"
					try {
						$dateTime = [DateTime]::Parse($newdateString)
					} catch {
						Write-Output "0"
						return
					}
				} else {
					Write-Output "0"
					return
				}
			}
			$epoch = [DateTime]::ParseExact("1970-01-01 00:00:00", "yyyy-MM-dd HH:mm:ss", $null).ToUniversalTime()
			$result2 = [Math]::Floor((New-TimeSpan -Start $epoch -End $dateTime.ToUniversalTime()).TotalSeconds)
			# Return as numeric value (not string) and ensure non-negative
			if ($result2 -lt 0) {
				Write-Output "0"
			} else {
				Write-Output $result2
			}
		} else {
			Write-Output "0"
		}
	}
	
	"LastEndTime" {
		# LastEndTime returns the backup metadata update time (MetaUpdateTime from backupbackup.xml)
		# This represents when the backup chain metadata was last modified/updated
		# Use case in Zabbix: Monitor backup chain activity and metadata freshness
		# Note: This is different from LastRunTime - LastEndTime tracks metadata updates,
		#       while LastRunTime tracks actual job completion times
		$xml1 = ImportXml -item backupbackup
		if (!$xml1) {
			Write-Output "0"
			return
		}
		# Get-VBRBackup objects have JobId nested in Info property
		# Handle both array and single object cases
		$query = $null
		if ($xml1 -is [Array]) {
			$query = $xml1 | Where-Object { 
				if ($_.Info -and $_.Info.JobId) { 
					$_.Info.JobId.ToString() -like "*$ID*" 
				}
			} | Select-Object -First 1
		} else {
			if ($xml1.Info -and $xml1.Info.JobId -and $xml1.Info.JobId.ToString() -like "*$ID*") {
				$query = $xml1
			}
		}
		if ($query -and $query.Info -and $query.Info.MetaUpdateTime) {
			$metaUpdateTime = $query.Info.MetaUpdateTime
			# Handle DateTime object or string
			if ($metaUpdateTime -is [DateTime]) {
				$dateTime = $metaUpdateTime
			} else {
				[string]$query1 = $metaUpdateTime
				if ([string]::IsNullOrWhiteSpace($query1)) {
					Write-Output "0"
					return
				}
				$result1 = $nextdate, $nexttime = $query1.Split(" ")
				if ($result1.Count -ge 2) {
					$newdateString = "$($nextdate -replace "(\d{2})-(\d{2})", "`$2-`$1") $nexttime"
					try {
						$dateTime = [DateTime]::Parse($newdateString)
					} catch {
						Write-Output "0"
						return
					}
				} else {
					Write-Output "0"
					return
				}
			}
			$epoch = [DateTime]::ParseExact("1970-01-01 00:00:00", "yyyy-MM-dd HH:mm:ss", $null).ToUniversalTime()
			$result2 = [Math]::Floor((New-TimeSpan -Start $epoch -End $dateTime.ToUniversalTime()).TotalSeconds)
			# Return as numeric value (not string) and ensure non-negative
			if ($result2 -lt 0) {
				Write-Output "0"
			} else {
				Write-Output $result2
			}
		} else {
			Write-Output "0"
		}
	}
	
	"NextRunTime" {
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.Id -like "*$ID*" }
		$query1 = $query.ScheduleOptions
		$result = $query1.NextRun
		if (!$result)
		{
			$result = $query | Select-Object name, @{ N = 'RunAfter'; E = { ($xml1 | Where-Object { $_.id -eq $query.info.ParentScheduleId }).Name } }
			$result1 = 'After Job' + " : " + $result.RunAfter
			[string]$result1
		}
		else
		{
			[string]$result
		}
	}
	
	"RunningJob" {
		$xml1 = ImportXml -item backupjob
		$query = $xml1 | Where-Object { $_.isCompleted -eq $false } | Measure-Object
		if ($query)
		{
			[string]$query.Count
		}
		else
		{
			return "0"
		}
	}
	default
	{
		write-output "-- ERROR -- : Need an option !"
	}
}
