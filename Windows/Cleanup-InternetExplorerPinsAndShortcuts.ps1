###################################################
# Cleanup-InternetExplorerPinsAndShortcuts.ps1
# Authors: Sean Huggans, Doug Flaten
$ScriptVersion = "22.7.22.8"
###################################################
# Script Variables
###########################################
$LogFile = "Cleanup-InternetExplorerPinsAndShortcuts.log"
$LogDir = "C:\Windows\Logs\Maintenance"
$LogPath = "$($LogDir)\$($LogFile)"


###################################################
# Script Functions
###########################################

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
        Write-Host $Message
    }
}

###################################################
# Script Execution Policy
###########################################


$ReplaceTaskBar = '        <taskbar:DesktopApp DesktopApplicationLinkPath="%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" />'


# Loop through each user profile directory
Log-Action -Message "----------------------------------"
Log-Action -Message "Running IE entry cleanup script..."

# Check for IE shortcuts on the public desktop
Log-Action -Message "Checking for Internet Explorer shortcuts on the public desktop..."
$RemovedPublicDesktopShortcuts = $false
foreach ($ShortcutPath in $(Get-ChildItem -Path "$($env:SystemDrive)\Users\Public\Desktop" | Where-Object {$_.Extension -eq ".lnk"})) {
    $ShortcutObject = New-Object -ComObject WScript.Shell
    if ($ShortcutObject.CreateShortcut($ShortcutPath.FullName).TargetPath -like "*iexplore.exe*") {
        # Remove shortcuts to IE ONLY if there is no URL argument included (those will open with edge via the redirect to edge IE addon).
        if ($ShortcutObject.CreateShortcut($ShortcutPath.FullName).Arguments -eq "") {
            Remove-Item -Path $ShortcutPath.FullName -Force -ErrorAction SilentlyContinue
            $RemovedPublicDesktopShortcuts = $true
        }
    }
}
if ($RemovedPublicDesktopShortcuts -eq $true) {
    Log-Action -Message " - IE shortcuts were found on the public desktop and were removed, unless they included URL arguments, in which case they were left alone (those will open with edge via the redirect to edge IE addon)."
} else {
    Log-Action -Message " - No IE shortcuts were found on the public desktop, unless they included URL arguments, in which case they were left alone (those will open with edge via the redirect to edge IE addon)."
}

Log-Action -Message "Examining and cleaning up user profiles..."
$users = Get-ChildItem -Path "$($env:SystemDrive)\users" | Where-Object { (($_.PSIsContainer) -and ($_.Name -ne "Public") -and ($_.Name -notlike "Admin*")) }
foreach ($user in $users.fullname)
{
	$userlayoutpath = "$($User)\AppData\Local\Microsoft\Windows\Shell"
    $userdesktoppath = "$($User)\Desktop"
    # Define some tracking variables for this user
    $UpdatedStartMenuPins = $false
    $UpdatedTaskBarPins = $false
    $RemovedUserDesktopShortcuts = $false

    # Check for IE shortcuts on the desktop
    foreach ($ShortcutPath in $(Get-ChildItem -Path $UserDesktopPath | Where-Object {$_.Extension -eq ".lnk"})) {
        $ShortcutObject = New-Object -ComObject WScript.Shell
        if ($ShortcutObject.CreateShortcut($ShortcutPath.FullName).TargetPath -like "*iexplore.exe*") {
            # Remove shortcuts to IE ONLY if there is no URL argument included (those will open with edge via the redirect to edge IE addon).
            if ($ShortcutObject.CreateShortcut($ShortcutPath.FullName).Arguments -eq "") {
                Remove-Item -Path $ShortcutPath.FullName -Force -ErrorAction SilentlyContinue
                $RemovedUserDesktopShortcuts = $true
            }
        }
    }



    # Test for LayoutModification.xml
	if (test-path -path "$($userlayoutpath)\LayoutModification.xml")
	{
        Try {
		    $OutputLines = New-Object System.Collections.ArrayList
		    $LayoutXMLLines = Get-Content -Path "$($userlayoutpath)\LayoutModification.xml" -ErrorAction Stop
		    foreach ($LayoutXMLLine in $LayoutXMLLines)
		    {
			    $OutputLine = $LayoutXMLLine
                # Check line for IE taskbar pin	
			    If ($LayoutXMLLine -like "*Internet Explorer.lnk*")
			    {
				    $OutputLine = $ReplaceTaskBar
                    $UpdatedTaskBarPins = $true
			    }
                # Check line for IE start menu pin	
			    If ($LayoutXMLLine -like "*Microsoft.InternetExplorer.Default*")
			    {
				    $OutputLine = $LayoutXMLLine.Replace("Microsoft.InternetExplorer.Default", "MSEdge")
                    $UpdatedStartMenuPins = $true
			    }
            
			    # Ignore previous edge taskbar and Start Menu pins (If edge was already pinned, we only want one resulting pin left instead of ending up with 2)
                $EdgeAlreadyPinned = $false
                foreach ($CheckLine in $OutputLines.ToArray()) {
                    # taskbar pin
                    if (($LayoutXMLLine -like "*<taskbar:*") -and ($LayoutXMLLine -like "*Edge*")) {
                        $EdgeAlreadyPinned = $true
                    }
                    # Start Menu Pin
                    if ($LayoutXMLLine -like "*MSEdge*") {
                        $EdgeAlreadyPinned = $true
                    }
                }
                # If not already pinned, add it
                if ($EdgeAlreadyPinned -ne $true) {
                    $OutputLines.Add($OutputLine) | Out-Null
                }
		    }
            # Attempt to write our changes to the user's actual layoutmodification.xml file
            Try {
		        $OutputLines | Out-File -FilePath "$($userlayoutpath)\LayoutModification.xml" -Encoding utf8 -Force -erroraction Stop
                Log-Action -Message " - $($userlayoutpath): Finished! (Found/Updated Taskbar Pins: $($UpdatedTaskBarPins), Found/Updated Start Menu Pins: $($UpdatedStartMenuPins), Found/Updated User Desktop Shortcuts: $($RemovedUserDesktopShortcuts))"
            } Catch {
                Log-Action -Message " - $($userlayoutpath): Error Saving Layout File! (Found/Updated User Desktop Shortcuts: $($RemovedUserDesktopShortcuts))"
            }        
        } Catch {
            Log-Action -Message " - $($userlayoutpath): Error Openning Layout File! (Found/Updated User Desktop Shortcuts: $($RemovedUserDesktopShortcuts))"
        }
	}
	Else
	{
		Log-Action -Message " - $($userlayoutpath): Skipped (Layout Not Found)"
	}
}


Log-Action -Message "IE entry cleanup script finished."