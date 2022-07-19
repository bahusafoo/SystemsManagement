#####################################
# Maintain-IISLogs.ps1
# Author: Sean Huggans
# Script Date: 18.12.24.1
#####################################
# This script is meant to run as system in a scheduled task set to run as often as you like.

$LogDir = "C:\inetpub\logs"
$LogPath = "$($LogDir)\Log-Maintenance.log"
$ArchivedLogRetentionPeriod = 5 # In Days
 
###################
# Functions
###################
function Log-Action ($Message) {
    if (!(test-path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Confirm:$false -Force | Out-Null
    }
    "[ $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File -FilePath $LogPath -Force -Append
}
 
function Maintain-Logs {
    Remove-Item -Path $LogPath -ErrorAction SilentlyContinue -Force -confirm:$false
    Log-Action "Log Maintenance - Beginning Log Maintenance!"
    # If any Archived Logs are older than Retention Period days
    $CutOffNumber = "-$($ArchivedLogRetentionPeriod)"
    $Cutoff = (Get-Date).AddDays($CutOffNumber)
    [array]$ArchivedLogs = Get-ChildItem -Path $LogDir -Recurse | Where-Object {$_.Extension -eq ".log"}
    if ($ArchivedLogs.Count -gt 0) {
        foreach ($ArchivedLog in $ArchivedLogs) {
            if ($ArchivedLog.LastWriteTime -lt $Cutoff) {
                try {
                    remove-item -Path $ArchivedLog.FullName -Confirm:$False -force -erroraction Stop | Out-Null
                    Log-Action "Log Maintenance - Deleted $($ArchivedLog.Name) due to exceeding the retention period of $($ArchivedLogRetentionPeriod) days."
                } catch {
                    Log-Action "Log Maintenance - Failed to delete $($ArchivedLog.Name).  This file needs to be deleted (manually if needed) due to exceeding the retention period of $($ArchivedLogRetentionPeriod) days."
                }
            } else {
                Log-Action "Log Maintenance - $($ArchivedLog.Name) will be retained as its age is within the retention period of $($ArchivedLogRetentionPeriod) days."
            }
        }
    } else {
        Log-Action "Log Maintenance - No old Logs Exist to Evaluate."
    }
    Log-Action "Log Maintenance - Log Maintenance Completed."
}
 
Maintain-Logs