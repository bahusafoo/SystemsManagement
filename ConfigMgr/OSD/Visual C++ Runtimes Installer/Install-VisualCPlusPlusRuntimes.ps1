#######################################
# Install-VisualCPlusPlusRuntimes.ps1
# Author(s): Sean Huggans (@bahusafoo, https://bahusa.net)
$Script:ScriptVersion = "22.8.29.2"
#######################################
# Script Description
##############################
# Script is meant to be used part of a package or application packge.
# This script will loop through directory structure present in its 
# current directory and identify + silently execute Visual C++ runtimes
# it finds.  It is necessary to maintain the following structure alongside
# the script for it to function correctly:
# /
# /2012/
# /2013/
# /2022/
# /Install-VisualCPlusPlusRuntimes.ps1
# ----------------
# You will need to download the appropriate installers as we cannot distribute
# them alongside the solution.  Latest known links are included in text documents
# inside the included directory structure.
#
# The script should be future proof to handle future VC++ versions as long
# as this directory structure is still followed with new versions as well.
#######################################
# Script Variables
##############################
[string]$script:LogFile = "Install-VisualCPlusPlusRuntimes.log"
[string]$script:LogDir = "C:\Windows\Logs\Software"
[string]$script:LogPath = "$($LogDir)\$($LogFile)"

#######################################
# Script Functions
##############################
function Log-Action ($Message, $StampDateTime, $WriteHost)
{
    ################################
    # Function Version 19.5.11.4
    # Function by Sean Huggans
    ################################
	New-Item -ItemType directory -Path $script:LogDir -Confirm:$false -Force | out-null
    if (($StampDateTime -eq $false) -or ($StampDateTime -eq "no")) {
        $Message | Out-File $LogPath -Append
    } else {
	    "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File $script:LogPath -Append
    }
    if ($WriteHost -eq $true) {
        Write-Host $Message
    }
}

#######################################
# Script Execution Logic
##############################

# Set a return code
$script:InstallerReturnCode = 0

Log-Action -Message "Beginning Visual C++ Runtimes Installation..." -WriteHost $true
# Create an arraylist to store all found executables
$InstallerObjects = New-Object System.Collections.ArrayList

#Find each EXE in the current directory structure (recursive), store them in an array
Log-Action -Message "Locating executables..." -WriteHost $true
if (($EXEFiles = [array]$(Get-ChildItem -Path $PSScriptRoot -Recurse -force | Where-Object {$_.Extension -eq ".exe"})) -and ($EXEFiles.Count -gt 0)) {
    foreach ($EXEFile in $EXEFiles) {
        # Validation:  We are only checking the file description and see if it shows as being a visual c++ redistributable, not doing anything else for validation here, though it could be easily expanded from here
        Log-Action -Message " - Validating File ($($EXEFile.FullName))..." -WriteHost $true
        if ($(Get-Item -Path $ExeFile.FullName).VersionInfo.FileDescription -like "*Visual C++*") {
            Log-Action -Message " - - Validation SUCCESS, analyzing file..." -WriteHost $true
            # Create Installer Object to track this installer's information
            $NewInstallerObject = New-Object -TypeName PSObject
            # Grab the version information from the exe's parent directory name, combine that into a string value adding .0.0.0, and store it in a Version object on the InstallerObject for accurate sorting later
            [version]$RuntimeVersion = "$($(Get-Item -Path $ExeFile.FullName).Directory.Name.Trim()).0.0.0"
            Log-Action -Message " - - - Runtime Version: $($RuntimeVersion)" -WriteHost $true
            $NewInstallerObject | Add-Member -MemberType NoteProperty -Name "RuntimeVersion" -Value $RuntimeVersion
            # Add the full path of the installer as a path property to the InstallerObject
            Log-Action -Message " - - - Full Path: $($EXEFile.FullName)" -WriteHost $true
            $NewInstallerObject | Add-Member -MemberType NoteProperty -Name "Path" -Value $EXEFile.FullName

            # Add the architecture to the InstallerObject
            switch -wildcard ($EXEFile.Name) {
                "*x64*" {
                    $Architecture = "x64"
                    Log-Action -Message " - - - Architecture: $($Architecture)" -WriteHost $true
                    break
                }
                "*x86*" {
                    $Architecture = "x86"
                    Log-Action -Message " - - - Architecture: $($Architecture)" -WriteHost $true
                    break
                }
                default {
                    $Architecture = "unknown"
                    Log-Action -Message " - - - Warning: unknown Architecture, this file will be skipped during installation!" -WriteHost $true
                    break
                }
            }
            $NewInstallerObject | Add-Member -MemberType NoteProperty -Name "Architecture" -Value $Architecture

            # Add this version object to the $InstallerObjects we created earlier
            $InstallerObjects.Add($NewInstallerObject) | Out-Null
        } else {
            Log-Action -Message " - - Validation FAILURE, skipping inclusion of file..." -WriteHost $true
        }
    }
    # Loop through a temporary sorted version of $InstallerObjects (ascending) in order to install the runtimes from oldest to newest, x86 first followed by x64
    Log-Action -Message "Found $($InstallerObjects.ToArray().Count.ToString()) VC++ runtime installers within this package, installing them now..." -WriteHost $true
    foreach ($InstallerObject in $($InstallerObjects | Sort-Object -Property "Architecture" -Descending | Sort-Object -Property "RuntimeVersion")) {
        if ($InstallerObject.Architecture -ne "Unknown") {
        Log-Action -Message " - Installing $($InstallerObject.Architecture) Visual C++ $($InstallerObject.RuntimeVersion.Major) Runtime..." -WriteHost $true
        Try {
            # Start a process to run the exe with the appropriate parameters, hiding the new window and enabling passthru to return a return code, and waiting until the process is completed to continue.
            $InstArgs = "/Q"
            if ($InstallerObject.RunTimeVersion.Major -ge 2013) {
                # version 2013 and newer need a /NoRestart switch in order to avoid a reboot
                $InstArgs = "/Quiet /NoRestart"
            }
            $InstallProc = Start-Process -FilePath $InstallerObject.Path -ArgumentList $InstArgs -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
            switch ($InstallProc.ExitCode) {
                0 {
                    Log-Action -Message " - - Success!" -WriteHost $True
                    break
                }
                3010 {
                    Log-Action -Message " - - Success (reboot required)!" -WriteHost $True
                    $InstallerReturnCode = 3010
                }
                default {
                    Log-Action -Message " - - Error: Unknown success code returned from installation process ($($InstallProc.ExitCode)), this is considered a failure!" -WriteHost $True
                    $InstallerReturnCode = 1603
                    break
                }
            }

            } catch {
                Log-Action -Message " - - Error: Error starting installation process ($_.Error)!" -WriteHost $True
            }
        } else {
            Log-Action -Message "- Error: Unknown architecture for this installer, it will be skipped!" -WriteHost $True
        }
    }
} else {
    Log-Action -Message " - Error: No exe's were found in the current package (did you forget to download them?).  Installation aborting." -WriteHost $True
    $InstallerReturnCode = 1603
}

return $script:InstallerReturnCode