###########################################
# Find-InstalledApplications.ps1
# Author(s): Sean Huggans
$Script:ScriptVersion = "22.9.27.1"
###########################################
# Example script to find info on installed applications.  Checks both 64-bit and 32-bit if running on an x64 system.

# Create a new arraylist to store found applications
$InstalledApps = New-Object System.Collections.ArrayList

# Get the uninstall entries for the matching OS architecture's uninstall path
$AppRegPaths = Get-ChildItem -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
if (Test-Path -Path "$(${env:ProgramFiles(x86)})") {
    # Get the uninstall entries for the emulated 32-bit uninstall path
    $AppRegPaths += Get-ChildItem -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
}

# Loop through found applications
foreach ($AppRegPath in $AppRegPaths) {
    # Only track apps that have a displayname
    if ($($AppRegPath.GetValue("DisplayName")) -ne $null) {
        # Create an object to store information about this specific app
        $AppInfoObject = New-Object psobject
        # Find this app's displayname
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $AppRegPath.GetValue("DisplayName")
        # Find this app's publisher
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Publisher" -Value $AppRegPath.GetValue("Publisher")
        # Find this app's architecture
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Path" -Value $AppRegPath.Name.Replace('HKEY_LOCAL_MACHINE\','HKLM:\')
        if ($AppInfoObject.Path -like "*\WOW6432NODE\*") {
            $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Architecture" -Value "32-Bit"
        } else {
            $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Architecture" -Value "64-Bit"
        }
        # Find this app's version (storign as string - not all values here can be directly converted to a .net version object
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Version" -Value $AppRegPath.GetValue("DisplayVersion")
        # Find this app's URLs
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Link_Help" -Value $AppRegPath.GetValue("HelpLink")
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Link_Update" -Value $AppRegPath.GetValue("URLUpdateInfo")
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Link_About" -Value $AppRegPath.GetValue("URLInfoAbout")
        # Find this app's size
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Size" -Value $AppRegPath.GetValue("EstimatedSize")
        # Find this app's uninstall strings
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Uninstall_Quiet" -Value $AppRegPath.GetValue("QuietUninstallString")
        $AppInfoObject | Add-Member -MemberType NoteProperty -Name "Uninstall" -Value $AppRegPath.GetValue("UninstallString")
        # Add the App Info Object to the main ArrayList
        $InstalledApps.Add($AppInfoObject) | Out-Null
    }
}
$InstalledApps