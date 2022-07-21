########################################################################################################################################################
# visuaFUSION Systems Solutions Windows 10 Toolkit
# Configure-DefaultLockscreen.ps1
########################################################################################################################################################
# This script will clear out Administrator Profile's lockscreen settings
# and then set a lock screen image policy to set the policy

############################################################
# Script Config
############################################################
$ScriptVersion = "19.6.9.1"
#$Script:RegistryObject = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','default')

############################################################
# Logging Config
############################################################
$LogFile = "Configure-DefaultLockscreen.log"
$LogDir = "C:\Windows\visuaFUSION\OS Management"
$LogPath = "$($LogDir)\$($LogFile)"

############################################################
# Functions
############################################################

function Log-Action ($Message, $TimeStamp)
{
    ################################
    # Function Version 18.4.14.1
    # Function by Sean Huggans
    ################################
	New-Item -ItemType directory -Path $LogDir -Confirm:$false -Force -ErrorAction SilentlyContinue | out-null
    if (($TimeStamp -ne $false) -and ($TimeStamp -ne "no")) {
	    "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File $LogPath -Append
    } else {
        "$($Message)" | Out-File $LogPath -Append
    }
}

function Set-AppRegPermissions ($Setting, $RegPath) {
########################################
# Modify Registry Permissions
# Function Date: 18.10.2.1
# Function by Chad Loevinger
########################################
    if (($Setting) -and ($RegPath)) {
        try {
            Log-Action -Message "Setting ""$($Setting)"" permission on ""$($RegPath)""..."
            $acl = Get-Acl "$($RegPath)"
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule ("everyone","$($Setting)","Allow")
            $acl.SetAccessRule($rule)
            $acl | Set-Acl -Path "$($RegPath)"
            Log-Action -Message " - Success!"
            return $true
        } catch {
            Log-Action -Message " - Error!"
            return $false
        }
    } else {
        Log-Action -Message " - Error! (Incomplete Parameters Passed)"
        return $false
    }
}

function Set-RegistryValue ($ValuePath, $ValueName, $ValueData) {
    ###########################################################
    # Set-RegistryValue
    # Function by: Sean Huggans
    # Function Date: 2018.08.14
    ###########################################################
    # Function will set a registry value, creating the key path if it does not already exist.
    # Usage Example: Set-RegistryValue -ValuePath "Software\Tests\Test 3" -ValueName "Test Value 4" -ValueData "Test Data REVISED 2"
    if (($ValuePath -ne "") -and ($ValueName -ne "") -and ($ValueData -ne "")) {
        $RegistryObject = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $env:COMPUTERNAME)
        $RegistryObject.CreateSubKey("$($ValuePath)") | Out-Null
        $RegistryKey = $RegistryObject.OpenSubKey("$($ValuePath)", $true)
        try {
            $RegistryKey.SetValue("$($ValueName)", "$($ValueData)", [Microsoft.Win32.RegistryValueKind]::String) | Out-Null
            Log-Action "Registry Add: $($ValuePath)\$($ValueName) ($($ValueData)): Success!"
            return $true
        } catch {
            Log-Action "Registry Add: $($ValuePath)\$($ValueName) ($($ValueData)): Error!"
            return $false
        }
    } else {
        Log-Action "Error: Set-RegistryValue was called with missing parameters!"
        return $false
    }
}

############################################################
# Execution Logic
############################################################

if (test-path -path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\S-1-5-18\AnyoneRead\LockScreen") {
    Set-AppRegPermissions -Setting FullControl -RegPath "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\S-1-5-18\AnyoneRead\LockScreen"
    Remove-Item -Path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\S-1-5-18\AnyoneRead\LockScreen\CacheFormat_P" -force
    Remove-Item -Path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\S-1-5-18\AnyoneRead\LockScreen\GPImagePath_P" -force
    Remove-Item -Path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\S-1-5-18\AnyoneRead\LockScreen\SizeX_P" -force
    Remove-Item -Path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\S-1-5-18\AnyoneRead\LockScreen\SizeY_P" -force
    Log-Action "Admin Profile LockScreen Settings Were Removed"
} else {
    Log-Action "Admin Profile LockScreen Settings Do Not Exist, Skipped Removal"
}

if ($(Set-RegistryValue -ValuePath "SOFTWARE\Policies\Microsoft\Windows\Personalization" -ValueName "LockScreenImage" -ValueData "C:\Windows\Web\Screen\img103.jpg") -eq $true) {
    Log-Action "Lock Screen was set!"
} else {
    Log-Action "Error Setting Locke Sreen!"
}



