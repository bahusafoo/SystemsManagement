#####################################
# Set-ProtocolAndCipherSuitePosture.ps1
# Author(s): Sean Huggans
$ScriptVersion = "24.10.17.2"
######################################
# Variables
#############################
$LogFile = "Disable-InsecureProtocols.log"
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

######################################
# Execition Logic
#############################

$AllSuccess = $true
# Disable SSL 1.0
Try {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 1.0\Server' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 1.0\Server' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 1.0\Server' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 1.0\Client' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 1.0\Client' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 1.0\Client' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    Log-Action -Message "SSL 1.0 - successfully disabled"
} catch {
    Log-Action -Message "SSL 1.0 - error disabling"
    $AllSuccess = $false
}

# Disable SSL 2.0
Try {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    Log-Action -Message "SSL 2.0 - successfully disabled"
} catch {
    Log-Action -Message "SSL 2.0 - error disabling"
    $AllSuccess = $false
}

# Disable SSL 3.0
Try {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    Log-Action -Message "SSL 3.0 - successfully disabled"
} catch {
    Log-Action -Message "SSL 3.0 - error disabling"
    $AllSuccess = $false
}

# Disable TLS 1.0
Try {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    Log-Action -Message "TLS 1.0 - successfully disabled"
} catch {
    Log-Action -Message "TLS 1.0 - error disabling"
    $AllSuccess = $false
}

# Enable TLS 1.1
Try {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    Log-Action -Message "TLS 1.1 - successfully disabled"
} catch {
    Log-Action -Message "TLS 1.1 - error disabling"
    $AllSuccess = $false
}

# Enable TLS 1.2
Try {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -name 'Enabled' -value '1' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -name 'DisabledByDefault' -value 0 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -name 'Enabled' -value '1' -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -name 'DisabledByDefault' -value 0 -PropertyType 'DWord' -Force -ErrorAction Stop | Out-Null
    Log-Action -Message "TLS 1.2 - successfully enabled"
} catch {
    Log-Action -Message "TLS 1.2 - error enabling"
    $AllSuccess = $false
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
    if ([array]$(Get-TlsCipherSuite).name -contains $TLSCipherSuite) {
        $CipherSuiteCompliance = $false
        Log-Action -Message "Error: Cipher Suite ""$TLSCipherSuite"" was still discovered as enabled on this system." 
    }
}

if ($AllSuccess -eq $true) {
    if ($CipherSuiteCompliance -eq $true) {
        if (!(Test-Path -Path "HKLM:\SOFTWARE\visuaFUSION\Systems Management")) {
            New-Item -Path "HKLM:\SOFTWARE\visuaFUSION\Systems Management" -ItemType directory -Force | Out-Null
        }
        New-ItemProperty -Path "HKLM:\SOFTWARE\visuaFUSION\Systems Management" -Name "ProtocolSecurityLockDownVersion" -Value $ScriptVersion -Force | Out-Null
    }
}