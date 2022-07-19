###############################################################################################################
# Correct-PendingContentOnSpecificDP.ps1
#
# This script will compare what the database knows for packages on a specific DP against what is actually in
# WMI and the Content library on that DP.  If variances are found it reports on those in that DPs log
# file.  Optionally, the script can be told to correct the variances it finds as well.
#
# Author: Sean Huggans
# Version: 2018.01.30
###############################################################################################################
 
param (
	$DPName,
	$SiteCode,
	$SiteServer,
	$LogPath,
	$FixBadPackages,
	$OutPutBadPackages,
	$FixObsoletePackages,
    $OutPutObsoletePackages
)
 
function Remove-PackageFromDPWMI ($DPName, $PackageID)
{
	$RemoveResult = Invoke-Command -ComputerName $DPName -ScriptBlock {
		param ($PackageID)
		$Result = $false
		try
		{
			Get-WmiObject -Namespace "ROOT\SCCMDP" -Class SMS_PackagesInContLib -Filter "PackageID = '$PackageID'" -ErrorAction Stop | Remove-WmiObject
			#Remove-WmiObject -Namespace "ROOT\SCCMDP" -Class SMS_PackagesInContLib1 -ErrorAction Stop -Confirm:$false | Where-Object {$_.PackageID -eq $PackageID}
			$Result = $true
		}
		catch
		{
			#nothing
		}
		return $Result
	} -ArgumentList $PackageID
	return $RemoveResult
}
 
function Remove-PackageFromContentLib ($DPName, $PackageID)
{
    Invoke-Command -ComputerName $DPName -ScriptBlock {
        param($PackageID)
        $RemovedINIs = new-object System.Collections.ArrayList
        $StorageVolumes = Get-Volume | Where-Object {(($_.DriveType -eq 'Fixed') -and ($_.DriveLetter))}
        foreach ($StorageVolume in $StorageVolumes) {
            Set-Location "$($StorageVolume.DriveLetter):"
            $ContentLibPath = "$($StorageVolume.DriveLetter):\SCCMContentLib\PkgLib"
            if (test-path -Path $ContentLibPath) {
                $PackageINI = "$($ContentLibPath)\$($PackageID).ini"
                if (Test-Path -path $PackageINI) {
                    try {
                        remove-item -Path $PackageINI -Force -Confirm:$false -ErrorAction Stop
                        $RemovedINIs.Add("$($PackageINI), Sucessfully Removed from PkgLib") | Out-Null
                    } catch {
                        $RemovedINIs.Add("$($PackageINI), Failed to Remove from PkgLib") | Out-Null
                    }
                }
            }
        }
        return $RemovedINIs
    } -ArgumentList $PackageID
}
 
function Invoke-SQL
{
    ########################################
    # Function Provided by Chris Magnuson
    ########################################
	param (
		[string]$dataSource,
		[string]$database,
		[string]$sqlCommand = $(throw "Please specify a query.")
	)
 
	$connectionString = "Data Source=$dataSource; " +
	"Integrated Security=SSPI; " +
	"Initial Catalog=$database"
 
	$connection = new-object system.data.SqlClient.SQLConnection($connectionString)
	$command = new-object system.data.sqlclient.sqlcommand($sqlCommand, $connection)
	$connection.Open()
 
	$adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
	$dataset = New-Object System.Data.DataSet
	$adapter.Fill($dataSet) | Out-Null
 
	$connection.Close()
	$dataSet.Tables
 
}
 
Function Refresh-SpecificDP
{
	###################################
	# Function by Mike Laughlin
	###################################
	param ($packageID,
		$dpName)
	$dpFound = $false
	If ($packageID.Length -ne 8)
	{
		Throw "Invalid package"
	}
	$distPoints = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\Site_$($siteCode)" -Query "Select * From SMS_DistributionPoint WHERE PackageID='$packageID'" -ErrorAction Stop
	ForEach ($dp In $distPoints)
	{
		If ((($dp.ServerNALPath).ToUpper()).Contains($dpName.ToUpper()))
		{
			$dpFound = $true
 
			Try
			{
				$dp.RefreshNow = $true
				$dp.Put() | Out-Null
				return $true
			}
			Catch [Exception]
			{
				return $false
			}
		}
	}
	If ($dpFound -eq $false)
	{
		return $false
	}
}
 
if (($DPName -ne $null) -and ($SiteCode -ne $null) -and ($SiteServer -ne $null))
{
 
	#Default these parameters if not provided
	if ($LogPath -eq $NULL)
	{
		$LogPath = "C:\Temp\Maintenance"
	}
	if ($OutPutBadPackages -eq $null)
	{
		$OutPutBadPackages = $false
	}
	if ($FixBadPackages -eq $NULL)
	{
		$FixBadPackages = $false
	}
	else
	{
		switch ($FixBadPackages)
		{
			"True" {
				$FixBadPackages = $true
			}
			"False" {
				$FixBadPackages = $false
			}
			"Yes" {
				$FixBadPackages = $true
			}
			"No" {
				$FixBadPackages = $false
			}
			default
			{
				$FixBadPackages = $false
			}
		}
	}
    if ($OutPutBadPackages -eq $null) {
        $OutPutBadPackages = $false
    }
	if ($FixObsoletePackages -eq $NULL)
	{
		$FixObsoletePackages = $false
	}
	else
	{
		switch ($FixObsoletePackages)
		{
			"True" {
				$FixObsoletePackages = $true
			}
			"False" {
				$FixObsoletePackages = $false
			}
			"Yes" {
				$FixObsoletePackages = $true
			}
			"No" {
				$FixObsoletePackages = $false
			}
			default
			{
				$FixObsoletePackages = $false
			}
		}
	}
    if ($OutPutObsoletePackages -eq $null) {
        $OutPutObsoletePackages = $false
    }
 
	$LogFile = "PendingContentFix-$($DPName).log"
 
 
	new-item -ItemType Directory -Path $LogPath -force -Confirm:$false -ErrorAction SilentlyContinue | out-null
 
	Write-Host "Script is running, progress can be monitored via the log at $($LogPath)\$($LogFile).  Once you run this script, do not run it against the same DP until distribution has finished."
    "[ $(Get-Date -Format 'yyyy.MM.dd hh:mm:ss') ] Script Started" | Out-File "$($LogPath)\$($LogFile)" -Append
	"Running comparisons on DP '$($DPName)'..." | Out-File "$($LogPath)\$($LogFile)" -Append
	[array]$AllPackages = Invoke-SQL -dataSource $SiteServer -database "CM_$($SiteCode)" -sqlCommand "select * from pkgstatus where pkgserver like '%$($DPName)%';"
	[array]$TotalPackages = $AllPackages.ID
	"Total Packages: $($TotalPackages.Count)" | Out-File "$($LogPath)\$($LogFile)" -Append
 
	[array]$PackagesInLib = Invoke-Command -ComputerName $DPName -ScriptBlock {
		$FilteredList = New-Object System.Collections.ArrayList
		try
		{
			[array]$PKGsInLib = $(Get-ChildItem -Path "C:\SCCMContentLib\PkgLib" -ErrorAction Stop | Where-Object { $_.Extension -eq ".ini" }).Name
		}
		catch
		{
			[array]$PKGsInLib = $(Get-ChildItem -Path "D:\SCCMContentLib\PkgLib" | Where-Object { $_.Extension -eq ".ini" }).Name
		}
		foreach ($PKG in $PKGsInLib)
		{
			$FilteredList.Add($PKG.toupper().replace(".INI", "")) | out-null
		}
		return $FilteredList
	}
	"Packages in Library: $($PackagesInLib.Count)" | Out-File "$($LogPath)\$($LogFile)" -Append
 
	[array]$PackagesInWMI = Invoke-Command -ComputerName $DPName -ScriptBlock {
		[array]$PKGsinWMI = Get-WmiObject –namespace root\sccmdp –class SMS_PackagesInContLib –Property PackageID
		return $PKGsinWMI.PackageID
	}
	"Packages in WMI: $($PackagesInWMI.Count)" | Out-File "$($LogPath)\$($LogFile)" -Append
 
	$GoodPackages = New-Object System.Collections.ArrayList
	foreach ($Package in $TotalPackages)
	{
		if (($PackagesInLib -contains $Package) -and ($PackagesInWMI -contains $Package))
		{
			$GoodPackages.Add($Package) | Out-Null
		}
	}
	"Good Packages: $($GoodPackages.Count)" | Out-File "$($LogPath)\$($LogFile)" -Append
 
	$BadPackages = New-Object System.Collections.ArrayList
	foreach ($Package in $TotalPackages)
	{
		if ($GoodPackages -notcontains $Package)
		{
			$BadPackages.Add($Package) | Out-Null
		}
	}
	"Bad Packages: $($BadPackages.Count)" | Out-File "$($LogPath)\$($LogFile)" -Append
 
	#Find Obsolete Packages
	$ObsoletePackages = New-Object System.Collections.ArrayList
	foreach ($Package in $PackagesInWMI)
	{
		if ($TotalPackages -notcontains $Package)
		{
			$ObsoletePackages.Add($Package) | Out-null
		}
	}
	foreach ($Package in $PackagesInLib)
	{
		if ($TotalPackages -notcontains $Package)
		{
			$ObsoletePackages.Add($Package) | Out-null
		}
	}
	"Obsolete Packages: $($ObsoletePackages.Count)" | Out-File "$($LogPath)\$($LogFile)" -Append
 
	#verify Data
	if ($($($($BadPackages.Count) + $($GoodPackages.Count))) -eq $AllPackages.Count)
	{
		"Counts ARE accurate." | Out-File "$($LogPath)\$($LogFile)" -Append
		if ($FixBadPackages -eq $true)
		{
			"Fix Packages flag IS present for Bad Packages, redistributing these Packages..." | Out-File "$($LogPath)\$($LogFile)" -Append
			foreach ($BadPackage in $BadPackages)
			{
				try
				{
					if (Refresh-SpecificDP -packageID $BadPackage -dpName $DPName)
					{
						"$($BadPackage), Success" | Out-File "$($LogPath)\$($LogFile)" -Append
					}
					else
					{
						"$($BadPackage), Failure" | Out-File "$($LogPath)\$($LogFile)" -Append
					}
				}
				catch
				{
					"$($BadPackage), Error" | Out-File "$($LogPath)\$($LogFile)" -Append
				}
			}
		}
		else
		{
			"Fix Packages flag is NOT present for Bad Packages, No Action will be taken on these Packages" | Out-File "$($LogPath)\$($LogFile)" -Append
		}
		if ($FixObsoletePackages -eq $true)
		{
            "Fix Packages flag IS present for Obsolete Packages, removing these packages from WMI and Content Library..." | Out-File "$($LogPath)\$($LogFile)" -Append
            foreach ($ObsoletePackage in $ObsoletePackages) {
                try
				{
			        if (Remove-PackageFromDPWMI -DPName $DPName -PackageID $ObsoletePackage) {
                        "$($ObsoletePackage), Successfully Removed from WMI" | Out-File "$($LogPath)\$($LogFile)" -Append
                    } else {
                        "$($ObsoletePackage), Not Found in WMI" | Out-File "$($LogPath)\$($LogFile)" -Append
                    }
                } catch {
                    "$($ObsoletePackage), Error Removing from WMI" | Out-File "$($LogPath)\$($LogFile)" -Append
                }
                try {
                    [array]$ContentLibRemovals = Remove-PackageFromContentLib -DPName $DPName -PackageID $ObsoletePackage
                    if ($ContentLibRemovals.count -gt 0) {
                        foreach ($ContentLibRemoval in $ContentLibRemovals) {
                            "$($ContentLibRemoval)" | Out-File "$($LogPath)\$($LogFile)" -Append
                        }
                    } else {
                        "$($ObsoletePackage), Not found in content Lib on this DP." | Out-File "$($LogPath)\$($LogFile)" -Append
                    }  
                } catch {
                    "$($ObsoletePackage), Error Removing from Content Library" | Out-File "$($LogPath)\$($LogFile)" -Append
                }
            }
		}
		else
		{
			"Fix Packages flag is NOT present for Obsolete Packages, No Action will be taken on these Packages" | Out-File "$($LogPath)\$($LogFile)" -Append
		}
        if ($OutPutBadPackages -eq $true) {
            if ($BadPackages.count -gt 0) {
                Write-Host "Bad Packages:"
                foreach ($BadPackage in $BadPackages) {
                    Write-Host "- $($BadPackage)"
                }
            } else {
                Write-Host "No Bad Packages Found."
            }
        }
        if ($OutPutObsoletePackages -eq $true) {
            if ($ObsoletePackages.Count -gt 0) {
                Write-Host "Obsolete Packages:"
                foreach ($ObsoletePackage in $ObsoletePackages) {
                    Write-Host "- $($ObsoletePackage)"
                }
            } else {
                Write-Host "No Obsolete Packages Found."
            }
        }
        "[ $(Get-Date -Format 'yyyy.MM.dd hh:mm:ss') ] Script Ended" | Out-File "$($LogPath)\$($LogFile)" -Append
	}
	else
	{
		"Counts are NOT accurate.  Aborting." | Out-File "$($LogPath)\$($LogFile)" -Append
	}
}
else
{
	Write-Host "You must provide your Site Server name, Site Code, and a DP to check.  You may optionally provide a log path location as well."
}