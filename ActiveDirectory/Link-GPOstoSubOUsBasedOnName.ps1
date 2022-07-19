#########################################################
#
# Name: Link-GPOstoSubOUsBasedOnName.ps1
# Author: Sean Huggans
# Version: 16.11.30.3
# Links GPOs provided in a supplied list to OUs provided
# in a supplied list.
#
#########################################################
Import-Module ActiveDirectory
Import-Module GroupPolicy
 
$GPOList = "c:\temp\gpolist.txt"
$OUsNamed = "Computers"
$LinkToAllSubOUs = $false #Change to $true to link to sub OUs of found OUs Named
$SkipOUKeyword1 = "filter1"
$SkipOUKeyword2 = "filter2"
$SkipOUKeyword3 = "filter3"
 
######################
[array]$GPOList = $(Get-Content $GPOList)
 
function LinkGPO ($title, $ListedOU) {
# Create the link on the target
New-GPLink -Name $title -Target $ListedOU -LinkEnabled "Yes" -confirm:$false
# Set the link order on the target
Set-GPLink -Name $title -Target $ListedOU -Order 1 -confirm:$false
# Set the original enforcement setting on the target
Set-GPLink -Name $title -Target $ListedOU -Enforced "No" -confirm:$false
}
 
[array]$OUFilter = Get-ADOrganizationalUnit -Filter "Name -eq '$OUsNamed'"
foreach ($ComputerOU in $OUFilter | Sort) {
    if ($LinkToAllSubOUs -eq $true) {
        $SubOUs = Get-ADOrganizationalUnit -SearchBase $ComputerOU  -SearchScope Subtree -Filter * | Select-Object DistinguishedName
        foreach ($SubOU in $SubOUs) {
            if (($SubOU.DistinguishedName -notlike "*$($SkipOUKeyword1)*") -and ($SubOU.DistinguishedName -notlike "*$($SkipOUKeyword2)*") -and ($SubOU.DistinguishedName -notlike "*$($SkipOUKeyword3)*"))  {
                write-host “———————————————-----------------------------—”
                write-host $SubOU.DistinguishedName
                write-host “———————————————-----------------------------—”
                ForEach ($title in $GPOList) {
                    write-host $title
                    LinkGPO -title $title -ListedOU $SubOU.DistinguishedName
                }
                write-host "---"
                write-host ” ”
            } else {
                write-host “———————————————-----------------------------—”
                write-host $SubOU.DistinguishedName
                write-host “———————————————-----------------------------—”
                write-host "No GPOs were linked due to filtering."
                write-host "---"
                write-host ” ”
            }
        }
    } else {
        if (($ComputerOU.DistinguishedName -notlike "*$($SkipOUKeyword1)*") -and ($SubOU.DistinguishedName -notlike "*$($SkipOUKeyword2)*") -and ($SubOU.DistinguishedName -notlike "*$($SkipOUKeyword3)*"))  {
            write-host “———————————————-----------------------------—”
            write-host $ComputerOU.DistinguishedName
            write-host “———————————————-----------------------------—”
            ForEach ($title in $GPOList) {
                write-host $title
                LinkGPO -title $title -ListedOU $ComputerOU.DistinguishedName
            }
            write-host "---"
            write-host ” ”
        } else {
            write-host “———————————————-----------------------------—”
            write-host $ComputerOU.DistinguishedName
            write-host “———————————————-----------------------------—”
            write-host "No GPOs were linked due to filtering."
            write-host "---"
            write-host ” ”
        }
    }
}