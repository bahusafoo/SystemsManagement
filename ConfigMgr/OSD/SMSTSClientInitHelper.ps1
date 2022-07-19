##############################################
# SMSTSClientInitHelper.ps1
# Client not started fix
# Author: Sean Huggans
$Version = "20.14.1.3"
##############################################
[string]$CMSiteCode = "FOO"
[string[]]$MPNames = "<Server>.FQDN.NET"
[string]$LogFile = "SMSTSClientInitHelper.log"
[string]$LogDir = "C:\Windows\CCM\Logs"
 
#################################
# Script Functions
#################################
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
        Log-action -Message $Message
    }
}
 
#################################
# Script Execution Logic
#################################
Log-action -Message "SMSTS Client Initialization Helper Script v$($Version) Started."
Log-action -Message "Waiting 60 seconds prior to seeing if ConfigMgr client agent is operational..."
Start-Sleep -Seconds 60
Log-action -Message "Checking to make sure ConfigMgr client agent is operational..."
switch ($(Get-Service -Name CcmExec).Status) {
    "Running" {
        Log-action -Message "ConfigMgr client is running.  Waiting an additional minute to give the client a chance to start up prior to allowing the task sequence to move on."
        # Output TS variable as True after one minute
        Start-Sleep -Seconds 60
        return $true
    }
    default {
        Try {
            start-service -Name CcmExec -erroraction silentlycontinue
            Log-action -Message "ConfigMgr client not running, wating 90 seconds before checking again..."
            # Wait 1.5 minutes for client to start up
            Start-Sleep -Seconds 90
            if ($($(Get-Service -Name CcmExec).Status) -ne "Running") {
                Log-action -Message "ConfigMgr client not running, wating 240 more seconds before checking again..."
                # Wait another 4 minutes for client to start up
                Start-Sleep -Seconds 240
                if ($($(Get-Service -Name CcmExec).Status) -ne "Running") {
                    Log-action -Message "ConfigMgr client not running, kicking off ccmsetup with configured settings..."
                    if (test-path -path "$($env:SystemDrive)\Windows\ccmsetup\ccmsetup.exe") {
                        # Get first online MP in the list
                        [string]$FirstOnlineMP = $MPNames[0]
                        foreach ($MPName in $MPNames) {
                            if (Test-Connection -ComputerName $MPName -Count 2 -Quiet) {
                                $FirstOnlineMP = $MPName
                                Log-action -Message "$($MPName) is online, will be used for ccmsetup MP."
                            } else {
                                Log-action -Message "$($MPName) is not reachable, trying the next MP in the list (if provided)..."
                            }
                        }
                        Log-action -Message "Kicking off CCMSetup.exe with the following arguments: ""SMSSITECODE=$($CMSiteCode), /MP:$($FirstOnlineMP)"" (MP May changed via boundary assignement once the client initializes)"
                        # Run CCM setup, provide MP Name
                        $Process = start-process -FilePath "$($env:SystemDrive)\Windows\ccmsetup\ccmsetup.exe" -argumentlist "SMSSITECODE=$($CMSiteCode) /MP:$($FirstOnlineMP)" -PassThru -wait -erroraction SilentlyContinue
                        switch ($Process.ExitCode) {
                            0 {
                                # Restart workstation, Output TS variable as True
                                Log-action -Message "CCMSetup returned an exit code indicating a successfull installation.  Waiting an additional 7 minutes for any client initialization to finish up..."
                                # Wait another 7 minutes for client to install and become available
                                Start-Sleep -Seconds 720
                                if ($($(Get-Service -Name CcmExec).Status) -ne "Running") {
                                    Log-action -Message "ConfigMgr client is still not running.  Giving up (Failure Spot 3)."
                                    # Output TS variable as False
                                    return $false
                                } else {
                                    # Output TS variable as True
                                    Log-action -Message "Returning success"
                                    return $true
                                }
                            }
                            7 {
                                # Restart workstation, Output TS variable as True
                                Log-action -Message "CCMSetup returned an exit code indicating a reboot is needed for the ConfigMgr client to initialize.  A reboot has been scheduled for 15 seconds, the script is Returning success"
                                Start-Process -FilePath shutdown -ArgumentList "/r /t 15"
                                return $true
 
                            }
                        }
                    } else {
                        Log-action -Message "ConfigMgr client setup path does not exist to run a repair.  Giving up (Failure Spot 2)."
                        # Output TS variable as False, ccmsetup does not exist.
                        return $false
                    }
                }
            } else {
                Log-action -Message "ConfigMgr client is running.  Waiting an additional minute to give the client a chance to start up prior to allowing the task sequence to move on."
                # Output TS variable as True after one minute
                Start-Sleep -Seconds 60
                Log-action -Message "Returning success"
                return $true
            }
        } catch {
            Log-action -Message "Some failure occured attempting to wait for or remediate the ConfigMgr client during the task seqence.  Giving up (Failure Spot 1)."
            # Output TS variable as False, ccmsetup does not exist.
            return $false
        }
    }
}