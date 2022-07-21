########################################################################################################################################################
# visuaFUSION Systems Solutions Windows 10 Toolkit
# Update-ImageInfo.ps1
# Author: Sean Huggans
$Version = "17.2.3.3"
###############################################################################################################
# This script will create or update an Image Version registry value at "SOFTWARE\\$($CompanyName)\\ImageVersion".
# When used on a machine without an existing ImageVersion tracked (ideally as a step within an OSD task sequence,
# in a step that uses a package with source files), it will create the initial key.  When used on a machine that 
# already has an existing key (ideally as a step within an OS upgrade task sequence, in a step that uses a package
# with source files) the script will update the existing key to show the current OS release, as well as the number
# of times the machine has been upgraded.
#
# The format of the ImageVersion value is: AAAA.B.CCCC.DDDDDDDD
# AAAA = Currently installed OS release, B = Number of times the installed OS has been upgraded, CCCC = Originally
# Installed OS Release, DDDDDDD = your Organization's Named Image (provided by you for new machines, you can leave
# the default if you don't have your own naming scheme to supply)

########################################################################################################################################################
# Script variables
#####################################
[string]$CompanyName = "visuaFUSION"
[string]$OrganizationNamedImage = "1607_15a" # Update this with the ImageName you are deploying out for newly imaged machines
[string]$ImageVersionKey = "SOFTWARE\\$($CompanyName)\\ImageVersion"
[string]$LogFile = "ImageInfo.log"
[string]$LogDir = "C:\Windows\$($CompanyName)"

#####################################
# Script Functions
#####################################

function Log-Action ($Message, $StampDateTime, $WriteHost)
{
    ################################
    # Function Version 19.5.11.4
    # Function by Sean Huggans
    ################################
    $LogPath = "$($LogDir)\$($LogFile)"
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

function Update-ImageKeyInfo {
    #Clear Out Any Existing Matching Variables
    $CurrentWindowsVersion = $null
    [int]$CurrentBuildUpdatesInstalled = $null
    $OriginalWindowsVersionInstalled = $null
    $OriginalOrgImageInstalled =  $null

    #Fetch Existing Version Info
    $RemoteRegistry = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', "$Env:COMPUTERNAME")
    #Grab Current Release Version ID from Registry (YYMM build #)
	$CurrentWindowsVersionKey = $RemoteRegistry.OpenSubKey("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", $true)
	$CUrrentWindowsReleaseID = $CurrentWindowsVersionKey.GetValue("ReleaseID")

    #Grab Current Image Info From Registry
    $ImageVersionKey = $RemoteRegistry.OpenSubKey($ImageVersionKey, $true)
    Try {
        $CurrentImageVersionString = $ImageVersionKey.GetValue("Version")
        # Break Out Current Image Information From Existing String
        $CurrentImageVersionSplit = $CurrentImageVersionString.Split(".")
        if ($CurrentImageVersionSplit.Count -eq 4) {
            Log-Action -message "Detected ImageInfo update type is: Upgrade, original image stamp present"
            # Upgrade (with original image stamp)
            $CurrentWindowsVersion = $CurrentImageVersionSplit[0]
            [int]$CurrentBuildUpdatesInstalled = $CurrentImageVersionSplit[1]
            #Increment Build Updates Installed
            $NewBuildUpdatesInstalled = $CurrentBuildUpdatesInstalled += 1
            $OriginalWindowsVersionInstalled = $CurrentImageVersionSplit[2]
            $OriginalOrgImageInstalled =  $CurrentImageVersionSplit[3]
        } else {
            Log-Action -message "Detected ImageInfo update type is: Upgrade, Warning: organization name for the originally installed image is not present, and a ""0"" will be used in its place"
            # Upgrade (without original image stamp)
            [int]$CurrentBuildUpdatesInstalled = 0
            $NewBuildUpdatesInstalled = 0
            $OriginalWindowsVersionInstalled = $CurrentWindowsReleaseID
            if ($CurrentImageVersionSplit[0]) {
                $OriginalOrgImageInstalled = $CurrentImageVersionSplit[0]
            } else {
                $OriginalOrgImageInstalled = 0
            }
        }
        Log-Action -message "Building new ImageInfo string..."
        #Build New Image Info String
        $NewImageVersionString = "$($CurrentWindowsReleaseID).$($NewBuildUpdatesInstalled).$($OriginalWindowsVersionInstalled).$($OriginalOrgImageInstalled)"

    } catch {
        Log-Action -message "Detected ImageInfo update type is: Fresh Image, OrganizationNamedImage value will be used (currently ""$($OrganizationNamedImage)"")"
        # Fresh Image
        [int]$CurrentBuildUpdatesInstalled = 0
        $NewBuildUpdatesInstalled = 0
        $OriginalWindowsVersionInstalled = $CurrentWindowsReleaseID
        Try {
            if ($CurrentImageVersionSplit[0]) {
                $OriginalOrgImageInstalled = $CurrentImageVersionSplit[0]
            } else {
                $OriginalOrgImageInstalled = 0
            }
        } catch {
            $OriginalOrgImageInstalled = 0
        }
        Log-Action -message "Building new ImageInfo string..."
        #Build New Image Info String
        $NewImageVersionString = "$($CurrentWindowsReleaseID).$($NewBuildUpdatesInstalled).$($OriginalWindowsVersionInstalled).$($OrganizationNamedImage)"
    }
    Log-Action -Message "The current Windows 10 Version installed is ""$($CurrentWindowsReleaseID)""."
    Log-Action -Message "The OS has been upgraded ""$($NewBuildUpdatesInstalled)"" times since being installed."
    Log-Action -Message "The version of Windows 10 originally installed when this computer was imaged was ""$($OriginalWindowsVersionInstalled)""."
    Log-Action -Message "The internal name of the originally installed Windows 10 image is ""$($OriginalOrgImageInstalled)""."
    Log-Action -message "Writing processed ImageInfo to registry (""$($NewImageVersionString)"")"
    #Update Image Info Registry Value with New Image Version String
    Try {
        $ImageVersionKey.SetValue("Version", $NewImageVersionString)
        Log-Action -message "Result: Success"
    } catch {
        Log-Action -message "Result: Error"
    }
}

#####################################
# Execution Logic
#####################################
Log-Action -message "------------------------------------------------" -StampDateTime $false
Log-Action -message "Beginning ImageInfo processing (script version $($Version))..."
Update-ImageKeyInfo
Log-Action -message "Finished ImageInfo processing, see above for details."