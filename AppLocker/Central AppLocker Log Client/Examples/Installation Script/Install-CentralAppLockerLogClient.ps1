#############################################
# Install-CentralAppLockerLogClient.ps1
# Author(s): Sean Huggans
$ScriptVersion = "25.1.19.2"
#############################################
# Variables
#####################
$AppName = "Central AppLocker Log Client"
$AppInstallPath = "C:\Program Files\bahusa.net\$($AppName)" # Service is hard coded to bahusa.net due to msi build - you will need to rebuild exe + msi from source if you want to change this!

$LogFile = "$($AppName)_Install.log"
$LogDir = "C:\Windows\Logs\Software"
$LogPath = "$($LogDir)\$($LogFile)"

###########################
# Functions
#####################

Function Log-Action ($Message, $StampDateTime, $WriteHost) {
    ################################
    # Function Version 19.5.11.4
    # Function by Sean Huggans
    ################################
    if (!(Test-Path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Confirm:$false -Force | Out-Null
    }
    if (($StampDateTime -eq $false) -or ($StampDateTime -eq "no")) {
        $Message | Out-File $LogPath -Append
    } else {
        "[ $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss') v$($ScriptVersion) ] $($Message)" | Out-File $LogPath -Append
    }
    if ($WriteHost -eq $true) {
        Write-Host $Message
    }
}

###########################
# Execution Logic
#####################
Log-Action -Message "Beginning $($AppName) installation..."

# Install MSI
Try {
    $MSIPath = "$($PSScriptRoot)\Central AppLocker Log Client.msi"
    $MSILogPath = "$($LogDir)\$($AppName)_MSIInstall.log"
    if (Test-Path -Path $MSIPath) {
        Log-Action -Message "Installing MSI from $($MSIPath)..."
        $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($MSIPath)`" /qn /l*v `"$($MSILogPath)`"" -PassThru -Wait -WindowStyle Hidden
        switch ($Process.ExitCode) {
            0 {
                Log-Action -Message "Successfully installed service MSI, continuing on..."
            }
            1602 {
                Log-Action -Message "MSI installation was cancelled (Exit Code: 1602).  Aborting."
                Exit 1602
            }
            1603 {
                Log-Action -Message "MSI installation encountered a fatal error (Exit Code: 1603).  Check MSI log for details.  Aborting."
                Exit 1603
            }
            1618 {
                Log-Action -Message "Another installation is already in progress (Exit Code: 1618).  Aborting."
                Exit 1618
            }
            1619 {
                Log-Action -Message "MSI package could not be opened (Exit Code: 1619).  Aborting."
                Exit 1619
            }
            1641 {
                Log-Action -Message "MSI installed successfully but a reboot was initiated (Exit Code: 1641)."
                Exit 1641
            }
            3010 {
                Log-Action -Message "MSI installed successfully but a reboot is required (Exit Code: 3010).  Continuing on..."
            }
            default {
                Log-Action -Message "MSI installation returned an unhandled exit code: $($Process.ExitCode).  Aborting."
                Exit $Process.ExitCode
            }
        }
    } else {
        Log-Action -Message "MSI file not found at $($MSIPath).  Aborting."
        Exit 1
    }
} catch {
    Log-Action -Message "Error during MSI installation: $($_.Exception.Message).  Aborting."
    Exit 1
}

# Plant Config
Try {
    $ConfigSource = "$($PSScriptRoot)\CALC.config"
    $ConfigDestination = "$($AppInstallPath)\CALC.config"
    if (Test-Path -Path $ConfigSource) {
        Log-Action -Message "Copying config file to $($ConfigDestination)..."
        Copy-Item -Path $ConfigSource -Destination $ConfigDestination -Force -ErrorAction Stop
        Log-Action -Message "Successfully planted CALC.config."
    } else {
        Log-Action -Message "Config file not found at $($ConfigSource).  Aborting."
        Exit 1
    }
} catch {
    Log-Action -Message "Error planting CALC.config: $($_.Exception.Message).  Aborting."
    Exit 1
}

Log-Action -Message "$($AppName) installation completed successfully."
Exit 0