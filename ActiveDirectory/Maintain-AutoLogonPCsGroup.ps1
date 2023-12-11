###############################################
# Maintain-AutoLogonPCsGroup.ps1
# AutoLogon Group Maintenance Script
# Author(s): Sean Huggans
$Version = "23.12.9.5"
###############################################
# Variables
#########################################
[string]$AutoLogonPCsGroupName = "Ent-AutoLogonPCs"
$WorkstationOSUsedAsServersInEnvironnment = $true # Set this to true if you utilize workstations OS you want to exclude from maintenance in your environment (Why are you doing this?!)
[string]$LogFile = "Maintain-AutoLogonPCsGroup.log"
[string]$LogDir = "C:\Maintenance\Logs"
[string]$LogPath = "$($LogDir)\$($LogFile)"
###############################################
# Functions
#########################################
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
	    "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') v$($Version)] $($Message)" | Out-File $LogPath -Append
    }
    if ($WriteHost -eq $true) {
        Write-Host $Message
    }
}

Function Change-GroupMembership ($Action,$GroupName,$Member) {
    if (($Action -ne $null) -and ($GroupName -ne $null) -and ($Member -ne $null)) {
        if ($ADGroupObject = Get-ADGroup -Identity $GroupName) {
            Try {
                switch ($Action.ToUpper())
                {
                    "ADD" {
                        Add-ADGroupMember -Identity $GroupName -Members $Member -ErrorAction Stop -Confirm:$false
                        return "Remediated"
                    }
                    "REMOVE" {
                        Remove-ADGroupMember -Identity $GroupName -Members $Member -ErrorAction Stop -Confirm:$false
                        return "Remediated"
                    }
                    Default {
                        return "Error 3"
                    }
                }
            } catch {
                return "Error 4 ($($PSItem.ToString()))"
            }
        } else {
            return "Error 1"
        }
    } else {
        return "Error 0"
    }
}

###############################################
# Execution Logic
#########################################
Log-Action -Message "AutoLogon PCs Group Maintenance Started..."
[array]$AutoLogonPCGroupMembers = $(Get-ADGroupMember -identity $AutoLogonPCsGroupName).Name
if ($WorkstationOSUsedAsServersInEnvironnment -eq $true) {
    [array]$DomainComputers = Get-ADComputer -filter {operatingsystem -like "Windows 10*" -or operatingsystem -like "Windows 11*"} -Properties OperatingSystem | Where-Object {$_.DistinguishedName -notlike "*server*"} # Filter out cases where workstation OS is server use :(
} else {
    [array]$DomainComputers = Get-ADComputer -filter {operatingsystem -like "Windows 10*" -or operatingsystem -like "Windows 11*"} -Properties OperatingSystem
}
Log-Action -Message "Pre-Maintenance count of AutoLogon Machines is $($AutoLogonPCGroupMembers.count) out of $($DomainComputers.Count) total.  Checking workstations now..."
foreach ($DomainComputer in $DomainComputers) {
    Try {
        if (Test-Connection -ComputerName $DomainComputer.Name -Count 2 -ErrorAction Stop) {
            try {
                $Session = Invoke-Command -ComputerName $DomainComputer.Name -ScriptBlock {
                    Try {
                        if ($AutoAdminLogonProperty = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon") {
                            switch ($AutoAdminLogonProperty) {
                                1 {
                                    return $true
                                }
                                default {
                                    return $false
                                }
                            }
                        } else {
                            return $false
                        }
                    } catch {
                        return $false
                    }
                }
                if ($Session -eq $true) {
                    if ($AutoLogonPCGroupMembers -contains $DomainComputer.Name) {
                        Log-Action -Message "$($DomainComputer.Name) - Online, AutoLogon: $($Session), Compliant: $($true), Remediation: NA"
                    } else {
                        $RemediationResult = Change-GroupMembership -Action "Add" -GroupName $AutoLogonPCsGroupName -Member "$($DomainComputer.Name)$"
                        Log-Action -Message "$($DomainComputer.Name) - Online, AutoLogon: $($Session), Compliant: $($false), Remediation: $($RemediationResult)"
                    }
                } else {
                    if ($AutoLogonPCGroupMembers -contains $DomainComputer.Name) {
                        $RemediationResult = Change-GroupMembership -Action "Remove" -GroupName $AutoLogonPCsGroupName -Member "$($DomainComputer.Name)$"
                        Log-Action -Message "$($DomainComputer.Name) - Online, AutoLogon: $($Session), Compliant: $($false), Remediation: $($RemediationResult)"
                    } else {
                        Log-Action -Message "$($DomainComputer.Name) - Online, AutoLogon: $($Session), Compliant: $($true), Remediation: NA"
                    }
                }
            } catch {
                Log-Action -Message " - - Error invoking remote session ($($PSItem.ToString()))"
            }
        } else {
            Log-Action -Message "$($DomainComputer.Name) - Offline"
        }
    } catch {
        Log-Action -Message "$($DomainComputer.Name) - Error Testing Connection ($($PSItem.ToString()))"
    }
}
Log-Action -Message "AutoLogon PCs Group Maintenance Finished."