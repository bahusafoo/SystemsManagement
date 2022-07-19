###############################
# Copy-GroupMembers.ps1
# Script by Sean Huggans
# Original Date: 2016.09.15
###############################
 
import-module ActiveDirectory
 
$SourceGroup = "MyTestGroup"
$TargetGroup = "MySecondTestGroup"
 
foreach ($Member in $(Get-ADGroupMember -Identity $SourceGroup)) {
echo $Member
Add-ADGroupMember $TargetGroup $Member.distinguishedName
}