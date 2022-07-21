########################################################################################################################################################
# visuaFUSION Systems Solutions Windows 10 Toolkit
# Remove-ProvisionedApps.ps1
# Script Author: Sean Huggans
########################################################################################################################################################
# This script is meant to be used in a legacy package (with source files, no
# program) called from a command line step after booting into an 
# installed operating system during an OSD task sequence. It will remove the 
# provisioned apps called out in the accompanying Remove-ProvisionedApps.list 
# file in this script's root directory.

############################################################
# Script Config
############################################################
$ScriptVersion = "19.06.08.07"

############################################################
# Logging Config
############################################################
$LogFile = "Remove-ProvisionedApps.log"
$LogDir = "C:\Windows\visuaFUSION\OS Management"
$LogPath = "$($LogDir)\$($LogFile)"

function Log-Action ($Message, $TimeStamp)
{
    ################################
    # Function Version 18.4.14.1
    # Function by Sean Huggans
    ################################
	New-Item -ItemType directory -Path $LogDir -Confirm:$false -Force -ErrorAction SilentlyContinue | out-null
    if (($TimeStamp -ne $false) -and ($TimeStamp -ne "no")) {
	    "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File $LogPath -Append
    } else {
        "$($Message)" | Out-File $LogPath -Append
    }
}

Log-Action "===============================================================================" -TimeStamp $false
Log-Action "= visuaFUSION Systems Solutions Windows 10 Toolkit" -TimeStamp $false
Log-Action "= Remove-ProvisionedApps version: $($ScriptVersion)" -TimeStamp $false
Log-Action "===============================================================================" -TimeStamp $false
if (Test-Path -Path "$($PSScriptRoot)\Remove-ProvisionedApps.list") {
    [array]$ProvisionedAppsToRemove = Get-Content -Path "$($PSScriptRoot)\Remove-ProvisionedApps.list"
    if ($ProvisionedAppsToRemove.count -gt 0) {
        foreach ($ProvisionedAppToRemove in $ProvisionedAppsToRemove) {
            $ResultA = 0
            $ResultB = 0
            if (($ProvisionedAppToRemove -ne "") -and ($ProvisionedAppToRemove -ne $null)) {
                try {
                    Get-AppxPackage -Name $ProvisionedAppToRemove -AllUsers | Remove-AppPackage -ErrorAction Stop
                } catch {
                    $Details = "$($_.CategoryInfo.ToString()), $($_.FullyQualifiedErrorId)"
                    if ($Details -like "*ObjectNotFound*") {
                        $ResultA = 1
                    } else {
                        $ResultA = 2
                    }
                }
                Try {
                    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $ProvisionedAppToRemove } | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
                } catch {
                    $Details = "$($_.CategoryInfo.ToString()), $($_.FullyQualifiedErrorId)"
                     if ($Details -like "*ObjectNotFound*") {
                        $ResultB = 1
                    } else {
                        $ResultB = 2
                    }
                }
                if (($ResultA -eq 2) -or ($ResultB -eq 2)) {
                    Log-Action " - $($ProvisionedAppToRemove) - Removal Failed"
                } else {
                    Log-Action " - $($ProvisionedAppToRemove) - Removal Succeeded"
                }
            }
        }
        Log-Action "All actions have completed.  Check Details Above."
    } else {
        Log-Action "Error: The accompanying Remove-ProvisionedApps.list file contains no Provisioned Apps to Remove."
    }
} else {
    Log-Action "Error: The required Remove-ProvisionedApps.list file cannot be found in the script root.  No actions have been taken, this script will exit."
}