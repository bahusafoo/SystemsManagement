########################################################################################################################################################
# visuaFUSION Systems Solutions Windows 10 Toolkit
# Configure-DefaultUserProfile.ps1
########################################################################################################################################################
# This script will configure the default user profile used as a template to set up a user's
# profile  when a new user logs into a PC.  Several settings are set through the registry
# (You will want to check through the settings set below and remove what you don't want),
# as well as planting a Start Menu Layout XML file and setting the system to use it as the
# default start menu layout.

############################################################
# Script Config
############################################################
$ScriptVersion = "19.9.28.1"

############################################################
# Logging Config
############################################################
$LogFile = "Configure-DefaultUserProfile-$($ScriptVersion).log"
$LogDir = "C:\Windows\visuaFUSION\OS Management"
$LogPath = "$($LogDir)\$($LogFile)"

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

function ErrorOut-Script {
    Log-Action "Changes were not successful, see above for details."
    #exit
}

function Load-DefaultUserRegistryHive {
    $Result = Start-Process -FilePath "reg.exe" -ArgumentList "LOAD HKU\ReferenceProfile ""$($Env:SystemDrive)\Users\Default\NTUSER.DAT""" -PassThru -NoNewWindow -Wait
    switch ($Result.ExitCode) {
        0 {
            Log-Action "Default User Registry Hive Loaded Successfully"
            
            return $true
        }
        default {
            Log-Action "Error: Could Not Load Default User Registry Hive"
            return $false
        }
    }
}

function Unload-DefaultUserRegistryHive {
    # Sleep to give processes time to finish before unload
    start-sleep -Seconds 5

    $Result = Start-Process -FilePath "reg.exe" -ArgumentList "UNLOAD HKU\ReferenceProfile" -PassThru -NoNewWindow -Wait

    # Sleep to give processes time to finish after unload
    start-sleep -Seconds 5

    switch ($Result.ExitCode) {
        0 {
            Log-Action "Default User Registry Hive Unloaded Successfully"
            
            return $true
        }
        default {
            Log-Action "Error: Could Not Unload Default User Registry Hive"
            return $false
        }
    }
}

############################################################
# Execution Logic
############################################################

Log-Action "===============================================================================" -TimeStamp $false
Log-Action "= visuaFUSION Systems Solutions Windows 10 Toolkit" -TimeStamp $false
Log-Action "= Configure-DefaultUserProfile version: $($ScriptVersion)" -TimeStamp $false
Log-Action "===============================================================================" -TimeStamp $false

if (Load-DefaultUserRegistryHive -eq $true) {

    # Prevent Edge Icon From Populating on new User Profiles
    try {
        $SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
        [Microsoft.Win32.RegistryKey]$EdgeIconKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $EdgeIconKey.SetValue("DisableEdgeDesktopShortcutCreation", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $EdgeIconKey.Dispose()
        $EdgeIconKey.Close()
        Log-Action -Message "Prevent Edge Icon From Populating on new User Profiles: Success"
    } catch {
        Log-Action -Message "Prevent Edge Icon From Populating on new User Profiles: Failed"
    }

    # Set default Start Menu and Task Bar layout
    if (Test-Path -Path "$($PSScriptRoot)\LayoutModification.xml") {
        try {
            Copy-Item -Path "$($PSScriptRoot)\LayoutModification.xml" -Destination "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml" -Force -Confirm:$false -ErrorAction Stop | Out-Null
            Log-Action -Message "Set default Start Menu and Task Bar layout: Success"
        } catch {
            Log-Action -Message "Set default Start Menu and Task Bar layout: Failed"
        }
    }

    # Remove Task View Button
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        [Microsoft.Win32.RegistryKey]$TaskViewKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $TaskViewKey.SetValue("ShowTaskViewButton", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $TaskViewKey.Dispose()
        $TaskViewKey.Close()
        Log-Action -Message "Remove Task View Button: Success"
    } catch {
        Log-Action -Message "Remove Task View Button: Failed"
    }

    # Do Not Show People on the Taskbar
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People"
        [Microsoft.Win32.RegistryKey]$PeopleButtonKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $PeopleButtonKey.SetValue("PeopleBand", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $PeopleButtonKey.Dispose()
        $PeopleButtonKey.Close()
        Log-Action -Message "Do Not Show People on the TaskBar: Success"
    } catch {
        Log-Action -Message "Do Not Show People on the TaskBar: Failed"
    }

    # Show All Icons in the Notification Area (Do Not Auto Hide Them)
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\"

        [Microsoft.Win32.RegistryKey]$ShowAllNotificationIconsKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $ShowAllNotificationIconsKey.SetValue("EnableAutoTray", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $ShowAllNotificationIconsKey.Dispose()
        $ShowAllNotificationIconsKey.Close()
        Log-Action -Message "Show All Icons in the Notification Area: Success"
    } catch {
        Log-Action -Message "Show All Icons in the Notification Area: Failed"
    }

    # Show File Extentions
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"   
        [Microsoft.Win32.RegistryKey]$ShowFileExtensionsKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $ShowFileExtensionsKey.SetValue("HideFileExt", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $ShowFileExtensionsKey.Dispose()
        $ShowFileExtensionsKey.Close()
        Log-Action -Message "Show File Extentions: Success"
    } catch {
        Log-Action -Message "Show File Extentions: Failed"
    }

    # Turn on Automatic Accent Color From Background
    try {
        $SubKey = "ReferenceProfile\Control Panel\Desktop"
        [Microsoft.Win32.RegistryKey]$AccentColorFromBackgroundKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $AccentColorFromBackgroundKey.SetValue("AutoColorization", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $AccentColorFromBackgroundKey.Dispose()
        $AccentColorFromBackgroundKey.Close()
        Log-Action -Message "Turn on Automatic Accent Color From Background: Success"
    } catch {
        Log-Action -Message "Turn on Automatic Accent Color From Background: Failed"
    }

    # Set Search Box Mode to Search Icon
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        [Microsoft.Win32.RegistryKey]$SearchBoxModeKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $SearchBoxModeKey.SetValue("SearchboxTaskbarMode", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $SearchBoxModeKey.Dispose()
        $SearchBoxModeKey.Close()
        Log-Action -Message "Configure Search Box Mode: Success"
    } catch {
        Log-Action -Message "Configure Search Box Mode: Failed"
    }

    # Disable "Search The Web" for Windows Search
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"

        [Microsoft.Win32.RegistryKey]$SearchTheWebKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $SearchTheWebKey.SetValue("BingSearchEnabled", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $SearchTheWebKey.Dispose()
        $SearchTheWebKey.Close()
        Log-Action -Message "Disable Search The Web from Windows Search: Success"
    } catch {
        Log-Action -Message "Disable Search The Web from Windows Search: Failed"
    }

    # Disable Windows Search From Using Location
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        [Microsoft.Win32.RegistryKey]$SearchLocationPermissionKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $SearchLocationPermissionKey.SetValue("AllowSearchToUseLocation", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $SearchLocationPermissionKey.Dispose()
        $SearchLocationPermissionKey.Close()
        Log-Action -Message "Disable Windows Search From Using Location: Success"
    } catch {
        Log-Action -Message "Disable Windows Search From Using Location: Failed"
    }

    # Disable Cortana (Only Use Windows Search)
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        [Microsoft.Win32.RegistryKey]$CortanaConsentKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $CortanaConsentKey.SetValue("CortanaConsent", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $CortanaConsentKey.Dispose()
        $CortanaConsentKey.Close()

        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        [Microsoft.Win32.RegistryKey]$AllowCortanaKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $AllowCortanaKey.SetValue("AllowCortana", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $AllowCortanaKey.Dispose()
        $AllowCortanaKey.Close()
        Log-Action -Message "Disable Cortana (Only Use Windows Search): Success"
    } catch {
        Log-Action -Message "Disable Cortana (Only Use Windows Search): Failed"
    }

    # Disable Typing Insights in Windows
    try {
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Input\Settings"

        [Microsoft.Win32.RegistryKey]$TypingInsightsey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $TypingInsightsey.SetValue("InsightsEnabled", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $TypingInsightsey.Dispose()
        $TypingInsightsey.Close()
        Log-Action -Message "Disable Typing Insights in Windows: Success"
    } catch {
        Log-Action -Message "Disable Typing Insights in Windows: Failed"
    }

    # Set lock screen to default image lock screen image
    try {
        # Disable Content Delivery Manager Option affecting the lock screen
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        [Microsoft.Win32.RegistryKey]$ContentDeliveryManagerKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $ContentDeliveryManagerKey.SetValue("RotatingLockScreenOverlayEnabled", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $ContentDeliveryManagerKey.SetValue("RotatingLockScreenEnabled", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $ContentDeliveryManagerKey.Dispose()
        $ContentDeliveryManagerKey.Close()
        # Remove Creative Content values and set lock screen to Default File
        $SubKey = "ReferenceProfile\SOFTWARE\Microsoft\Windows\CurrentVersion\Lock Screen\Creative"
        [Microsoft.Win32.RegistryKey]$CreativeKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $CreativeKey.SetValue("LockImageFlags", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $CreativeKey.SetValue("LockScreenOptions", 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $CreativeKey.SetValue("CreativeId", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("DescriptionText", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("ActionText", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("ActionUri", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("PlacementId", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("ClickthroughToken", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("ImpressionToken", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("CreativeJson", "", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("PortraitAssetPath", "C:\Windows\Web\Screen\img100.jpg", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("LandscapeAssetPath", "C:\Windows\Web\Screen\img100.jpg", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.SetValue("HotspotImageFolderPath", "C:\Windows\Web\Screen\img100.jpg", [Microsoft.Win32.RegistryValueKind]::String)
        $CreativeKey.Dispose()
        $CreativeKey.Close()
        # Disable Windows Spotlight Features (These override the lockscreen)
        $SubKey = "ReferenceProfile\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        [Microsoft.Win32.RegistryKey]$CloudContentKey = [Microsoft.Win32.Registry]::Users.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        $CloudContentKey.SetValue("DisableWindowsSpotlightFeatures", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $CloudContentKey.Dispose()
        $CloudContentKey.Close()
        Log-Action -Message "Set lock screen to default image lock screen image: Success"
    } catch {
        Log-Action -Message "Set lock screen to default image lock screen image: Failed"
    }


    # Unload Modified Default User Registry Hive
    if (Unload-DefaultUserRegistryHive -eq $true) {
        Log-Action "Script Finished Running"
    } else {
        ErrorOut-Script
    }

} else {
    ErrorOut-Script
}

