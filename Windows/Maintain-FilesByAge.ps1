###################################################################
# Maintain-FilesByAge.ps1
# Author(s): Sean Huggans
$ScriptVersion = "24.1.17.1"
###################################################################
# Variables
########################################
[string]$MaintenanceDirectory = "C:\DirectoryA\Monitored Directory" # Path of root directory containing files to maintain
[string]$MaintenanceExtension = "7z" # Extension of files (leave blank for "all"), do NOT include a .
[int]$MaxAgeDays = 365 # Max number of days to allow a file to exist in the configured maintenance directory before being deleted by this script
[bool]$LogSkippedFileHandling = $false # $true/$false - set to true to create log entries informing you that a file is newer than the configured max age and will be skipped from deletion (this will increase log data significantly depending on the number of files being maintained, recommended to leave this off unless needed)
[string]$LogFile = "Maintain-ArchivedApps.log" # Name of log file to output
[string]$LogDir = "C:\Maintenance\Logs" # Path of directory to output log file into
###################################
# No-touch Variables
###################################
[string]$LogPath = "$($LogDir)\$($LogFile)"
$FailedDeletionList = New-Object System.Collections.arraylist
[int]$DeletedCount = 0
########################################
# Functions
########################################

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
	    "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File $LogPath -Append
    }
    if ($WriteHost -eq $true) {
        Write-Host $Message
    }
}

function Maintain-Logs {
    if (Test-Path -Path $LogPath) {
        if (!(Test-Path -Path "$($LogDir)\Archived")) {
            New-Item -Path "$($LogDir)\Archived" -ItemType Directory -Force | Out-Null
        }
        # Truncate Log if over 5,000KB
        if ((Get-Item $LogPath).length -gt 5000kb) {
            $ArchiveStamp = "-Archived-$(get-date -Format "yyyyMMddhhmmss")"
            $ArchivedLogName = "$($LogDir)\Archived\$($LogFile.Replace('.log',''))$($ArchiveStamp).log"
            $TryCount = 5
            $Moved = $false
            do {
                try {
                    Move-Item -Path $LogPath -Destination $ArchivedLogName -Force -Confirm:$false -ErrorAction Stop
                    Log-Action -Message "This Log has been truncated.  Messages from the previous truncation can be found at $ArchivedLogName"
                    $Moved = $true
                } catch {
                    Write-Host $ArchivedLogName
                    Start-Sleep -Seconds 3
                }
                $TryCount -= 1
            } until (($TryCount -le 0) -or ($Moved -eq $true))
            Log-Action -Message "Log was rolled over due to the log being above threshold size."
        } else {
            Log-Action -Message "Log Maintenance Skipped (Log Size below threshold)..."
        }
    }  
    #TODO: Check for Logs Older than 4 weeks and delete them  
}

########################################
# Execution Logic
########################################
Maintain-Logs
Log-Action -Message "Maintenance of files within ""$($MaintenanceDirectory)"" is starting.  Files older than $($MaxAgeDays.ToString()) days will be deleted..."
# Get array of file objects within the maintained directory
if ($MaintenanceExtension.Trim() -ne "") {
    Log-Action -Message "Maintenance is filtered to files with the ""$($MaintenanceExtension.Trim().Replace('.',''))"" extension..."
    [array]$MaintainedFiles = Get-ChildItem -Path $MaintenanceDirectory -File | Where-Object {$_.Extension -eq ".$($MaintenanceExtension.Trim().Replace('.',''))"}
} else {
    Log-Action -Message "Maintenance is NOT filtered to any extension, all files will be included..."
    [array]$MaintainedFiles = Get-ChildItem -Path $MaintenanceDirectory -File
}

if ($MaintainedFiles.count -gt 0) {
    Log-Action -Message "Checking a total of $($MaintainedFiles.Count.ToString()) files..."
    # Loop through each file in the array
    foreach ($MaintainedFile in $MaintainedFiles) {
        # Check the file's last modified time to see if it's older than todays date minus the configured $MaxAgeDays value
        if ($(Get-Date -date $MaintainedFile.LastWriteTime) -lt $(Get-Date).AddDays(-$($MaxAgeDays))) {
            Try {
                Remove-Item -Path $MaintainedFile.FullName -Force -Confirm:$false -ErrorAction Stop
                $DeletedCount +=1
                Log-Action -Message " - $($MaintainedFile.Name) was deleted ($($($($(Get-Date) - $MaintainedFile.LastWriteTime).Days).ToString()) days old)."
            } catch {
                Log-Action -Message " - The file $($MaintainedFile.Name) is $($($($(Get-Date) - $MaintainedFile.LastWriteTime).Days).ToString()) is days old, however, there was error trying to delete the file."
                $FailedDeletionList.Add($MaintainedFile.Name) | Out-Null
            }
        } else {
            # If $LogSkippedFileHandling is enabled, create an entry for the skipped file
            if ($LogSkippedFileHandling -eq $true) {
                Log-Action -Message " - The file $($MaintainedFile.Name) is $($($($(Get-Date) - $MaintainedFile.LastWriteTime).Days).ToString()) is days old, which is newer than the maximum age value.  This file will not yet be deleted."
            }
        }
    }
    Log-Action -Message "Maintenance was finished.  A total of $($DeletedCount) files were deleted during this cycle."
} else {
    Log-Action -Message "Maintenance was finished.  No files were found to check."
}

# TODO: email report of deletion failures to systems management team (need to draw attention to the failures for investigation)