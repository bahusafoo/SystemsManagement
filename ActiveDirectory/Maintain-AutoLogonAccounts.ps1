###############################################
# Maintain-AutoLogonAccounts.ps1
# AutoLogon Account Maintenance Script
# Author(s): Sean Huggans
$Version = "24.2.12.9"
###############################################
# Variables
#########################################
[string]$DomainName = "DOMAIN"
[string]$AutoLogonPCsGroupName = "Ent-AutoLogonPCs"
[bool]$RebootAfterUpdate = $true # Reboot the local PC after it's autologon password has been updated (this is probably a good idea to avoid account lockouts, etc.)
[int]$RebootTimeInSeconds = 120 # Time to wait after notifying the user of a reboot before the reboot will occur (A message is displayed for this many seconds, warning the user to save their work)
[int]$MaxPasswordAgeDays = 90 # Maximum Password Age in Days
[int]$PerRunLimit = 256 # Limit this script to handling X number of accounts per-run.  This is useful for preventing overload, as well as staggering management of accounts (so that we aren't resetting large #s always at once)
[int]$PasswordLength = 20 # Set the minimum password length of generated passwords
[string]$SQLServerFQDN = "" # Leave as "" unless SQL is off-box
[string]$SQLDBName = "" # Leave as "" unless specifically naming DB differently from default (AutoLogonAccountMaintenance)
[string]$PathToAutoLogonEXE = "C:\Program Files\SysInternals\Autologon\Autologon.exe" # Path where Autologon EXE is expected to be on managed workstations
[int]$LogLevel = 1

# Email Settings:
$SMTPServer = "smtp.somedomain.com"
$ToAddress = "ToEmail@somedomain.com"
$FromAddress = "" # leave blank to pull mail property address from currently running account, setting this will override
$CCAddress = "" # leave blank ("") for none
$EmailTitle = "Autologon Accounts Maintenance Summary - $(Get-Date -format 'yyyy/MM/dd')"
$SendingOrg = "Some IT Dept. Name"
$ScriptReportBaseURL = "https://internalserver.somedomain.com"

# Log Settings:
[string]$LogFile = "Maintain-AutoLogonPasswords.log"
[string]$LogDir = "D:\Maintenance Jobs\Logs"
[string]$LogPath = "$($LogDir)\$($LogFile)"
[string]$ReportsDir = "D:\Maintenance Jobs\Maintain-AutoLogonPasswords\Reports"


###############################################
# No-Touch Variables
#########################################
$ErrorMachines = New-Object System.Collections.ArrayList # ArrayList to track failed machines and failure reasons
$ErrorMachines_Critical = New-Object System.Collections.ArrayList # ArrayList to track any failed machines left in a critical (non-functional) state
[int]$SQLErrors = 0

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

function Invoke-SQL
{
	param (
		[string]$dataSource,
		[string]$database,
		[string]$sqlCommand = $(throw "Please specify a query.")
	)
	if (Test-Connection -ComputerName $dataSource -Count 2 -Quiet)
	{
		$connectionString = "Data Source=$dataSource; " +
		"Integrated Security=SSPI; " +
		"Encrypt=True;" +
		"TrustServerCertificate=True;" +
		"Initial Catalog=$database"
 
		$connection = new-object system.data.SqlClient.SQLConnection($connectionString)
		$command = new-object system.data.sqlclient.sqlcommand($sqlCommand, $connection)
		Try
		{
			$connection.Open()
 
			$adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
			$dataset = New-Object System.Data.DataSet
			$adapter.Fill($dataSet) | Out-Null
 
			$connection.Close()
 
			$Result = $dataSet.Tables
		}
		catch
		{
			$ErrorMessage = $PSItem.ToString()
			switch -Wildcard ($ErrorMessage)
			{
				"*Login failed for user*" {
					$ErrorParts = $ErrorMessage.split("`n")
					$UserName = $ErrorParts[1].Split("'")[1].Replace("'", "")
 
					$QueryError = "User ""$($UserName)"" failed to login to the database."
				}
				default
				{
					$QueryError = "Unhandled Error: $($ErrorMessage)"
				}
			}
			$Result = "Error: A query to database ""$($database)"" on host ""$($dataSource)"" failed ($($PSItem.ToString()))."
		}
	}
	else
	{
		$Result = "Error: A query to the Database ""$($database)"" on host ""$($dataSource)"" was not attempted: $($dataSource) is unreachable."
	}
	return $Result
}

Function Track-MaintenanceStatus ($AccountName, $Status, $LogDetails) {
    if ($LogLevel -gt 0) {
        Log-Action -Message "DEBUG: Tracking Attempt for $($AccountName) ($($Status))..."
    }
    #Example: Track-MaintenanceStatus -AccountName "PEREXM44" -Status "Success"
    [array]$CurrentEntry = Invoke-SQL -dataSource $SQLServerFQDN -database $SQLDBName -sqlCommand "SELECT * FROM Maintenance_Tracking WHERE AccountName = '$($AccountName)';"
    [int]$CurrentFailures = 0
    if ($CurrentEntry -ne $null) {
        if ($CurrentEntry -notlike "Error*") {
            # Update Existing Entry
            if ($LogLevel -gt 0) {
                Log-Action -Message "Debug: $($AccountName), found existing record, updating..."
            }
            # If this machine is an error, track it for reporting later
            if ($Status.ToUpper() -notlike "SUCCESS*") {
                # Check if this machine was in error state last time maintenance attempted to run against it.  If so, we will increase the failure count by 1.
                if (($CurrentEntry.FailureCount) -and ($CurrentEntry.FailureCount -ne $null)) {
                    $CurrentFailures = $CurrentEntry.FailureCount + 1
                }
                # If this machine is a critical error (unusable state), track it for reporting later
                if ($Status.ToUpper() -eq "LOCALPASSWORDUPDATEFAILURE") {
                    # Add this machine to the critical error machines arraylist
                    $ErrorMachines_Critical.Add("$($AccountName),$($Status)") | Out-Null
                }
                # Add this machine to the error machines arraylist
                $ErrorMachines.Add("$($AccountName),$($Status)") | Out-Null
            }
            $NewEntry = Invoke-SQL -dataSource $SQLServerFQDN -database $SQLDBName -sqlCommand "UPDATE Maintenance_Tracking SET Status = '$($Status)', FailureCount = '$($CurrentFailures)' WHERE AccountName = '$($AccountName)';"
        } else {
            Log-Action -Message "$($AccountName) - Error Tracking Status in Database ($($CurrentEntry.ToString()))!"
            $SQLErrors +=1
            if ($Status.ToUpper() -notlike "SUCCESS*") {
                $CurrentFailures +=1
                # Add this machine to the error machines arraylist
                $ErrorMachines.Add("$($AccountName),$($Status)") | Out-Null
                # If this machine is a critical error (unusable state), track it for reporting later
                if ($Status.ToUpper() -eq "LOCALPASSWORDUPDATEFAILURE") {
                    # Add this machine to the critical error machines arraylist
                    $ErrorMachines_Critical.Add("$($AccountName),$($Status)") | Out-Null
                }
            }
        }
    } else {
        # Make New Entry
        if ($LogLevel -gt 0) {
            Log-Action -Message "Debug: $($AccountName), not yet tracked, updating record..."
        }
        # If this machine is an error, track it for reporting later
        if ($Status.ToUpper() -notlike "SUCCESS*") {
            $CurrentFailures +=1
            # Add this machine to the error machines arraylist
            $ErrorMachines.Add("$($AccountName),$($Status)") | Out-Null
            # If this machine is a critical error (unusable state), track it for reporting later
            if ($Status.ToUpper() -eq "LOCALPASSWORDUPDATEFAILURE") {
                # Add this machine to the critical error machines arraylist
                $ErrorMachines_Critical.Add("$($AccountName),$($Status)") | Out-Null
            }
        }
        $NewEntry = Invoke-SQL -dataSource $SQLServerFQDN -database $SQLDBName -sqlCommand "INSERT INTO Maintenance_Tracking (AccountName, Status, FailureCount) VALUES ('$($AccountName)', '$($Status)', '$($CurrentFailures)');"
    }
    if (($LogDetails -eq $null) -or ($LogDetails -eq "")) {
        $LogDetails = "No details provided (likely a success case)"
    }
    Log-Action -Message "$($AccountName) - $($LogDetails)"
}

###############################################
# Execution Logic
#########################################
Log-Action -Message "AutoLogon Accounts Maintenance Started with a password age threshhold of $($MaxPasswordAgeDays.ToString()) days..."

if ($SQLServerFQDN -eq "") {
    $SQLServerFQDN = $env:COMPUTERNAME
}
if ($SQLDBName -eq "") {
    $SQLDBName = "AutoLogonAccountMaintenance"
}
if ($FromAddress -eq "") {
    $FromAddress = $(Get-ADUser -Identity $env:USERNAME -Properties mail).mail # Pull from email from current account
    Log-Action -Message "Notice: Pulled from address from currently running account ($($env:USERNAME)) mail property ($($FromAddress))"
} else {
    Log-Action -Message "Notice: Using hard-set from address ($($FromAddress))"
}

# Import system.web (we use the password generation method from the system.web.security.membership class).
Add-Type -AssemblyName System.Web
# Ensure password minimum length is good
if ($PasswordLength -lt 14) {
    $PasswordLength = 14
}

# Create an array containing all autologon pc group members from the configured AD group...
#[array]$AutoLogonPCGroupMembers = $(Get-ADGroupMember -identity $AutoLogonPCsGroupName).Name
# Using the below vs Get-ADGroupMember CMDlette to avoid a 5000 object default limit reached by larger environments:
# Return all enabled autologon group member accounts where their password is outside the configured password age:
[array]$AutoLogonPCGroupMembers = Get-ADUser -LDAPFilter "(&(objectCategory=user)(memberof=$($(Get-ADGroup -Identity $AutoLogonPCsGroupName).DistinguishedName)))" –Properties "Enabled","samAccountName","pwdLastSet","whenCreated","lastLogon","PasswordExpired" | Select-Object -Property "Enabled","samAccountName","lastLogon","whenCreated",@{Name="PasswordLastSet";Expression={[datetime]::FromFileTime($_."pwdLastSet")}},"PasswordExpired" | Where-Object { (($_.Enabled -eq $true) -and ($_.PasswordLastSet -lt $(get-date).AddDays(-$($MaxPasswordAgeDays)))) } | Sort-Object -Property "PasswordLastSet"
[int]$SuccessCount = 0
if ($AutoLogonPCGroupMembers.count -gt 0) {
    if ($AutoLogonPCGroupMembers.count -ge $PerRunLimit) {
        Log-Action -Message "Maintenance will attempt to run against $($PerRunLimit.ToString()) online hosts out of a total of $($AutoLogonPCGroupMembers.count) accounts that need managed..."
    } else {
        Log-Action -Message "Maintenance will attempt to run against $($AutoLogonPCGroupMembers.count) online hosts out of a total of $($AutoLogonPCGroupMembers.count) accounts that need managed..."
    }
    
    # Run through each group member, processing autologon password updates
    foreach ($AutoLogonPC in $AutoLogonPCGroupMembers) {
        if ($PerRunLimit -gt 0) {
            Try {
                if ($MatchingCompObject = Get-ADComputer -Identity $AutoLogonPC.samAccountName -ErrorAction Stop) {
                    Try {
                        if (Test-Connection -ComputerName $AutoLogonPC.samAccountName -Count 2 -ErrorAction SilentlyContinue) {
                            try {
                                # Test PSRemoting before we continue on
                                $TestSession = Invoke-Command -ComputerName $AutoLogonPC.samAccountName -ScriptBlock {
                                    param ($PathToAutoLogonEXE)
                                    [bool]$AutologonEXEPresent = $false
                                    Try {
                                        if (!(Test-Path -Path "C:\Windows\Logs\Maintenance")) {
                                            New-Item -Path "C:\Windows\Logs\Maintenance" -ItemType Directory | Out-Null
                                        }
                                        if (Test-Path -Path $PathToAutoLogonEXE) {
                                            $AutologonEXEPresent = $true
                                        }
                                        if ($AutologonEXEPresent -eq $true) {
                                            Try {
                                                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Autologon.exe is present!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenanceTest.log" -Force -Encoding utf8 -Confirm:$false
                                                return 0
                                            } catch {
                                                return 1
                                            }
                                        } else {
                                            Try {
                                                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Autologon.exe is NOT present!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenanceTest.log" -Force -Encoding utf8 -Confirm:$false
                                                return 2
                                            } catch {
                                                return 1
                                            }
                                        }
                                    } catch {
                                        return $false
                                    }
                                } -ErrorAction Stop -ArgumentList $PathToAutoLogonEXE
                                switch ($TestSession) {
                                    0 {
                                        # Generate a New Password to use 
                                        $NewPassword = Generate-StrongPassword
                                        $NewPasswordObject =  ConvertTo-SecureString -String $NewPassword -AsPlainText -Force

                                        # Minus our Per Run Limit count by 1 since machine was online, passed connection tests, autologon EXE is installed, and autologon account follows standards.
                                        $PerRunLimit -=1

                                        # User object found, Update Password in Active Directory
                                        # Log-Action -Message "$($AutoLogonPC.samAccountName) - ($($NewPassword))"
                                        Try {
                                            Set-ADAccountPassword -identity $AutoLogonPC.samAccountName -NewPassword $NewPasswordObject -Reset -ErrorAction Stop
                                            if ($AutoLogonPC.PasswordExpired -eq $true) {
                                                Set-Aduser -ChangePasswordAtLogon $false -Identity $AutoLogonPC.samAccountName -ErrorAction Stop
                                            }
                                        
                                            Try {
                                                # Update password on target PC
                                                $LocalUpdateSessionResult = Invoke-Command -ComputerName $AutoLogonPC.samAccountName -ScriptBlock {
                                                    param ($PathToAutoLogonEXE, $DomainName, $NewPassword, $AutologonAccountName, $RebootAfterUpdate, $RebootTimeInSeconds)
                                                    if (($RebootTimeInSeconds -eq $null) -or ($RebootTimeInSeconds -eq "")) {
                                                        $RebootTimeInSeconds = 120 # Default the reboot timing value if it is null
                                                    }
                                                
                                                    # Check for Warp Drive Installation (We need to set up autologon without autologon.exe if so
                                                    $WarpDriveInstalled = $false
                                                    $ProgramFilesPath = "C:\Program Files"
                                                    # Warp Drive is x86 software, test for presence of x64 bit OS, and adjust our installation test path if necessary
                                                    if (Test-Path -Path "C:\Program Files (x86)") {
                                                        $ProgramFilesPath = "C:\Program Files (x86)"
                                                    }
                                                    if (Test-Path -Path "$($ProgramFilesPath)\Epic\WarpDrive\WarpDrive.exe") {
                                                        $WarpDriveInstalled = $true
                                                        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Epic Warp Drive is present!  Non-AutoLogon.exe method will be used!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenance.log" -Force -Encoding utf8 -Confirm:$false
                                                    }
                                                    # Handle Setting up/updating Autologon on the device
                                                    if ($WarpDriveInstalled -eq $true) {
                                                        # Handle plain-text autologon setup (Local Update Scenario B)
                                                        Try {
                                                            #Remove Auto Logon Setting (We ran into an issue with this in the past of not clearing them out before re-applying them)
			                                                $RemoteRegistry = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', "$Env:COMPUTERNAME")
			                                                $LogonKey = $RemoteRegistry.OpenSubKey("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", $true)
			                                                $LogonKey.SetValue("AutoAdminLogon", "0")
			                                                $LogonKey.SetValue("DefaultUserName", "")
			                                                $LogonKey.SetValue("DefaultPassword", "")
			                                                $LogonKey.SetValue("DefaultDomainName", "")
			                                                $LogonKey.SetValue("ForceAutoLogon", "0")
			                                                #Apply Auto Logon Setting
			                                                $LogonKey.SetValue("AutoAdminLogon", "1")
			                                                $LogonKey.SetValue("DefaultUserName", "$($AutologonAccountName.ToUpper())")
			                                                $LogonKey.SetValue("DefaultPassword", "$($NewPassword)")
			                                                $LogonKey.SetValue("DefaultDomainName", "$($DomainName.ToUpper())")
			                                                $LogonKey.SetValue("ForceAutoLogon", "1")
                                                            if ($RebootAfterUpdate -ne $false) {
			                                                    $RestartProc = Start-Process -FilePath shutdown.exe -ArgumentList "/r /f /t $($RebootTimeInSeconds) /c ""This computer is rebooting in $($($RebootTimeInSeconds / 60).ToString()) minutes due to autologon account maintenance.  This reboot is necessary for the workstation to continue functioning without being locked out.  `n`rPlease save your work as soon as possible to avoid loss of data.  You may resume your work as soon as the workstation finishes rebooting.""" -ErrorAction SilentlyContinue
                                                            }
                                                            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Autologon Setting Applied Successfully!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenance.log" -Force -Encoding utf8 -Confirm:$false
                                                            return "0B,Success"
                                                        } catch {
                                                            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Autologon Setting Failed to Apply ($($PSItem.ToString()))!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenance.log" -Force -Encoding utf8 -Confirm:$false
                                                            return "1B,$($PSItem.ToString())"
                                                        }
                                                    } else {
                                                        #Handle Autogon.exe autologon setup  (Local Update Scenario A)
                                                        Try {
                                                            $AutologonProcess = Start-Process -FilePath $PathToAutoLogonEXE -ArgumentList """/accepteula"" $($AutologonAccountName.ToUpper()) $($DomainName.ToUpper()) $($NewPassword)" -Wait -PassThru -Verbose -WindowStyle Hidden -ErrorAction Stop
                                                            switch ($AutologonProcess.ExitCode) {
                                                                0 {
                                                                    if ($RebootAfterUpdate -ne $false) {
			                                                            $RestartProc = Start-Process -FilePath shutdown.exe -ArgumentList "/r /f /t $($RebootTimeInSeconds) /c ""This computer is rebooting in $($($RebootTimeInSeconds / 60).ToString()) minutes due to autologon account maintenance.  This reboot is necessary for the workstation to continue functioning without being locked out.  `n`rPlease save your work as soon as possible to avoid loss of data.  You may resume your work as soon as the workstation finishes rebooting.""" -ErrorAction SilentlyContinue
                                                                    }
                                                                    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Autologon Setting Applied Successfully!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenance.log" -Force -Encoding utf8 -Confirm:$false
                                                                    return "0A,Success"
                                                                }
                                                               # 1 {
                                                               #     return "0A,Success" # Exit Code 1 - need to research what this is for autologon.exe (possible success code)
                                                               # }
                                                                default {
                                                                    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Autologon Setting Returned Unknown Exit Code ($($AutologonProcess.ExitCode))!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenance.log" -Force -Encoding utf8 -Confirm:$false
                                                                    return "2A,Unhandled Autologon.exe Exit Code ($($AutologonProcess.ExitCode))"
                                                                }
                                                            }
                                                        } catch {
                                                            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Autologon Setting Failed to Apply ($($PSItem.ToString()))!" | Out-File -FilePath "C:\Windows\Logs\Maintenance\AutoLogonMaintenance.log" -Force -Encoding utf8 -Confirm:$false
                                                            return "1A,$($PSItem.ToString())"
                                                        }
                                                    }
                                                } -ArgumentList $PathToAutoLogonEXE, $DomainName, $NewPassword, $AutoLogonPC.samAccountName, $RebootAfterUpdate, $RebootTimeInSeconds
                                                $LocalUpdateSessionResultReturnCode = $LocalUpdateSessionResult.Split(",")[0]
                                                $LocalUpdateSessionResultDetails = $LocalUpdateSessionResult.Split(",")[1]
                                                switch ($LocalUpdateSessionResultReturnCode) {
                                                    0A {
                                                        Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "Success" -LogDetails "Online, InvokeSessionWorked: True, AD Object Found, AD Password Update Success, Local Password Update Success (Autologon Method)"
                                                        $SuccessCount += 1
                                                    }
                                                    0B {
                                                        Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "Success (Plain Text)" -LogDetails "Online, InvokeSessionWorked: True, AD Object Found, AD Password Update Success, Local Password Update Success (PlainText Method)"
                                                        $SuccessCount += 1
                                                    }
                                                    default {
                                                        Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "LocalPasswordUpdateFailure" -LogDetails "Online, InvokeSessionWorked: True, AD Object Found, AD Password Update Success, Local Machine Password Update FAILED (Reason B: ""$($LocalUpdateSessionResult)"")! (this machine needs to be manually fixed to avoid useability issues!)"
                                                    }
                                                }
                                            } catch {
                                                Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "LocalPasswordUpdateFailure" -LogDetails "Online, InvokeSessionWorked: True, AD Object Found, AD Password Update Success, Local Machine Password Update FAILED (Reason A: $($PSItem.ToString()))! (this machine needs to be manually fixed to avoid useability issues!)"
                                            }
                                        } catch {
                                            Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "ADPasswordUpdateFailure" -LogDetails "Online, InvokeSessionWorked: True, AD Object Found, AD Password Update Failed ($($PSItem.ToString()))!"
                                        }
                                    }
                                    1 {
                                        Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "TestLogWriteError" -LogDetails "Online, Error Writing Test Log!"
                                    }
                                    2 {
                                        Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "AutologonEXEMissing" -LogDetails "Online, AutoLogon.exe is not installed!"
                                    }
                                    default {
                                        Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "Unknown Status ($($TestSession))" -LogDetails "Online, Unknown Status Returned ($($TestSession))!"
                                    }
                                }
                            } catch {
                                Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "PSRemoteError" -LogDetails "Error invoking remote session ($($PSItem.ToString()))"
                            }
                        } else {
                            Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "Offline" -LogDetails "Offline"
                        }
                    } catch {
                        Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "OnlineTestError" -LogDetails "Error Testing Connection ($($PSItem.ToString()))"
                    }
                } else {
                    Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "NonMatchingMachineAccount" -LogDetails "AD Object NOT Found (Error - Skipping Non-Standard AutoLogon Account - No computer object found matching this username)"
                }
            } catch {
                Track-MaintenanceStatus -AccountName $AutoLogonPC.samAccountName -Status "NonMatchingMachineAccount" -LogDetails "AD Object NOT Found (Error - Skipping Non-Standard AutoLogon Account - No computer object found matching this username ($($PSItem.ToString())))"
            }
        } else {
            # Nothing, limit for this run was reached
        }
    }
} else {
    Log-Action -Message "Maintenance will be skipped as there are no current accounts that need managed..."
}

if (!(Test-Path -Path "$($ReportsDir)")) {
    New-Item -Path "$($ReportsDir)\CSVs" -ItemType Directory -force -ErrorAction SilentlyContinue | Out-Null
}
# Output a report of failed/skipped/offline machines
$ReportDateStamp = Get-Date -Format 'yyyy-MM-dd-HH-mm-ss'
$ErrorMachines | Out-File -FilePath "$($ReportsDir)\CSVs\FailedAccountMaintenanceReport-$($ReportDateStamp).csv" -Encoding utf8 -NoClobber -Force
$ErrorMachines_Critical | Out-File -FilePath "$($ReportsDir)\CSVs\CriticalFailedAccountMaintenanceReport-$($ReportDateStamp).csv" -Encoding utf8 -NoClobber -Force

$ScriptHTMLReportURL = "$($ScriptReportBaseURL)\Reports"
$ScriptCSVReportURL = "$($ScriptHTMLReportURL)\CSVs"
$ScriptReportHTMLFile = "AutoLogonMaintenanceReport-$($ReportDateStamp).html"

# TODO: Generate nicely formatted HTML Emails with results attached.
# Reports Needed:
# 1. Critical Failures (non-working state PCs)
# 2. Failures
# 3. Non-Standard accounts (no matching PC name)


$ReportHTML = "<html>
              <table align=""center"" style=""width:1000px"">
                <tr style=""height:100px"">
                  <td>
                    <center><img src=""$($ScriptReportBaseURL)/Images/Notif_AutoLogonMaintenanceBanner.png""></center>
                    <h1 align=""center"">Auto Logon Account Maintenance</h1><h3 align=""center"">Configured Password Age Threshhold: $($MaxPasswordAgeDays.ToString()) days</h3>
                  </td>
                </tr>
                <tr>
                  <td>
                    <h3>Summary:</h3>
                    <ul>"
                    if ($ErrorMachines_Critical.count -gt 0) {
                        $ReportHTML = "$($ReportHTML)<li>There were <b>$($ErrorMachines_Critical.count) critical failures</b> during this maintenance cycle.  <i>These machines are likely in an unusable state, and will need manual intervention to repair.  See below for a list of critical failures!</i></li>"
                    } else {
                        $ReportHTML = "$($ReportHTML)<li>There were <b>$($ErrorMachines_Critical.count) critical failures</b> during this maintenance cycle.</li>"
                    }
                    if ($ErrorMachines_Critical.count -gt 0) {
                        $ReportHTML = "$($ReportHTML)<li>There were <b>$($ErrorMachines.count) total failures</b> during this maintenance cycle.  See below for failure details.  These are not necesarilly critical errors.</li>"
                    } else {
                        $ReportHTML = "$($ReportHTML)<li>There were <b>$($ErrorMachines.count) total failures</b> during this maintenance cycle.</li>"
                    }
                    $ReportHTML = "$($ReportHTML)<li>There were a total of <b>$($SuccessCount) autologon accounts successfully updated</b>.</li></ul>
                    <br />
                  </td>
                </tr>"
                if ($SQLErrors -gt 0) {
                    $ReportHTML = "$($ReportHTML)<tr>
                      <td>
                        <i><b>NOTICE:</b> There were issues tracking one or more items in the SQL database utilized by the autologon management solution.  Please check the logs for more details!</i>
                      </td>
                    </tr>"
                }
                $ReportHTML = "$($ReportHTML)<tr>
                  <td>
                    <br />
                  </td>
                </tr>
                <tr>
                    <td>"
                    if ($ErrorMachines_Critical.count -gt 0) {
                        $ReportHTML = "$($ReportHTML)<h3>The following computers reported back critical failures and are <u>likely in an unusable state</u>:</h3>
                        <table width='100%' style='border-collapse: collapse;'><tr style='border-bottom: 1px solid;'>
                                <td width='10%'><b>Name</b></td>
                                <td><b>Detail</b></td>
                            </tr>"
                        foreach ($ErrorMachine_Critical in $ErrorMachines_Critical) {
                            $ReportHTML = "$($ReportHTML)<tr style='border-bottom: 1px solid;'>
                                <td width='10%'><b>$($ErrorMachine_Critical.Split(',')[0])</b></td>
                                <td>$($ErrorMachine_Critical.Split(',')[1])</td>
                            </tr>"
                        }
                        $ReportHTML = "$($ReportHTML)</table><br />"
                    }
                    if ($ErrorMachines.count -gt 0) {
                        $ReportHTML = "$($ReportHTML)<h3>The following computers reported back non-critical failures:</h3>
                        <table width='100%' style='border-collapse: collapse;'><tr style='border-bottom: 1px solid;'>
                                <td width='10%'><b>Name</b></td>
                                <td><b>Detail</b></td>
                            </tr>"
                        foreach ($ErrorMachine in $ErrorMachines) {
                            $ReportHTML = "$($ReportHTML)<tr style='border-bottom: 1px solid;'>
                                <td width='10%'><b>$($ErrorMachine.Split(',')[0])</b></td>
                                <td>$($ErrorMachine.Split(',')[1])</td>
                            </tr>"
                        }
                        $ReportHTML = "$($ReportHTML)</table><br />"
                    }
                    $ReportHTML = "$($ReportHTML)
                    </td>
                </tr>
                <tr>
                    <td>
                        <br /><p>Thank you,<br />
                        $($SendingOrg)</p><br />
                        <br /><p>This report is also available at: <a href=""$($ScriptHTMLReportURL)/$($ScriptReportHTMLFile)"">$($ScriptHTMLReportURL)/$($ScriptReportHTMLFile)</a>. Also available are <a href=""$($ScriptCSVReportURL)\CriticalFailedAccountMaintenanceReport-$($ReportDateStamp).csv"">a list of any Failures in CSV format</a> and <a href=""$($ScriptCSVReportURL)\FailedAccountMaintenanceReport-$($ReportDateStamp).csv"">a list of any Critical Failures in CSV format</a></p>
                        <br /><p><b>This message is generated from an automated system.  Please do not respond to this email.</b></p>
                    </td>
                </tr>
              </table>
            </html>"



$ReportHTML | Out-File -FilePath "$($ReportsDir)\$($ScriptReportHTMLFile)" -Force

Try {
    if (($CCAddress -ne "") -and ($CCAddress -ne $null)) {
        Send-MailMessage -smtpServer $SMTPServer -To $ToAddress -from $FromAddress -Cc $CCAddress -subject $EmailTitle -Body $ReportHTML -BodyAsHtml -Attachments "$($ReportsDir)\CSVs\FailedAccountMaintenanceReport-$($ReportDateStamp).csv","$($ReportsDir)\CSVs\CriticalFailedAccountMaintenanceReport-$($ReportDateStamp).csv" -ErrorAction Stop
    } else {
        Send-MailMessage -smtpServer $SMTPServer -To $ToAddress -from $FromAddress -subject $EmailTitle -Body $ReportHTML -BodyAsHtml -Attachments "$($ReportsDir)\CSVs\FailedAccountMaintenanceReport-$($ReportDateStamp).csv","$($ReportsDir)\CSVs\CriticalFailedAccountMaintenanceReport-$($ReportDateStamp).csv" -ErrorAction Stop
    }
    Log-Action "Email: ""$($EmailTitle)"", Successfully sent."
} catch {
    Log-Action "Email: ""$($EmailTitle)"", Failed to send email from ""$($FromAddress)"" to ""$($ToAddress)"": $($PSItem.ToString())"
}

Log-Action -Message "AutoLogon Accounts Maintenance Finished.  Result: $($SuccessCount) Success, $($ErrorMachines.Count) Errors.  $($ErrorMachines_Critical.Count) Are Critical Errors.  Check above for details.  Failed Machine reports will be available at ""$($LogDir)\Reports""."