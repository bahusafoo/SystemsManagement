###############################
# Link-GPOtoAllComputerOUs
# Script by Sean Huggans
# Original Date: 2016.09.14
###############################
 
Import-Module ActiveDirectory
Import-Module GroupPolicy
 
foreach ($ComputerOU in $(Get-ADOrganizationalUnit -Filter 'Name -eq "Computers"' | Sort)) {
New-GPLink -Name "<GPONAME>" -Target $ComputerOU -LinkEnabled "Yes" -confirm:$false
echo $ComputerOU.DistinguishedName
}