############################################
# Generate-ADOrgTreeInfoReport.ps1
# Author(s): Sean Huggans
$ScriptVersion = "24.1.26.1"
############################################
# Variables
#################################
$StandardUserOUDN = "OU=Standard Users,OU=SomeOu,DC=SomeNetBIOS,DC=SomeDomain,DC=com"

############################################
# Execution Logic
#################################
$DateStamp = Get-Date -Format 'yyyyMMddHHmmss'
$StartLine = "DisplayName,LastName,FirstName,Description,Title,Department,Company,Manager"
Write-Host $StartLine
$StartLine | Out-File -FilePath "C:\Temp\OrgTreeInfoReport-$($DateStamp).csv" -Encoding utf8 -NoClobber -Force
foreach ($StandardUserAccount in $(Get-ADUser -Filter * -SearchBase $StandardUserOUDN -Properties * | Sort-Object -Property Department)) {
    $ManagerDisplayName = "NO MANAGER SET"
    if ($StandardUserAccount.Manager) {
        $ManagerDisplayName = $(Get-ADUser -Identity $($StandardUserAccount.Manager) -Properties *).DisplayName
    }
    $OrganizationName = "NO ORGANIZATION SET"
    if ($StandardUserAccount.Company) {
        $OrganizationName = $StandardUserAccount.Company
    }
    $DepartmentName = "NO DEPARTMENT SET"
    if ($StandardUserAccount.Department) {
        $DepartmentName = $StandardUserAccount.Department
    }
    $TitleName = "NO DEPARTMENT SET"
    if ($StandardUserAccount.Department) {
        $TitleName = $StandardUserAccount.Title
    }
    $DescriptionText = "NO DESCRIPTION SET"
    if ($StandardUserAccount.Description) {
        $DescriptionText = $StandardUserAccount.Description
    }
    $UserLine = ""
    $UserLine = "$($StandardUserAccount.DisplayName),$($StandardUserAccount.Surname),$($StandardUserAccount.GivenName),$($DescriptionText),$($TitleName),$($DepartmentName),$($OrganizationName),$($ManagerDisplayName)"
    Write-Host $UserLine
    $UserLine | Out-File -FilePath "C:\Temp\OrgTreeInfoReport-$($DateStamp).csv" -Encoding utf8 -Force -NoClobber -Append
}