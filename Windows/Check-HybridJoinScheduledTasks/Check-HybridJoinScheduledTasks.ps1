#########################################
# Check-HybridJoinScheduledTasks.ps1
$ScriptVersion = "25.7.27.1"
# This script is intended as a ConfigMgr Compliance Item
#########################################
# Variables
###################################
$LogFile = "Check-HybridJoinScheduledTasks.log"
$LogDir = "C:\Windows\Logs\Compliance"
$LogPath = "$($LogDir)\$($LogFile)"
[string[]]$CheckTasks = "Automatic-Device-Join", "Device-Sync", "Recovery-Check"

#########################################
# Functions
###################################

function Log-Action ($Message, $StampDateTime, $WriteHost)
{
    ################################
    # Function Version 19.5.11.4
    # Function by Sean Huggans
    ################################
	New-Item -ItemType directory -Path $LogDir -Confirm:$false -Force | out-null
    if (($StampDateTime -eq $false) -or ($StampDateTime -eq "no")) {
        $Message | Out-File $LogPath -Append
    } else {
	    "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') v$($ScriptVersion) ] $($Message)" | Out-File $LogPath -Append
    }
    if ($WriteHost -eq $true) {
        Write-Host $Message
    }
}

function Maintain-Log {
    Try {
        if ($(Get-Item -Path $LogPath).Length -gt 5120) {
            # Remove Previous Archived Log
            $ArchivedLogs = Get-ChildItem -Path $LogDir | Where-Object {(($_.Name -like "ARCHIVED-*") -and ($_.Extension -eq ".log"))}
            foreach ($ArchivedLog in $ArchivedLogs) {
                Remove-Item -Path $ArchivedLog.FullName -Force
                Log-Action -Message "Log Maintenance: Removed $($ArchivedLog.FullName)"
            }
            Rename-Item -Path $LogPath -NewName "ARCHIVED-$($LogFile.replace('.log',''))-$(Get-date -Format 'yyyyMMdd-HHmmss').log" -Force
            Log-Action -Message "The previous log was over 5120 in size and has been archived."
        }
    } catch {
        Log-Action "Error: Maintain Log Failed ($($PSItem.ToString()))."
    }
}

#########################################
# Execution Logic
###################################
Maintain-Log

Log-Action -Message "Starting Check..."
[bool]$AllChecked = $True
[bool]$AllEnabled = $True
foreach ($CheckTask in $CheckTasks) {
    Remove-Variable -Name "TaskObject" -Force -ErrorAction SilentlyContinue
    Try {
        $TaskObject = Get-ScheduledTask -TaskName $CheckTask -ErrorAction Stop
        if ($TaskObject.State -ne "Disabled") {
            Log-Action -Message "Scheduled Task is Enabled ($($CheckTask))."
        } else {
            Log-Action -Message "Warning: Scheduled Task is Disabled ($($CheckTask))."
            $AllEnabled = $False
        }
    } catch {
        Log-Action -Message "Error: Scheduled Task Not Found ($($CheckTask))."
        $AllChecked = $False
    }
}

if (($AllChecked -eq $True) -and ($AllEnabled -eq $True)) {
    Log-Action -Message "Check Result: Compliant"
    Log-Action -Message "Finished Check."
    Return $True
} else {
    Log-Action -Message "Check Result: Not Compliant"
    Log-Action -Message "Finished Check."
    Return $False
}