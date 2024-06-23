############################
# Install-RSAT.ps1
$ScriptVersion = "24.6.22.4"
# Script Author(s): PotentEngineer, Sean Huggans (Bahusafoo)
############################
# Variables
############################
$LogFile = "RSAT_Install.log"
$LogDir = "C:\Windows\Logs\Software"
$LogPath = "$($LogDir)\$($LogFile)"

############################
# Functions
############################

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
        Write-host $Message
    }
}

Function Clear-WindowsFeatureInstallationBlocks {
# Function based on Original Script posted by PotentEngineer (https://www.reddit.com/user/PotentEngineer/)
    Try {
        Log-Action -Message "Attempting to clear up Known RSAT Installation Blockers..."
        # Clear Keys Which Prevent RSAT, WSL, OpenSSH Installations
        if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name DeferFeatureUpdatesPeriodInDays -ErrorAction SilentlyContinue) {Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name DeferFeatureUpdatesPeriodInDays -Force}
        if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name SetDisableUXWUAccess -ErrorAction SilentlyContinue) {Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name SetDisableUXWUAccess -Force}
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name DisableWindowsUpdateAccess -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name SetPolicyDrivenUpdateSourceForDriverUpdates -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name SetPolicyDrivenUpdateSourceForFeatureUpdates -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name SetPolicyDrivenUpdateSourceForOtherUpdates -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name SetPolicyDrivenUpdateSourceForQualityUpdates -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name UseUpdateClassPolicySource -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name DoNotConnectToWindowsUpdateInternetLocations -Value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name DisableWindowsUpdateAccess -Value 0
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache\CacheSet001\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache\CacheSet002\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        # We need to also clear the servicing key's repair contentserversource if present - localsourcepath may also interfere so removing it, too.
        if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" -Name RepairContentServerSource -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" -Name RepairContentServerSource -Force -ErrorAction Stop
        }
        if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" -Name LocalSourcePath -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" -Name LocalSourcePath -Force -ErrorAction Stop
        }
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache\CacheSet001\WindowsUpdate" -Force | Out-Null
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache\CacheSet001\WindowsUpdate\AU" -Force | Out-Null
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache\CacheSet002\WindowsUpdate" -Force | Out-Null
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache\CacheSet002\WindowsUpdate\AU" -Force | Out-Null
        Log-Action -Message " - Success! Known blockers have been cleared!"
        # Restart WSUS
        Try {
            Log-Action -Message "Attempting to restart WSUS Service after policy adjustments..."
            Stop-Service -Name wuauserv -Force -ErrorAction Stop
            Start-Service -Name wuauserv -ErrorAction Stop
            Log-Action -Message " - Success!"
        } catch {
            Log-Action -Message " - Failed ($($PSItem.ToString()))"
        }
        return $true
    } catch {
        Log-Action -Message " - Error: Clearing Windows Feature Installation Blocks failed!  The script will continue, however, installation of RSAT may fail!"
        return $false
    }
}
############################
# ExecutionLogic
############################
Log-Action -Message "RSAT Installation Script Started."
$ClearBlocksResult = Clear-WindowsFeatureInstallationBlocks

# Get OS Name
$OS = $(Get-WmiObject Win32_OperatingSystem).Caption

Log-Action -Message "Checking status of RSAT modules, we will attempt to install any that are not present ..."
if ($OS -notlike "*Windows Server*") {
    # Handle Windows Client OS
    Foreach ($RSATPackage in [array]$(Get-WindowsCapability -Name "RSAT*" -Online)) {
        if ($RSATPackage.State -eq "NotPresent") {
            Try {
                Log-Action -Message "Attempting to Install ""$($RSATPackage.Name)"" ($($RSATPackage.DisplayName)) - This may take some time..."
                Add-WindowsCapability -Name $RSATPackage.Name -Online -ErrorAction Stop | out-null
                Log-Action -Message " - Success: $($RSATPackage.Name) ($($RSATPackage.DisplayName))"
            } catch {
                Log-Action -Message " - Failed: $($RSATPackage.Name) ($($PSItem.ToString()))"
            }
        } else {
            Log-Action -Message """$($RSATPackage.Name)"" ($($RSATPackage.DisplayName)) is already installed, skipping!"
        }
    }
} else {
    Foreach ($RSATPackage in [array]$(Get-WindowsFeature -Name "RSAT*")) {
        if ($RSATPackage.InstallState -eq "Available") {
            Write-Host "$($RSATPackage.Name) - $($RSATPackage.InstallState)"
            Try {
                Log-Action -Message "Attempting to Install ""$($RSATPackage.Name)"" ($($RSATPackage.DisplayName)) - This may take some time..."
                Install-WindowsFeature -Name $RSATPackage.Name -ErrorAction Stop | out-null
                Log-Action -Message " - Success: $($RSATPackage.Name) ($($RSATPackage.DisplayName.Replace('[','').Replace(']','').Trim()))"
            } catch {
                Log-Action -Message " - Failed: $($RSATPackage.Name) ($($PSItem.ToString()))"
            }
        }
    }
}
# Put Servicing Values Back
Try {
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" -Name RepairContentServerSource -PropertyType DWORD -Value 2 -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" -Name LocalSourcePath -PropertyType ExpandString -Value "" -Force -ErrorAction Stop | Out-Null
    Log-Action -Message "Successfully re-applied servicing values."
} catch {
    Log-Action -Message "Failed to re-apply servicing values ($($PSItem.ToString()))"
}
Log-Action -Message "RSAT Installation Script Finished."