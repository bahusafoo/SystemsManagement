#####################################
# Remediate-CipherSuitePosture.ps1
# Author(s): Sean Huggans
$ScriptVersion = "24.10.17.2"
######################################
# Variables
#############################
$LogFile = "CipherSuitePosture.log"
$LogDir = "C:\Windows\Logs\Compliance"
$LogPath = "$($LogDir)\$($LogFile)"

[string[]]$CipherSuitesToDisable = "TLS_RSA_WITH_3DES_EDE_CBC_SHA"

######################################
# Functions
#############################
function Log-Action ($Message, $StampDateTime, $WriteHost)
{
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

#Handle Cipher Suites
foreach ($CipherSuiteToDisable in $CipherSuitesToDisable) {
    Try {
        Disable-TlsCipherSuite -Name $CipherSuiteToDisable -ErrorAction Stop | Out-Null
        Log-Action -Message "Cipher Suite ""$($CipherSuiteToDisable)"" was disabled."
    } catch {
        Log-Action -Message "Error disabling Cipher Suite ""$($CipherSuiteToDisable)""."
    }
}

$CipherSuiteCompliance = $true
foreach ($TLSCipherSuite in $CipherSuitesToDisable) {
    Try {
        if ([array]$(Get-TlsCipherSuite -ErrorAction Stop).name -contains $TLSCipherSuite) {
            $CipherSuiteCompliance = $false
            Log-Action -Message "Error: Blacklisted Cipher Suite ""$TLSCipherSuite"" was still discovered as enabled on this system." 
        } else {
            Log-Action -Message "Info: Blacklisted Cipher Suite ""$TLSCipherSuite"" was not detected as enabled on this system." 
        }
    } catch {
        Log-Action -Message "Error: Could not retrieve cipher suites on this system." 
    }
}

if ($CipherSuiteCompliance -eq $true) {
    if (!(Test-Path -Path "HKLM:\SOFTWARE\visuaFUSION\Systems Management")) {
        New-Item -Path "HKLM:\SOFTWARE\visuaFUSION\Systems Management" -ItemType directory -Force | Out-Null
    }
    New-ItemProperty -Path "HKLM:\SOFTWARE\visuaFUSION\Systems Management" -Name "CipherSuitePostureVersion" -Value $ScriptVersion -Force | Out-Null
}