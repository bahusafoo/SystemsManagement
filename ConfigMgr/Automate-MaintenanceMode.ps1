################################################################################
# Automate-MaintenanceMode.ps1
# Auto Detect DP online status and set Maintenance Mode accordingly
# Author: Sean Huggans
# Version: "19.11.2.6"
################################################################################
# Script Variables
########################################
 
$SiteCode = "FOO" # Site code 
$ProviderMachineName = "SomeServer.SomeDomain.com" # SMS Provider machine name
[string[]]$SkipNames = "PRIMARY","PRIM","MP","CMG" # Add any other name patterns you want to be excluded from the scheduled task
 
# Email:
$Script:FromAddress = "ServiceAccount@SomeDomain.com" # Address of the service account you are sending emails from
$Script:ToAddress = "SCCMTeam@SomeDomain.com" # Address to send report of results to when finished
#$Script:CCAddress = "" # CC Addresses for build/ Reports
$Script:SMTPServer= "SMTPServer@SomeDomain.com" #SMTP server address
 
# Logging:
$LogFile = "Detect-MaintenanceModeChanges.log"
$LogDir = "C:\Environment Maintenance\Logs" # Adjust accordingly
 
####################################################################
# Do not change
######################
$LogPath = "$($LogDir)\$($LogFile)"
 
$initParams = @{}
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
Set-Location "$($SiteCode):\" @initParams
 
########################################
# Script Functions
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
        Log-Action -Message $Message
    }
}
 
function Maintain-Logs {
        # Truncate Log if over 5,000KB
    if ((Get-Item $LogPath).length -gt 5000kb) {
        $ArchiveStamp = "-Archived-$(get-date -Format "yyyyMMddhhmmss")"
        $ArchivedLogName = "$($LogDir)\Archived\$($LogFile.Replace('.log',''))$ArchiveStamp.log"
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
    }
    #Check for Logs Older than 4 weeks and delete them     
}
 
function Set-SHCMDPMaintenanceMode ($DP, $MaintModeState) {
    #Based on the works of Cody Mathis @ https://github.com/CodyMathis123/CM-Ramblings/blob/master/Set-CMDistributionPointMaintenanceMode.ps1
    $RemoteResult = Invoke-Command -ComputerName $ProviderMachineName -ScriptBlock {
        param ($DP, $MaintModeState, $SiteCode)
        if ($DP.NALPath) {
            if ($MaintModeState -eq "Enabled") {
                $WMISplat = @{
                    ClassName    = 'SMS_DistributionPointInfo'
                    Namespace    = "root\sms\site_$($SiteCode)"
                    MethodName   = 'SetDPMaintenanceMode'
                    Arguments    = @{
                        NALPath = $DP.NALPath
                        Mode    = [uint32]1
                    }
                }
            } else {
                $WMISplat = @{
                    ClassName    = 'SMS_DistributionPointInfo'
                    Namespace    = "root\sms\site_$($SiteCode)"
                    MethodName   = 'SetDPMaintenanceMode'
                    Arguments    = @{
                        NALPath = $DP.NALPath
                        Mode    = [uint32]0
                    }
                }
            }
            $result = $(Invoke-CimMethod @WMISplat).ReturnValue
            return $result
        } else {
            return 404
        }
    } -ArgumentList $DP, $MaintModeState, $SiteCode
    return $RemoteResult
}
 
########################################
# Script Execution Logic
########################################
Maintain-Logs
 
Log-Action -Message "=============================================================================="
Log-Action -Message "Gathering Distribution Point Data"
$DPs = Get-CMDistributionPoint
 
 
Log-Action -Message "Flushing DNS cache before checking DP statuses..."
Clear-DnsClientCache
 
Log-Action "Provider machine name is $($ProviderMachineName), checking connectivity..."
if (Test-Connection -ComputerName $ProviderMachineName -Count 4 -Quiet) {
    Log-Action -Message "$($ProviderMachineName) is online, Checking DP statuses..."
    $DPsPlacedIntoMaintenanceMode = New-Object system.collections.arraylist
    $DPsRemovedFromMaintenanceMode = New-Object system.collections.arraylist
    $DPswithFailedStateChanges = New-Object system.collections.arraylist 
    $CountTicker = 0
    foreach ($DP in $DPs) {
        $CountTicker += 1
        $DPName =  $DP.NALPath.split("\")[2].ToUpper()
        Log-Action -Message "Checking DP: $($DPName) ($($CountTicker)/$($DPs.Count) - $([math]::Round($($($CountTicker) / $($DPs.Count) * 100), 2))%)"
        $NamePassesCheck = $true
        foreach ($SkipName in $SkipNames) {
            if ($DPName -like "*$($SkipName)*") {
                $NamePassesCheck = $false
            }
        }
        if ($NamePassesCheck -eq $true) {
            $MaintenanceModeStatus = $(Get-WmiObject -ComputerName $ProviderMachineName -Namespace root\sms\site_SAN -Class "SMS_DistributionPointInfo" -Filter "name = '$($DPName)'").MaintenanceMode
            if (Test-Connection -ComputerName $DPName -Count 2 -Quiet) {
                $OnlineStatus =  "Online"
            } else {
                $OnlineStatus =  "Offline"
            }
            switch ($MaintenanceModeStatus) {
                0 {
                    Log-Action -Message "$($DPName): $($OnlineStatus), Not currently in maintenance Mode."
                    if ($OnlineStatus -eq "Online") {
                        Log-Action -Message " - Host is currently online, leaving DP out of maintenance mode."
                    } else {
                        Log-Action -Message " - Initial attempt to ping this DP has failed, waiting 30 seconds and trying again..."
                        Start-Sleep -Seconds 30
                        if (!(Test-Connection -ComputerName $DPName -Count 2 -Quiet)) {
                            Log-Action -Message " - Host is not reachable after two consecutive attempts, waiting 30 seconds and trying again..."
                            Start-Sleep -Seconds 30
                            if (!(Test-Connection -ComputerName $DPName -Count 2 -Quiet)) {
                                Log-Action -Message " - Host is not reachable after three consecutive attempts, enabling maintenance mode..."
                                Try {
                                    # Enable Maintenance Mode
                                    Set-SHCMDPMaintenanceMode -DP $DP -MaintModeState "Enabled"
                                    $DPsPlacedIntoMaintenanceMode.Add($DPName) | Out-Null
                                    Log-Action -Message " - Successfully placed DP into maintenance Mode."
                                } catch {
                                    Log-Action -Message " - Error: Failed to place DP into maintenance mode!"
                                    $DPswithFailedStateChanges.Add($DPName) | Out-Null
                                }
                            } else {
                                Log-Action -Message " - Host is currently online, leaving DP out of maintenance mode."
                            }
                        } else {
                            Log-Action -Message " - Host is currently online, leaving DP out of maintenance mode."
                        }
                    }
                }
                1 {
                    Log-Action -Message "$($DPName): $($OnlineStatus), Currently in maintenance Mode."
                    if ($OnlineStatus -eq "Online") {
                        Log-Action -Message " - Host is currently online, disabling maintenance mode..."
                        Try {
                            # Disable Maintenance Mode
                            Set-SHCMDPMaintenanceMode -DP $DP -MaintModeState "Disabled"
                            $DPsRemovedFromMaintenanceMode.Add($DPName) | Out-Null
                            Log-Action -Message " - Successfully removed DP from Maintenance Mode."
                        } catch {
                            Log-Action -Message " - Error: Failed to remove DP from maintenance mode!"
                            $DPswithFailedStateChanges.Add($DPName) | Out-Null 
                        }
                    } else {
                        Log-Action -Message " - Host is not currently online, leaving DP in maintenance mode."
                    }
                }
            }
        } else {
            Log-Action -Message "$($DPName): DP name is excluded from maintenance mode auto-maintenance."
        }
    }
 
    # Send email if necessary
 
    $HTMLString = "<html><body><h1 align=""center"">Distribution Point Maintenance Mode Change Report</h1><br />"
    $HTMLString = "$($HTMLString)The most recent run of the Distribution Point Maintenance Mode maintenance auto-job detected and made the following needed changes to distribution points:<br /><br />"
    if ($DPsPlacedIntoMaintenanceMode.Count -gt 0) {
        $HTMLString = "$($HTMLString)<b>The following distribution points were <u>unreachable</u> over the network and have been <u>placed into maintenance mode</u>:</b><br /><ol>"
        foreach ($DP in $DPsPlacedIntoMaintenanceMode) {
            $HTMLString = "$($HTMLString)<li>$($DP)</li>"
        }
        $HTMLString = "$($HTMLString)</ol><br />"
    }
    if ($DPsRemovedFromMaintenanceMode.Count -gt 0) {
        $HTMLString = "$($HTMLString)<b>The following distribution points were found to be <u>back online</u> and have been <u>taken out of maintenance mode</u>:</b><br /><ol>"
        foreach ($DP in $DPsRemovedFromMaintenanceMode) {
            $HTMLString = "$($HTMLString)<li>$($DP)</li>"
        }
        $HTMLString = "$($HTMLString)</ol><br />"
    }
    if ($DPswithFailedStateChanges.Count -gt 0) {
        $HTMLString = "$($HTMLString)<b>The auto-job detected state changes were needed for the following distribution points, however, changing their state failed.  These should be checked to determine if they should placed into or removed from maintenance mode:</b><br /><ol>"
        foreach ($DP in $DPswithFailedStateChanges) {
            $HTMLString = "$($HTMLString)<li>$($DP)</li>"
        }
        $HTMLString = "$($HTMLString)</ol><br />"
    }
    $HTMLString = "$($HTMLString)<i>This message has been sent from an automated system, please do not reply.</i><html><body>"
 
    if (($DPsPlacedIntoMaintenanceMode.count -ge 1) -or ($DPsRemovedFromMaintenanceMode.Count -ge 1) -or ($DPswithFailedStateChanges.Count -ge 1)) {
        Send-MailMessage -smtpServer $Script:SMTPServer -To $Script:ToAddress -from $Script:FromAddress -subject "DP Maintenance Mode Changes" -Body $HTMLString -BodyAsHtml -ErrorAction Stop
        Log-Action -Message "Changes were made or attempted, and an email report has been sent."
    } else {
        Log-Action -Message "No changes were made or attempted, skipping sending email report."
    }
} else {
    Log-Action -Message "Warning: $($ProviderMachineName) is offline, DP maintenance mode check has been skipped!"
}