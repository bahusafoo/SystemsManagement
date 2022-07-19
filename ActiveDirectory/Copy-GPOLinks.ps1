#########################################################
#
# Name: Copy-GPOLinks.ps1
# Original Author: Tony Murray
# Version: 16.8.17
# Original Date: 26/10/2010
# Comment: PowerShell 2.0 script to copy GPO links from
# one OU to another
#
# Modified by: Sean Huggans
# Added external list function as well as enforcement
# checking, also added human readable output.
#
#########################################################
# Import the Group Policy module
Import-Module GroupPolicy
### Set global variables
# Source for GPO links
$Source = “OU=SampleOU,DC=SampleDomain,DC=org”
 
$TargetList = “c:\temp\newOUlist.txt”
# Target where we want to set the new links
### Finished setting global variables
function CopyGPOs {
# Get the linked GPOs
$linked = (Get-GPInheritance -Target $source).gpolinks
echo “————————————————”
echo $Target
echo “————————————————”
# Loop through each GPO and link it to the target
foreach ($link in $linked)
{
    $guid = $link.GPOId
    $title = $link.DisplayName
    $order = $link.Order
    $enabled = $link.Enabled
    if ($enabled)
    {
        $enabled = “Yes”
    }
    else
    {
        $enabled = “No”
    }
    $enforced = $link.Enforced
    if ($enforced)
    {
        $enforced = “Yes”
    }
    else
    {
        $enforced = “No”
    }
    echo “———”
    echo “$title – Link Enabled: $enabled – Policy Enforced: $enforced”
    # Create the link on the target
    New-GPLink -Name $title -Target $Target -LinkEnabled $enabled -confirm:$false
    # Set the link order on the target
    Set-GPLink -Name $title -Target $Target -Order $order -confirm:$false
    # Set the original enforcement setting on the target
    Set-GPLink -Name $title -Target $Target -Enforced $enforced -confirm:$false
    echo ” ”
}
    echo ” ”
}

$DestList = Get-Content $TargetList
foreach ($ListedOU in $DestList) {
    $Target = $ListedOU
    CopyGPOs
}