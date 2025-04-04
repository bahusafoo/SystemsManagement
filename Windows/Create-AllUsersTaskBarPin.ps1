function Create-AllUsersTaskbarPin ($ApplicationPath, $ApplicationName) {
    ################################
    # Function Version 25.4.1.2
    # Function by Sean Huggans
    ################################
    if (($ApplicationPath) -and ($ApplicationName)) {
        # Get all users profile paths:
        $ProfilePaths = New-Object System.Collections.ArrayList
        # List of excluded profiles. Note that we want to exclude Default User, but not Default - as we do want this to apply to the default profile to catch any new users who log in
        [string[]]$ExcludedDirectories = "Public", "DefaultAppPool", "Default User", "All Users"
        foreach ($UserProfilePath in [array]$(Get-ChildItem -Path "$($env:SystemDrive)\Users" -Directory -Force | Where-Object {($ExcludedDirectories -notcontains $_.Name)})) {
            $ProfilePath = $UserProfilePath.FullName
            try {
                # Build XML file path from profile
                $XMLFilePath = "$($ProfilePath)\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml"
        
                # Make path if it doesn't exist
                Log-Action -Message "Check XML Parent Path for $($XMLFilePath)"
                $XMLDir = Split-Path -Path $XMLFilePath -Parent
                if (!(Test-Path -Path $XMLDir)) {
                    Log-Action -Message "Creating non-existent XML Parent Path: $($XMLDir)"
                    New-Item -Path $XMLDir -ItemType Directory -Force | Out-Null
                }
                
                # Plant basic template if none already exists
                if (!(Test-Path -Path $XMLFilePath)) {
                    Log-Action -Message "$($UserProfilePath): Creating non-existent base template: $($XMLFilePath)"
                    $BaseXML = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
    <LayoutOptions StartTileGroupCellWidth="6" />
    <DefaultLayoutOverride>
        <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="6" />
        </StartLayoutCollection>
    </DefaultLayoutOverride>
    <CustomTaskbarLayoutCollection PinListPlacement="Replace">
        <defaultlayout:TaskbarLayout>
            <taskbar:TaskbarPinList>
                <taskbar:DesktopApp DesktopApplicationLinkPath="%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Outlook.lnk" />
                <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\File Explorer.lnk" />
                <taskbar:DesktopApp DesktopApplicationLinkPath="%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" />
            </taskbar:TaskbarPinList>
        </defaultlayout:TaskbarLayout>
    </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
                    $BaseXML | Out-File -FilePath $XMLFilePath -Encoding UTF8 -Force
                } else {
                    Log-Action -Message "$($UserProfilePath): LayoutModification.xml exists for this user"
                }

                # Load the XML file
                $XMLContent = Get-Content -Path $XMLFilePath -Raw -ErrorAction Stop
                [XML]$XML = $XMLContent
        
                # Check if LayoutModificationTemplate namespace exists
                if ($XML.LayoutModificationTemplate) {
                    # Get the CustomTaskbarLayoutCollection node
                    $CustomTaskbarLayoutCollectionNode = $XML.LayoutModificationTemplate.CustomTaskbarLayoutCollection
                    
                    if (!($CustomTaskbarLayoutCollectionNode)) {
                        # Create CustomTaskbarLayoutCollection if it doesn't exist
                        $CustomTaskbarLayoutCollectionNode = $XML.CreateElement("CustomTaskbarLayoutCollection")
                        $CustomTaskbarLayoutCollectionNode.SetAttribute("PinListPlacement", "Replace")
                        $XML.LayoutModificationTemplate.AppendChild($CustomTaskbarLayoutCollectionNode) | Out-Null
                    }

                    # Get or create the TaskbarLayout node
                    $TaskbarLayoutNode = $CustomTaskbarLayoutCollectionNode.TaskbarLayout
                    if (!($TaskbarLayoutNode)) {
                        $TaskbarLayoutNode = $XML.CreateElement("defaultlayout", "TaskbarLayout", "http://schemas.microsoft.com/Start/2014/FullDefaultLayout")
                        $CustomTaskbarLayoutCollectionNode.AppendChild($TaskbarLayoutNode) | Out-Null
                    }

                    # Get or create the TaskbarPinList node
                    $TaskbarPinListNode = $TaskbarLayoutNode.TaskbarPinList
                    if (!($TaskbarPinListNode)) {
                        $TaskbarPinListNode = $XML.CreateElement("taskbar", "TaskbarPinList", "http://schemas.microsoft.com/Start/2014/TaskbarLayout")
                        $TaskbarLayoutNode.AppendChild($TaskbarPinListNode) | Out-Null
                    }
            
                    # Create new DesktopApp element without Name attribute
                    $NewPin = $XML.CreateElement("taskbar", "DesktopApp", "http://schemas.microsoft.com/Start/2014/TaskbarLayout")
                    $NewPin.SetAttribute("DesktopApplicationLinkPath", $ApplicationPath)
            
                    # Append the new pin to TaskbarPinList
                    $TaskbarPinListNode.AppendChild($NewPin) | Out-Null
            
                    # Save the modified XML
                    $XML.Save($XMLFilePath)
                    Log-Action -Message "Success: added taskbar pin for $ApplicationPath to $XMLFilePath"
                }
                else {
                    Log-Action -Message "Error: Invalid LayoutModification XML format"
                }
            }
            catch {
                Log-Action -Message "Error: Error modifying LayoutModification.xml: $($PSItem.ToString())"
            }
        }
    } else {
        return "Error: All parameters were required but not supplied! (CHECK: ApplicationPath=""$($ApplicationPath)"", ApplicationName=""$($ApplicationName)"")"
    }
}