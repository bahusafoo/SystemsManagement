###############################################
# Maintain-AutoLogonAccounts.ps1
# AutoLogon Account Maintenance Script
# Author(s): Sean Huggans
$Version = "23.12.9.5"
###############################################
# Variables
#########################################
[string]$AutoLogonPCsGroupName = "Ent-AutoLogonPCs"
[int]$PasswordLength = 20 # Set the minimum password length of generated passwords
[string]$LogFile = "Maintain-AutoLogonPasswords.log"
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

function Generate-StrongPassword {
    $Compliant = $false
    $TestPass = ""
    do {
        # generate a password with a random number of special characters
        [int]$MinimumSpecialChars = $([math]::Round($(Get-Random -Minimum $($PasswordLength / 8) -Maximum $($PasswordLength / 4)),0))
        [int]$InstancePasswordLength = $PasswordLength + $(Get-Random -Minimum 0 -Maximum 21)
        $TestPass = [System.Web.Security.Membership]::GeneratePassword($InstancePasswordLength,$(Get-Random -Minimum $MinimumSpecialChars -Maximum $(Get-Random -Minimum $($MinimumSpecialChars + 1) -Maximum $($MinimumSpecialChars + 4))))
        # Check to make sure password meets the following:
        # # contains digin from 0-9
        # # contains uppercase characters
        # # contains lowercase characters
        # # contains special characters
        # # at least the configured password length (defined in $PasswordLength variable)
        if ($TestPass -match "((?=.*\d)(?=.*[a-z])(?=.*[A-Z])(?=.*[@#$%\[\]\{\}\;\:\-\(\)\|\/]).{$($PasswordLength),$($PasswordLength + 20)})") {
            $Compliant = $true
        }
    } until ($Compliant -eq $true)
    return $TestPass
}

###############################################
# Execution Logic
#########################################
Log-Action -Message "AutoLogon Accounts Maintenance Started..."
# Import system.web (we use the password generation method from the system.web.security.membership class).
Add-Type -AssemblyName System.Web
# Ensure password minimum length is good
if ($PasswordLength -lt 14) {
    $PasswordLength = 14
}

# Create an array containing all autologon pc group members from the configured AD group...
[array]$AutoLogonPCGroupMembers = $(Get-ADGroupMember -identity $AutoLogonPCsGroupName).Name

Log-Action -Message "Maintenance will attempt to run against a total of $($AutoLogonPCGroupMembers.count) accounts..."
[int]$SuccessCount = 0

# Create an array to track failed machines and failure reasons
$ErrorMachines = New-Object System.Collections.ArrayList

# Create an array to track any failed machines left in a critical (non-functional) state
$ErrorMachines_Critical = New-Object System.Collections.ArrayList

# Run through each group member, processing autologon password updates
foreach ($AutoLogonPC in $AutoLogonPCGroupMembers) {
    Try {
        if (Test-Connection -ComputerName $AutoLogonPC -Count 2 -ErrorAction SilentlyContinue) {
            try {
                $TestSession = Invoke-Command -ComputerName $AutoLogonPC -ScriptBlock {
                    Try {
                        if (Test-Path -Path "C:\Windows") {
                            Try {
                                "[$(Get-Date -Format 'YYYY-MM-dd HH:mm:ss')] AutoLogon Maintenance Access Test" | Out-File -FilePath "C:\Windows\AutoLogonMaintenanceTest.log" -Force -Encoding utf8 -Confirm:$false
                                return $true
                            } catch {
                                return $false
                            }
                        } else {
                            return $false
                        }
                    } catch {
                        return $false
                    }
                } -ErrorAction Stop

                # Test PSRemoting before we continue on
                if ($TestSession -eq $true) {
                    # Generate a New Password to use 
                    $NewPassword = Generate-StrongPassword
                    $NewPasswordObject =  ConvertTo-SecureString -String $NewPassword -AsPlainText -Force

                    # Check for matching user object in AD
                    if ($UserObject = Get-ADUser -Identity $AutoLogonPC) {

                        # User object found, Update Password in Active Directory
                        Log-Action -Message "$($AutoLogonPC) - Online, InvokeSessionWorked: True, AD Object Found ($($NewPassword))"
                        Try {
                            Set-ADAccountPassword -identity $AutoLogonPC -NewPassword $NewPasswordObject -Reset
                            Log-Action -Message "$($AutoLogonPC) - Online, InvokeSessionWorked: True, AD Object Found, AD Password Update Success"
                            # Perform logic to update password on target PC

                            $SuccessCount += 1
                        } catch {
                            Log-Action -Message "$($AutoLogonPC) - Online, InvokeSessionWorked: True, AD Object Found, AD Password Update Failed ($($PSItem.ToString()))!"
                            $ErrorMachines.Add("$($AutoLogonPC),ADPasswordUpdateFailure") | Out-Null
                        }
                    } else {
                        Log-Action -Message "$($AutoLogonPC) - Online, InvokeSessionWorked: True, AD Object NOT Found (Error)"
                        $ErrorMachines.Add("$($AutoLogonPC),MatchingAutoLogonAccountNotFound") | Out-Null
                    }
                } else {
                    Log-Action -Message "$($AutoLogonPC) - Online, Error Invoking Remote Session"
                    $ErrorMachines.Add("$($AutoLogonPC),PSRemoteError") | Out-Null
                }
            } catch {
                Log-Action -Message " - - Error invoking remote session ($($PSItem.ToString()))"
                $ErrorMachines.Add("$($AutoLogonPC),PSRemoteError") | Out-Null
            }
        } else {
            Log-Action -Message "$($AutoLogonPC) - Offline"
            $ErrorMachines.Add("$($AutoLogonPC),Offline") | Out-Null
        }
    } catch {
        Log-Action -Message "$($AutoLogonPC) - Error Testing Connection ($($PSItem.ToString()))"
        $ErrorMachines.Add("$($AutoLogonPC),OnlineTestError") | Out-Null
    }
}
if (!(Test-Path -Path "$($LogDir)\Reports")) {
    New-Item -Path "$($LogDir)\Reports" -ItemType Directory -force -ErrorAction SilentlyContinue | Out-Null
}
# Output a report of failed/skipped/offline machines
$ErrorMachines | Out-File -FilePath "$($LogDir)\Reports\FailedAccountMaintenanceReport-$(Get-Date -Format 'YYYY-MM-dd-HH-mm-ss').csv" -Encoding utf8 -NoClobber -Force
Log-Action -Message "AutoLogon Accounts Maintenance Finished.  Result: $($SuccessCount) Success, $($ErrorMachines.Count) Errors.  Check above for details.  Failed Machine reports will be available at ""$($LogDir)\Reports""."