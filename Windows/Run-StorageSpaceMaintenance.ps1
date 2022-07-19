#####################################################################################################
# Run-StorageSpaceMaintenance.ps1
# Script Author: Sean Huggans
$ScriptVersion = "22.4.22.5"
#####################################################################################################
# Script Variables
###################################
$Script:ScriptVersion = "22.4.21.2"
$Script:RemoveInactiveUserProfiles = $true
$Script:MaxProfileAge = 30 # Max user profile age, in days
$Script:CleanCCMCache = $true
$Script:MaxCCMCacheAge = 30 # Max CCMCache content age, in days
$Script:LogFile = "StorageSpaceMaintenance.log"
$Script:LogDir = "C:\Windows\Logs\Maintenance\$($AppName)"
$Script:LogPath = "$($LogDir)\$($LogFile)"
$Script:PreCleanCDriveFreeSpace = 0
$Script:PostCleanCDriveFreeSpace = 0
 
###################################
# Script Functions
###################################
 
function Log-Action ($Message, $RecordDateTime)
{
    ################################
    # Function Version 19.6.15.1
    # Function by Sean Huggans
    ################################
	New-Item -ItemType directory -Path $Script:LogDir -Confirm:$false -Force | out-null
    if (($RecordDateTime -eq $false) -or ($RecordDateTime -eq "no")) {
        $Message | Out-File $Script:LogPath -Append
    } else {
        "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File $Script:LogPath -Append
    }
}
 
function Remove-InactiveUserProfiles ($MaxAge) {
    if ($MaxAge) { 
        Log-Action -Message "Checking for and deleting user profiles that have not been used for ($($Script:MaxProfileAge)) days:"
        [array]$InactiveUserProfiles = Get-WmiObject -class Win32_UserProfile | Where-Object {(!$_.Special) -and ($_.ConvertToDateTime($_.LastUseTime) -lt (Get-Date).AddDays(-$($MaxAge)) -and ($_.LocalPath -notlike "*support*"))}
        if ($InactiveUserProfiles.count -gt 0) {
            foreach ($InactiveUserProfile in $InactiveUserProfiles) {
                $ProfileLogLine =  "$($InactiveUserProfile.LocalPath.split("\")[$($InactiveUserProfile.LocalPath.split("\")).count - 1]),$($InactiveUserProfile.ConvertToDateTime($InactiveUserProfile.LastUseTime))"
                try {
                    $InactiveUserProfile | Remove-WmiObject -ErrorAction Stop
                    Log-Action -Message " - Inactive Profile: $($ProfileLogLine.Split(',')[0]): Success!"
                } catch {
                    Log-Action -Message " - Inactive Profile: $($ProfileLogLine.Split(',')[0]): Failed!"
                }
            }
            Log-Action -Message "Finish deleting inactive user profiles, see results above."
        } else {
            Log-Action -Message "No profiles were found that were inactive in the last ($($Script:MaxProfileAge)) days."
        }
    } else {
        Log-Action -Message "MaxAge parameter was not specified, Inactive User Profile cleanup will be skipped!"
    }
}
 
function Clean-CCMCache ($DaysOldThreshhold) {
    Log-Action -Message "Performing CCMCache Maintenance:"		
	$SCCMCacheClearedSpace = 0
	$RemovedSCCMCachedItems = 0			
	Try
	{
		[array]$NonPersistentCacheItems = Get-WmiObject -Namespace root\ccm\SoftMgmtAgent -Query 'SELECT * FROM CacheInfoEx WHERE PersistInCache != 1' -ErrorAction Stop
		if ($DaysOldThreshhold -gt 0)
		{
			Log-Action -Message "Content Cache Removal has been filtered to any cache with a last referenced date older than ($($DaysOldThreshhold)) days."
			[array]$OldNonPersistentCacheItems = $NonPersistentCacheItems | where-object { $_.LastReferenced -le $(get-date).AddDays(- $DaysOldThreshhold).ToString("yyyyMMddhhmmss") }
		}
		else
		{
			Log-Action -Message "Content Cache Removal has been run without an explicitely defined last reference filter.  All non-persistent content will be removed."
			[array]$OldNonPersistentCacheItems = $NonPersistentCacheItems
		}
		Log-Action -Message "Flagged $($OldNonPersistentCacheItems.count) cached content items for deletion.  Removing them now..."
		foreach ($OldNonPersistentCacheItem in $OldNonPersistentCacheItems)
		{
			try
			{
				Remove-Item -Path $($OldNonPersistentCacheItem.Location) -Force -Recurse -ErrorAction Stop
				$PotentialClearedSpace = $OldNonPersistentCacheItem.ContentSize
				if (!(Test-Path $($OldNonPersistentCacheItem.Location)))
				{
 
					#$OldNonPersistentCacheItem.Delete()
					$RemovedSCCMCachedItems += 1
					$SCCMCacheClearedSpace += $PotentialClearedSpace
					Log-Action -Message "Removed content for cached item with the content ID '$($OldNonPersistentCacheItem.ContentId)' at path '$($OldNonPersistentCacheItem.Location)' ($($OldNonPersistentCacheItem.LastReferenced))."
				}
				else
				{
					Log-Action -Message "Content for cached item with the content ID '$($OldNonPersistentCacheItem.ContentId)' at path '$($OldNonPersistentCacheItem.Location)' is still present.  Checking back later..."
				}
			}
			catch
			{
				Log-Action -Message "Error removing content with content ID '$($OldNonPersistentCacheItem.ContentId)' at path '$($OldNonPersistentCacheItem.Location)'."
			}
		}
		#Cycle back through and remove any item from WMI that isn't locally present
		[array]$NonPersistentCacheItems = Get-WmiObject -Namespace root\ccm\SoftMgmtAgent -Query 'SELECT * FROM CacheInfoEx WHERE PersistInCache != 1' -ErrorAction Stop
		[array]$OldNonPersistentCacheItems = $NonPersistentCacheItems
		foreach ($OldNonPersistentCacheItem in $OldNonPersistentCacheItems)
		{
			if (!(Test-Path $($OldNonPersistentCacheItem.Location)))
			{
				$OldNonPersistentCacheItem.Delete()
				"[ $(Get-Date -Format 'yyyy.MM.dd hh:mm:ss') ] WMI entry for cached item with the content ID '$($OldNonPersistentCacheItem.ContentId)' at path '$($OldNonPersistentCacheItem.Location)' has been deleted as no local content is actually present." | Out-File "C:\Temp\SHCRMIT\Logs\DiskSpaceCleanup.log" -Append
			}
		}
		Log-Action -Message "$($RemovedSCCMCachedItems)/$($NonPersistentCacheItems.Count) non-persistent cached items were more than $($DaysOldThreshhold) days old and have been removed."
		Log-Action -Message "$([math]::round($SCCMCacheClearedSpace/1MB, 2)) GB of SCCM Cache space has been cleared up."
 
		# Remove rogue content
		Log-Action -Message "Checking ccmcache content for rogue items..."
		if (test-path "C:\Windows\ccmcache")
		{
			[array]$CCMCacheItems = Get-ChildItem "C:\Windows\ccmcache"
			[array]$AllCacheItems = Get-WmiObject -Namespace root\ccm\SoftMgmtAgent -Query 'SELECT * FROM CacheInfoEx' -ErrorAction Stop
			foreach ($CCMCacheItem in $CCMCacheItems)
			{
				if ($CCMCacheItem.Name -ne "skpswi.dat")
				{
					Log-Action -Message "Checking $($CCMCacheItem.FullName)..."
					$LegitItem = $false
					foreach ($CacheItem in $AllCacheItems)
					{
						if ($CacheItem.Location -like "*$($CCMCacheItem.FullName)*")
						{
							$LegitItem = $true
						}
					}
					if ($LegitItem -ne $true)
					{
						try
						{
							Log-Action -Message "WARNING!  Found rogue content!  Deleting $($CCMCacheItem.FullName)."
							remove-item $CCMCacheItem.FullName -Recurse -erroraction Stop
							Log-Action -Message " - SUCCESS!"
						}
						catch
						{
							Log-Action -Message " -ERROR!  Failed attempt to delete $($CCMCacheItem.FullName)!"
						}
					}
					else
					{
						Log-Action -Message "NOTICE!  $($CCMCacheItem.FullName) Is Legitimate SCCM content.  Leaving it alone."
					}
				}
				else
				{
					Log-Action -Message "NOTICE!  Skipping skpswi.dat..."
				}
			}
		}
	}
	Catch
	{
		Log-Action -Message "Warning! SCCM Client not Installed.  Skipping SCCM Content Cache Maintenance."
	}
    Log-Action -Message "Finish ccmcache maintenance, see results above."
}
 
 
function Run-DiskCleanup {
    Log-Action -Message "Starting CleanMgr (Disk Cleanup) process.  Planting sageset values..."
    $strKeyPath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    $strValueName = "StateFlags0065"
    $subkeys      = Get-ChildItem -Path $strKeyPath -Name
 
    ForEach($subkey in $subkeys){
        $null = New-ItemProperty  -Path $strKeyPath\$subkey -Name $strValueName -PropertyType DWord -Value 2 -ea SilentlyContinue -wa SilentlyContinue
    }
 
    Log-Action -Message "calling CleanMgr (Disk Cleanup) exe with sageset profile."
    Get-Process -Name CleanMgr -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $CleanMgrProc = Start-Process cleanmgr -ArgumentList "/sagerun:65" -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 
    # Start Check Loop
    [int]$RamUsedSameCount = 0
    [int]$RamUsedBase = 0
    [int]$RamUsedLast = 0
    Do {
        Start-Sleep -Seconds 5
        $RamUsedLast = $(Get-WMIObject -class Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.IDprocess -eq $CleanMgrProc.Id }).WorkingSetPrivate / 1kb
        if ($RamUsedLast -eq $RamUsedBase) {
            $RamUsedSameCount += 1
            # Log-Action -Message "Same - $($RamUsedLast) (Count: $($RamUsedSameCount))"
            Log-Action -Message " - Validating CleanMgr.exe is finished running..."
        } else {
            $RamUsedBase = $RamUsedLast
            # Log-Action -Message "Reset - $($RamUsedLast)"
            Log-Action -Message " - CleanMgr.exe still working, waiting for the cleanup to finish..."
        }
 
    } until ($RamUsedSameCount -gt 15) 
    Get-Process -Name CleanMgr -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Log-Action -Message "cleanmgr.exe exited, removing sageset values..."
    ForEach($subkey in $subkeys){
        $null = Remove-ItemProperty -Path $strKeyPath\$subkey -Name $strValueName -ea SilentlyContinue  -wa SilentlyContinue
    }
 
    Log-Action -Message "CleanMgr Exited."
}
 
 
 
 
###################################
# Script Execution Logic
###################################
 
Log-Action -Message "---------------------------------------------------------------------------------------" -RecordDateTime $false
Log-Action -Message "- Running storage space maintenance | v$($Script:ScriptVersion) | $(get-date -Format 'yyyy.MM.dd HH:mm:ss')" -RecordDateTime $false
Log-Action -Message "---------------------------------------------------------------------------------------" -RecordDateTime $false
 
# Track current free space
Log-Action -Message "Checking Disk Space (pre-Disk Cleanup)"
$DiskInfo = Get-WmiObject Win32_DiskDrive | % {
$disk = $_
$partitions = "ASSOCIATORS OF " +
"{Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} " +
"WHERE AssocClass = Win32_DiskDriveToDiskPartition"
	Get-WmiObject -Query $partitions | % {
		$partition = $_
		$drives = "ASSOCIATORS OF " +
		"{Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} " +
		"WHERE AssocClass = Win32_LogicalDiskToPartition"
		Get-WmiObject -Query $drives | % {
			New-Object -Type PSCustomObject -Property @{
				Disk = $disk.DeviceID
				DiskSize = $disk.Size
				DiskModel = $disk.Model
				Partition = $partition.Name
				RawSize = $partition.Size
				DriveLetter = $_.DeviceID
				VolumeName = $_.VolumeName
				Size = $_.Size
				FreeSpace = $_.FreeSpace
			}
		}
	}
}
foreach ($Disk in $DiskInfo) {
    Log-Action -Message " - Disk $($Disk.DriveLetter) - $([math]::round($($Disk.FreeSpace / 1GB), 2)) Free"
    if ($Disk.DriveLetter -eq "C:") {
        $Script:PreCleanCDriveFreeSpace = $([math]::round($($Disk.FreeSpace / 1GB), 2))
    }
}
 
if ($Script:RemoveInactiveUserProfiles -eq $true) {
    Remove-InactiveUserProfiles -MaxAge $Script:MaxProfileAge
}
 
if ($Script:CleanCCMCache -eq $true) {
    Clean-CCMCache -DaysOldThreshhold $Script:MaxCCMCacheAge
}
 
Run-DiskCleanup
 
# Track current free space
Log-Action -Message "Checking Disk Space (post-Disk Cleanup)"
$DiskInfo = Get-WmiObject Win32_DiskDrive | % {
$disk = $_
$partitions = "ASSOCIATORS OF " +
"{Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} " +
"WHERE AssocClass = Win32_DiskDriveToDiskPartition"
	Get-WmiObject -Query $partitions | % {
		$partition = $_
		$drives = "ASSOCIATORS OF " +
		"{Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} " +
		"WHERE AssocClass = Win32_LogicalDiskToPartition"
		Get-WmiObject -Query $drives | % {
			New-Object -Type PSCustomObject -Property @{
				Disk = $disk.DeviceID
				DiskSize = $disk.Size
				DiskModel = $disk.Model
				Partition = $partition.Name
				RawSize = $partition.Size
				DriveLetter = $_.DeviceID
				VolumeName = $_.VolumeName
				Size = $_.Size
				FreeSpace = $_.FreeSpace
			}
		}
	}
}
foreach ($Disk in $DiskInfo) {
    Log-Action -Message " - Disk $($Disk.DriveLetter) - $([math]::round($($Disk.FreeSpace / 1GB), 2)) Free"
    if ($Disk.DriveLetter -eq "C:") {
        $Script:PostCleanCDriveFreeSpace = $([math]::round($($Disk.FreeSpace / 1GB), 2))
    }
}
 
$Script:SpaceDifference = $Script:PostCleanCDriveFreeSpace - $Script:PreCleanCDriveFreeSpace
 
Log-Action -Message "Storage Space Maintenance v$($Script:ScriptVersion) Finished."
 
if ($Script:SpaceDifference -ge 0) {
    return "$($Script:SpaceDifference)GB was cleared."
} else {
    return "$($Script:SpaceDifference.ToString().Replace('-','')) more GB of space is taken up than before the cleanup was run."
}