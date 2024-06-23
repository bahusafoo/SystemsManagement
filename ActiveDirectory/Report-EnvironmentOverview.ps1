############################################
# Report-EnvironmentOverview.ps1
# Author(s): Sean Huggans
$ScriptVersion = "24.1.11.1"
# In Progress
############################################
# Variables
####################################

############################################
# Functions
####################################
function Report-DomainAdmins {
    Write-host "Domain Admins (recursive):"
    [array]$DomainAdmins = Get-ADGroupMember -Identity "Domain Admins" -Recursive
    foreach ($Member in $DomainAdmins) {
        if ($Member.objectClass -eq "user") {
            $UserObject = Get-ADUser -Identity $Member.SamAccountName
            if ($UserObject.enabled -eq $true) {
                Write-Host "$($Member.SamAccountName), $($Member.name)"
            }
        }
    }
}
############################################
# Execution Logic
####################################
Report-DomainAdmins