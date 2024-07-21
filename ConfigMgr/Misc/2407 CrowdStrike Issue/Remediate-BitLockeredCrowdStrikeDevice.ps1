##########################################
# Remediate-BitLockeredCrowdStrikeDevice.ps1
# Author(s): Sean Huggans
$ScriptVersion = "24.07.20.6"
##########################################
# Variables
########################################
$MBAMIsStandalone = $false # Set to true if you are still using standalone MBAM (Not the new built-in ConfigMgr MBAM feature)
$DBUserName = 'CrowdStrikeFix' # You can  change this if you like
$DBUserPass = 'SomeSecurePassword' 
$RebootTimerSeconds = 10 # number of seconds to wait after completion (fail or success) before rebooting automatically

# Standalone MBAM Section - ignore if using New ConfigMgr Built-In MBAM
$MBAMSQLServerFQDN = "someserver.somedomain.somecompany.com"# Use ConfigMgr DB Server Here if ConfigMgr is using new integrated MBAM

# ConfigMgr Built-In MBAM (New feature, this is not the same as standalone MBAM with ConfigMgr integration)
$ConfigMgrSQLServerFQDN = "someserver.somedomain.somecompany.com" # Only use if your org is using new ConfigMgr MBAM feature (not standalone MBAM)
$ConfigMgrSiteCode = "FOO"

##############################
# NO Touch Variables
############################
$SQLServer = ""
$DBName = ""
if ($MBAMIsStandalone -ne $true) {
    $DBName = "CM_$($ConfigMgrSiteCode)"
    $SQLServer = $ConfigMgrSQLServerFQDN
} else {
    $DBName = "MBAM Recovery and Hardware"
    $SQLServer = $MBAMSQLServerFQDN
}

##########################################
# Functions
########################################

# Original function credit unknown, modified to encrypt + Trust Server Cert
function Invoke-SQL
{
	param (
		[string]$dataSource,
		[string]$database,
		[bool]$NoPassthroughAuth,
		[string]$DBuserName,
		[string]$DBuserPassword,
		[string]$sqlCommand = $(throw "Please specify a query.")
	)
	if (Test-Connection -ComputerName $dataSource -Count 2 -Quiet)
	{
		$connectionString = ""
		if ($NoPassthroughAuth -eq $true)
		{
			$connectionString = "Data Source=$dataSource; " +
			"User id=$($DBuserName);" +
			"Password=$($DBuserPassword);" +
			"Encrypt=True;" +
			"TrustServerCertificate=True;" +
			"Initial Catalog=$database"
		}
		else
		{
			$connectionString = "Data Source=$dataSource; " +
			"Integrated Security=SSPI; " +
			"Encrypt=True;" +
			"TrustServerCertificate=True;" +
			"Initial Catalog=$database"
		}
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
					Try
					{
						$UserName = $ErrorParts[1].Split("'")[1].Replace("'", "")
						$QueryError = "User ""$($UserName)"" failed to login to the database."
					}
					catch
					{
						$QueryError = "$($ErrorMessage)"
					}

				}
				default
				{
					$QueryError = "Unhandled Error: $($ErrorMessage)"
				}
			}
			$Result = "Error: A query to database ""$($database)"" on host ""$($dataSource)"" failed ($($QueryError))."
		}
	}
	else
	{
		$Result = "Error: A query to the Database ""$($database)"" on host ""$($dataSource)"" was not attempted: $($dataSource) is unreachable."
	}
	return $Result
}

##########################################
# Execution Logic
########################################

Try {
    # Get the Key ID from the local machine's OS volume
    #$OSVolume = [array]$(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.VolumeType -eq "OperatingSystem" })[0]
    # Not available by default in WinPE - Changing to plain wmi
    $OSVolume = Get-WmiObject -namespace "Root\cimv2\security\MicrosoftVolumeEncryption" -ClassName "Win32_Encryptablevolume" -ErrorAction Stop | Where-Object { ((($_.VolumeType -eq 1) -or ($_.VolumeType -eq 0)) -and (($_.ProtectionStatus -eq 2) -or ($_.ProtectionStatus -eq 1))) }
    if ($OSVolume.count -gt 1) {
        Write-host "MORE THAN ONE!  GRABBING 0 VALUE!"
        $OSVolume = [array]$(Get-WmiObject -namespace "Root\cimv2\security\MicrosoftVolumeEncryption" -ClassName "Win32_Encryptablevolume" -ErrorAction Stop | Where-Object { $_.VolumeType -eq 0 })[0]
    }
    #$OSVolumeKeyID = $($OSVolume.KeyProtector | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"}).KeyProtectorID.ToString().Replace('{','').Replace('}','')
    # Not available by default in WinPE - Changing to plain wmi
    $KeyProtectorIDs = $OSVolume.GetKeyProtectors("0").volumekeyprotectorID
    foreach ($KeyProtectorID in $KeyProtectorIDs) {
        if ($OSVolume.GetKeyProtectorType($KeyProtectorID).KeyProtectorType -eq 3) { # You may need to change the type depending on your bitlocker settings
            #Write-Host "$($KeyProtectorID) - $($OSVolume.GetKeyProtectorType($KeyProtectorID).KeyProtectorType)"
            $OSVolumeKeyID = $KeyProtectorID.ToString().Replace('{','').Replace('}','')
        }
    }
    Try {
        # Retrieve most recent Recovery Key from MBAM or ConfigMgr DB Directly using key ID
        if ($MBAMIsStandalone -eq $true) {
            # Standalone MBAM retrieval
            [array]$RecoveryKeySQL = Invoke-SQL -NoPassthroughAuth $true -DBuserName $DBUserName -DBuserPassword $DBUserPass -dataSource $SQLServer -database $DBName -sqlCommand "SELECT top 1 * FROM [RecoveryAndHardwareCore].[Keys] WHERE RecoveryKeyId LIKE '$($OSVolumeKeyID)%' order by LastUpdateTime Desc"
            if (($RecoveryKeySQL -notlike "*failed*") -and ($RecoveryKeySQL -notlike "*error*")) {
                if ($RecoveryKeySQL -ne "") {
                    $RecoveryKey = $RecoveryKeySQL[0].RecoveryKey
                } else {
                    Write-Host "Error: Key Not Found!"
                }
            } else {
                Write-Host "Error: $($RecoveryKeySQL)"
                # Recovery Key SQLFailed - Nothing for now
            }
        } else {
            # ConfigMgr MBAM version retrieval
            [array]$RecoveryKeySQL = Invoke-SQL -NoPassthroughAuth $true -DBuserName $DBUserName -DBuserPassword $DBUserPass -dataSource $SQLServer -database $DBName -sqlCommand "select Machines.Id, Machines.Name, Volumes.VolumeId, Keys.RecoveryKeyId, Keys.LastUpdateTime, RecoveryAndHardwareCore.DecryptString(Keys.RecoveryKey, DEFAULT) AS RecoveryKey
            from dbo.RecoveryAndHardwareCore_Machines Machines
            inner join dbo.RecoveryAndHardwareCore_Machines_Volumes Volumes ON Machines.Id = Volumes.MachineId
            inner join dbo.RecoveryAndHardwareCore_Keys Keys ON Volumes.VolumeId = Keys.VolumeId
            where Keys.RecoveryKeyId LIKE '$($OSVolumeKeyID)%'"
            if (($RecoveryKeySQL -notlike "*failed*") -and ($RecoveryKeySQL -notlike "*error*")) {
                if ($RecoveryKeySQL -ne "") {
                    $RecoveryKey = $RecoveryKeySQL[0].RecoveryKey
                } else {
                    Write-Host "Error: Key Not Found!"
                }
            } else {
                Write-Host "Error: $($RecoveryKeySQL)"
                # Recovery Key SQLFailed - Nothing for now
            }
        }
        if (($RecoveryKey -ne "") -and ($RecoveryKey -notlike "*error*") -and ($RecoveryKey -notlike "*failed*")) {
            # Unlock the OS Volume using retrieved Recovery Key
            Try {
                #Unlock-BitLocker -MountPoint $OSVolume.MountPoint -RecoveryPassword $RecoveryKey.Trim() -ErrorAction Stop | Out-Null
                # CMDlettes not supported in WinPE by default, changing to using plain WMI
                $UnlockResult = $OSVolume.UnlockWithNumericalPassword($RecoveryKey)
                if ($UnlockResult.ReturnValue -eq 0) { # May need to change this action based on bitlocker settings
                    Try {
                        # Remove the bad driver file from the unlocked volume's OS files
                        Remove-Item -Path "$($OSVolume.DriveLetter)\Windows\System32\drivers\CrowdStrike\C-00000291*.sys" -Force -erroraction Stop
                        Write-Host "success!"
                        "[$(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')] Remediation Success!" | Out-File -FilePath "$($OSVolume.MountPoint)\Windows\CrowdStrikeFix.txt" -Force -ErrorAction SilentlyContinue
                        # Reboot the machine
                        Start-Sleep -Seconds $RebootTimerSeconds
                        restart-computer -Force
                    } catch {
                        # Remove Bad Driver Failed - Nothing for now
                        Write-Host "Remove Bad Driver Failed ($($PSItem.ToString()))"
                        Start-Sleep -Seconds $RebootTimerSeconds
                        restart-computer -Force
                    }
                } else {
                    Write-Host "Unlock Volume failed A ($($UnlockResult.ReturnValue))"
                    # Unlock Volume failed - Nothing for now
                    Start-Sleep -Seconds $RebootTimerSeconds
                    restart-computer -Force
                }
            } catch {
                Write-Host "Unlock Volume failed B ($($PSItem.ToString()))"
                # Unlock Volume failed - Nothing for now
                Start-Sleep -Seconds $RebootTimerSeconds
                restart-computer -Force
            }
        } else {
            Write-Host "Recovery Key SQL Failed B ($($PSItem.ToString()))"
            # Recovery Key SQLFailed - Nothing for now
            Start-Sleep -Seconds $RebootTimerSeconds
            restart-computer -Force
        }
    } catch {
        Write-Host "Recovery Key SQL Failed A ($($PSItem.ToString()))"
        # Recovery Key SQLFailed - Nothing for now
        Start-Sleep -Seconds $RebootTimerSeconds
        restart-computer -Force
    }
} catch {
    # OS Volume Key ID Retrieval Failed - Nothing for now
    Write-Host "OS Volume Key ID Retrieval Failed ($($PSItem.ToString()))"
    Start-Sleep -Seconds $RebootTimerSeconds
    restart-computer -Force
}