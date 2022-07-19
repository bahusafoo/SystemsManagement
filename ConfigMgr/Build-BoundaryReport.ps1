###########################################################
# Build-BoundaryReport.ps1
# Author: Sean Huggans
$Version = "22.3.24.6"
# Description: Script will build a csv report of all boundaries
# in the environment, including their boundary group membership
# and which site servers (DPs, etc.) are assigned to each.
###########################################################
$SiteCode = "FOO" # Site code 
$ProviderMachineName = "SOMESERVER.YOURDOMAIN.COM" # SMS Provider machine name
$ReportOutPutPath = "C:\Temp" # Location to output the log to.  The log is already datestamped, etc. - do not include a log name here
 
$initParams = @{}
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
Set-Location "$($SiteCode):\" @initParams
 
 
[array]$BoundaryGroups = Get-CMBoundaryGroup
$OutPutArray = New-Object system.collections.arraylist
$OutPutArray.Add("Boundary Group, Boundary Name, Boundary Range, Distribution Points, Peer Cache Setting") | Out-Null
foreach ($BoundaryGroup in $($BoundaryGroups | Sort-Object -Property Name)) {
    Write-Host "$($BoundaryGroup.Name)"
    [array]$Boundaries = Get-CMBoundary -BoundaryGroupName $BoundaryGroup.Name
    foreach ($Boundary in $Boundaries) {
        $SiteSystemsString = ""
        foreach ($SiteSystem in $Boundary.SiteSystems) {
            if ($SiteSystem -like "*DP*") { #Edit this to match your DP naming scheme, or Remove this if statement all together to include all site systems assigned to the boundary group
                if (!($SiteSystemIP = [array]$(Resolve-DnsName -Name $($SiteSystem) -ErrorAction SilentlyContinue)[0].IPAddress)) {
                    $SiteSystemIP = "IP Unknown"
                }
                if ($SiteSystemsString -eq "") {
                    $SiteSystemsString = "$($SiteSystem) ($($SiteSystemIP))"
                } else {
                    $SiteSystemsString = "$($SiteSystemsString) + $($SiteSystem) ($($SiteSystemIP))"
                }
            } # If you removed the if statement above, don't forget to remove this line as well!
        }
        # Translate Boundary Group Options
        $PeerCacheSetting = "Enabled within Boundary Group"
        switch ($BoundaryGroup.Flags) {
            0 {
                $PeerCacheSetting = "Enabled within Boundary Group"
            }
            1 {
                $PeerCacheSetting = "Disabled"
            }
            2 {
                $PeerCacheSetting = "Restricted to Same Subnet"
            }
            4 {
                $PeerCacheSetting = "Enabled but Prefer Distribution Points over Peers within the same subnet"
            }
            6 {
                $PeerCacheSetting = "Restricted to Same Subnet AND Prefer Distribution Points over Peers within the same subnet"
            }
            8 {
                $PeerCacheSetting = "Enabled but Prefer Cloud Based Sources over On-Prem Sources"
            }
            8 {
                $PeerCacheSetting = "Disabled AND Prefer Cloud Based Sources over On-Prem Sources"
            }
            12 {
                $PeerCacheSetting = "Enabled Prefer Distribution Points over Peers within the same subnet AND Prefer Cloud Based Sources over On-Prem Sources"
            }
            14 {
                $PeerCacheSetting = "Restricted to Same Subnet AND Prefer Distribution Points over Peers within the same subnet AND Prefer Cloud Based Sources over On-Prem Sources"
            }
            default {
                $PeerCacheSetting = "Unknown Config Value ($($BoundaryGroup.Flags))"
            }
        }
        Write-Host " - $($Boundary.DisplayName), $($Boundary.Value), $($SiteSystemsString), Peer Cache: $($PeerCacheSetting)" 
        $OutPutArray.Add("$($BoundaryGroup.Name.Replace(',',' ')), $($Boundary.DisplayName.Replace(',',' ')), $($Boundary.Value), $($SiteSystemsString), $($PeerCacheSetting)") | Out-Null
    }
}
 
if (!(Test-Path -path $ReportOutPutPath)) {
    New-Item -Path $ReportOutPutPath -ItemType Directory -force -erroraction SilentlyContinue | Out-Null
}
$OutPutArray | Out-File -FilePath "$($ReportOutPutPath)\BoundaryInfo-$(get-date -format 'yyMMdd-HHmm').csv" -Encoding utf8 -Force