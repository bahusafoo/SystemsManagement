##################################
# Find-SetGPOSettingsViaKeyWords.ps1
# Script by Sean Huggans
# Original Date 2016.09.13
# This Script will generate two logs - 
# one will be a list of GPOs containing 
# settings matching the search terms provided, 
# the second will be a log of those with GPOs, 
# with a breakdown of the groups with 
# ApplyGpo Permission on the GPO, as well as 
# the option to include groups with GPORead 
# permission.
##################################
 
Using NameSpace system
import-module ActiveDirectory
import-module GroupPolicy
 
#TODO: Take input Params
 
[String]$Domain = "Corp.FMScug.net"
[String]$ReportsPath = "C:\Temp\GPOReports\HTMLReports"
[String]$OutputPath = "C:\Temp\GPOReports\Results"
 
New-Item -ItemType directory -Path $ReportsPath -ErrorAction Ignore > $null
New-Item -ItemType directory -Path $OutputPath -ErrorAction Ignore > $null
 
echo ""
echo "********************************"
echo "Building GPO Reports..."
echo "********************************"
echo ""
 
foreach ($GPO in $(Get-GPO -all)) {
$GPOName = $GPO.DisplayName
$Path = "$ReportsPath\$GPOName.html"
Get-GPOReport -Name $GPO.DisplayName -ReportType Html -Domain $Domain -Path $Path
}
 
echo ""
echo "***********************************************"
echo "Beginning Search on GPO Reports..."
echo "***********************************************"
echo ""
 
filter KeyWords( [String[]]$SearchTerms ) {
echo "" > "$OutputPath\SearchResults.log"
echo "" > "$OutputPath\ApplyGroups.log"
echo "" > "$OutputPath\GPOs Matching Search Terms.log"
echo "GPO search results:" 
echo "GPO search results:" >> "$OutputPath\SearchResults.log"
$GPOList = New-Object System.Collections.ArrayList
$GroupList = New-Object System.Collections.ArrayList
 foreach($SearchTerm in $SearchTerms) {
  foreach ($file in Get-ChildItem $ReportsPath | Select-String -Pattern $SearchTerm | Select-Object -Unique path) {
    $GPOName = $file.path.Replace("$ReportsPath\","").replace(".html","")
    if ($GPOList -notcontains $GPOName) {
     $GPOGUID = $(Get-GPO -name "$GPOName").Id
     $GPOLinks = Get-ADOrganizationalUnit -LDAPFilter "(gPLink=*$GPOGUID*)"
     $GPOPerms = Get-GPPermissions -All -GUId $GPOGUID
     #Add GPO item to GPOList (Avoid Duplicates)
     $GPOList.add($GPOName) > $null
     # On Screen Display and Full Log
     echo "======"
     echo "======" >> "$OutputPath\GPOs Matching Search Terms.log"
     echo "GPO Name: $GPOName"
     echo "GPO Name: $GPOName" >> "$OutputPath\GPOs Matching Search Terms.log"
     echo "------"
     echo "------" >> "$OutputPath\GPOs Matching Search Terms.log"
     echo "GPO Permissions:"
     echo "GPO Permissions:" >> "$OutputPath\GPOs Matching Search Terms.log"
     foreach ($GPOPermObject in $GPOPerms.Trustee) {
      $GPOObjectName = $GPOPermObject.Name
      $GPOObjectPerms = Get-GPPermissions -Name $GPOName -TargetName "$GPOObjectName" -TargetType Group
      $GPOObjectPermsLevel = $GPOObjectPerms.Permission
      if ($GPOObjectPermsLevel -contains ("GpoApply")) {
       if ($GroupList -notcontains ($GPOObjectName)) {
       echo "$GPOObjectName : $GPOObjectPermsLevel"
       echo "$GPOObjectName : $GPOObjectPermsLevel" >> "$OutputPath\GPOs Matching Search Terms.log"
       $GroupList.add($GPOObjectName) > $null
       }
      }
    ## Uncomment to include READ permission listing
    ##  if ($GPOObjectPermsLevel -contains ("GpoRead")) {
    ##   if ($GroupList -notcontains ($GPOObjectName)) {
    ##    echo "$GPOObjectName : $GPOObjectPermsLevel"
    ##    echo "$GPOObjectName : $GPOObjectPermsLevel" >> "$OutputPath\GPOs Matching Search Terms.log"
    ##   }
    ##  }
    }
   echo "======"
   echo "======" >> "$OutputPath\GPOs Matching Search Terms.log"
   echo ""
   echo "" >> "$OutputPath\GPOs Matching Search Terms.log"
 
   # GPO List Log
   echo $GPOName >> "$OutputPath\SearchResults.log"
   }
  }
 }
}
KeyWords 'Phrase 1','Phrase2'
 
echo ""
echo ""
echo "A list of GPOs containing settings matching the search terms has been saved to $OutputPath\SearchResults.log."
echo "The entire formatted output from this script has been saved to $OutputPath\\GPOs Matching Search Terms.log."