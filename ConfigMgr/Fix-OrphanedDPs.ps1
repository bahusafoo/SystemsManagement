#################################################################################
# Fix-OrphanedDPs.ps1
# Version 20.4.24.1
# Author: Sean Huggans, with tons of help from Microsoft Support cases over 
# the years, in addition to various pieces found out and about in the community
#################################################################################
 
Param(
   [Parameter(Mandatory=$true)]
   [string]$SiteCode,
   [Parameter(Mandatory=$true)]
   [string]$ProviderMachineName
)
 
$Script:PreviousLocation = "$($(Get-Location).Drive.Name):\"
if (($SiteCode -ne "") -and ($ProviderMachineName -ne "")) {
    $initParams = @{}
    if((Get-Module ConfigurationManager) -eq $null) {
        Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
    }
    if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
    }
    Set-Location "$($SiteCode):\" @initParams
 
 
    function Invoke-SQL {
        param(
            [string] $dataSource,
            [string] $database,
            [string] $sqlCommand = $(throw "Please specify a query.")
          )
 
        $connectionString = "Data Source=$dataSource; " +
                "Integrated Security=SSPI; " +
                "Initial Catalog=$database"
 
        $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
        $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
        $connection.Open()
 
        $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataSet) | Out-Null
 
        $connection.Close()
        $dataSet.Tables
 
    }
 
    #########
    Write-host "Getting the list of Valid (existing) Distribution Points..."
    [array]$DPs = $(Get-CMDistributionPoint).NetworkOSPath.replace("\","").ToUpper()
    $OrphanedDPs = New-Object System.Collections.ArrayList
 
    #########
    Write-host "Getting raw distribution point data from the site database..."
    [array]$DPs_ContentDPMap = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select ServerName FROM ContentDPMap"
    [array]$DPs_DistributionPoints = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select ServerName FROM DistributionPoints"
    [array]$DPs_DPInfo = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select ServerName FROM DPInfo WHERE NOT ServerName like '%roamer%'"
    [array]$DPs_PkgServers_G = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select NALPath FROM PkgServers_G"
    [array]$DPs_PkgServers_L = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select NALPath FROM PkgServers_L"
    [array]$DPs_PkgStatus_G = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select PkgServer FROM PkgStatus_G"
    [array]$DPs_PkgStatus_L = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select PkgServer FROM PkgStatus_L"
    [array]$DPs_SysResList = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select ServerName FROM SysResList WHERE RoleName = 'SMS Distribution Point'"
    [array]$DPs_SC_SysResUse = Invoke-SQL Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "Select * FROM SC_SysResUse WHERE RoleTypeID = 3"
 
    ###########
    if ($DPs.Count -gt 0) {
        $Filtered_ContentDPMap = new-object system.collections.arraylist
        foreach ($Result in $DPs_ContentDPMap) {
            if ($Filtered_ContentDPMap -notcontains $Result.ServerName) {
                #Write-Host $Result.ServerName
                $Filtered_ContentDPMap.Add($Result.ServerName) | Out-Null
            }
        }
        if ($Filtered_ContentDPMap.Count -ne $DPs.Count) {
            Write-Host "ContentDPMap contains $($Filtered_ContentDPMap.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_ContentDPMap)) {
                if ($DPs -notcontains $DBDistributionPoint) {
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_G WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "ContentDPMap contains $($Filtered_ContentDPMap.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
 
        $Filtered_DistributionPoints = new-object system.collections.arraylist
        foreach ($Result in $DPs_DistributionPoints) {
            if ($Filtered_DistributionPoints -notcontains $Result.ServerName) {
                #Write-Host $Result.ServerName
                $Filtered_DistributionPoints.Add($Result.ServerName) | Out-Null
            }
        }
        if ($Filtered_DistributionPoints.Count -ne $DPs.Count) {
            Write-Host "DistributionPoints contains $($Filtered_DistributionPoints.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_DistributionPoints)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_G WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "DistributionPoints contains $($Filtered_DistributionPoints.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
 
        $Filtered_DPInfo = new-object system.collections.arraylist
        foreach ($Result in $DPs_DPInfo) {
            if ($Filtered_DPInfo -notcontains $Result.ServerName) {
                #Write-Host $Result.ServerName
                $Filtered_DPInfo.Add($Result.ServerName) | Out-Null
            }
        }
        if ($Filtered_DPInfo.Count -ne $DPs.Count) {
            Write-Host "DPInfo contains $($Filtered_DPInfo.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_DPInfo)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_G WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "DPInfo contains $($Filtered_DPInfo.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
        $Filtered_PkgServers_G = new-object system.collections.arraylist
        foreach ($Result in $DPs_PkgServers_G) {
            if ($Filtered_PkgServers_G -notcontains "$($Result.NALPATH.Split("\")[2].ToUpper())") {
                #Write-Host $Result.ServerName
                $Filtered_PkgServers_G.Add("$($Result.NALPATH.Split("\")[2].ToUpper())") | Out-Null
            }
        }
        if ($Filtered_PkgServers_G.Count -ne $DPs.Count) {
            Write-Host "PkgServers_G contains $($Filtered_PkgServers_G.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_PkgServers_G)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "PkgServers_L contains $($Filtered_PkgServers_G.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
 
        $Filtered_PkgServers_L = new-object system.collections.arraylist
        foreach ($Result in $DPs_PkgServers_L) {
            if ($Filtered_PkgServers_L -notcontains "$($Result.NALPATH.Split("\")[2].ToUpper())") {
                #Write-Host $Result.ServerName
                $Filtered_PkgServers_L.Add("$($Result.NALPATH.Split("\")[2].ToUpper())") | Out-Null
            }
        }
        if ($Filtered_PkgServers_L.Count -ne $DPs.Count) {
            Write-Host "PkgServers_L contains $($Filtered_PkgServers_L.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_PkgServers_L)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "PkgServers_L contains $($Filtered_PkgServers_L.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
        $Filtered_PkgStatus_G = new-object system.collections.arraylist
        foreach ($Result in $DPs_PkgStatus_G) {
            if ($Result.PkgServer -notlike "*PRIMARY*") {
                if ($Filtered_PkgStatus_G -notcontains "$($Result.PkgServer.Split("\")[2].ToUpper())") {
                    #Write-Host $Result.ServerName
                    $Filtered_PkgStatus_G.Add("$($Result.PkgServer.Split("\")[2].ToUpper())") | Out-Null
                }
            }
        }
        if ($Filtered_PkgStatus_G.Count -ne $DPs.Count) {
            Write-Host "PkgStatus_G contains $($Filtered_PkgStatus_G.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_PkgStatus_G)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "PkgStatus_G contains $($Filtered_PkgStatus_G.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
 
        $Filtered_PkgStatus_L = new-object system.collections.arraylist
        foreach ($Result in $DPs_PkgStatus_L) {
            if ($Result.PkgServer -notlike "*PRIMARY*") {
                if ($Filtered_PkgStatus_L -notcontains "$($Result.PkgServer.Split("\")[2].ToUpper())") {
                    #Write-Host $Result.ServerName
                    $Filtered_PkgStatus_L.Add("$($Result.PkgServer.Split("\")[2].ToUpper())") | Out-Null
                }
            }
        }
        if ($Filtered_PkgStatus_L.Count -ne $DPs.Count) {
            Write-Host "PkgStatus_L contains $($Filtered_PkgStatus_L.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_PkgStatus_L)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "PkgStatus_L contains $($Filtered_PkgStatus_L.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
        $Filtered_SysResList = new-object system.collections.arraylist
        foreach ($Result in $DPs_SysResList) {
            if ($Filtered_SysResList -notcontains "$($Result.ServerName.ToUpper())") {
                #Write-Host $Result.ServerName
                $Filtered_SysResList.Add("$($Result.ServerName.ToUpper())") | Out-Null
            }
        }
        if ($Filtered_SysResList.Count -ne $DPs.Count) {
            Write-Host "SysResList contains $($Filtered_SysResList.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_SysResList)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "PkgStatus_L contains $($Filtered_SysResList.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
        $Filtered_SC_SysResUse = new-object system.collections.arraylist
        foreach ($Result in $DPs_SC_SysResUse) {
            if ($Filtered_SC_SysResUse -notcontains "$($Result.NALPATH.Split("\")[2].ToUpper())") {
                #Write-Host $Result.ServerName
                $Filtered_SC_SysResUse.Add("$($Result.NALPATH.Split("\")[2].ToUpper())") | Out-Null
            }
        }
        if ($Filtered_SC_SysResUse.Count -ne $DPs.Count) {
            Write-Host "SC_SysResUse contains $($Filtered_SC_SysResUse.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Checking differences..." -ForegroundColor Red
            foreach ($DBDistributionPoint in $($Filtered_SC_SysResUse)) {
                if ($DPs -notcontains $DBDistributionPoint) {
 
                    [array]$DPDBEntries = Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                        SET @DPName = '$DBDistributionPoint'
                        SELECT * FROM ContentDPMap WHERE ServerName = @DPName
                        SELECT * FROM DistributionPoints WHERE ServerName = @DPName
                        SELECT * FROM DPInfo WHERE ServerName = @DPName
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                        SELECT * FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                        SELECT * FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                        [int]$Entries = 0
                        foreach ($TableValue in $DPDBEntries) {
                            foreach ($Entry in $TableValue) {
                                $Entries += 1
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)")) {
                                New-Item -ItemType Directory -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)" -Force | Out-Null
                            }
                            if (!(Test-Path -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV")) {
                                $TableValue | Export-Csv -Path "C:\Temp\OrphanedDPCleanup\$($DBDistributionPoint)\$($TableValue.TableName).CSV" -NoTypeInformation -Force
                            }
                        }
                    Write-Host " - $($DBDistributionPoint) is present in the database but not exist in the console and has $($Entries) content entries in the database." -ForegroundColor Yellow
                    # Add to orphaned DP list
                    if ($OrphanedDPs -notcontains $DBDistributionPoint) {
                        $OrphanedDPs.Add($DBDistributionPoint) | Out-Null
                    }
                }
            }
        } else {
            Write-Host "SC_SysResUse contains $($Filtered_SC_SysResUse.Count) unique DP names (vs. $($DPs.Count) DPs in ConfigMgr).  Nothing else to see here." -ForegroundColor Green
        }
 
        if ($OrphanedDPs.Count -gt 0) {
            Write-Host "A total of $($OrphanedDPs.Count) non-existent DPs were located in the database." -ForegroundColor Red
            $RemoveOrphanedDPs = [windows.forms.MessageBox]::Show("Warning!  Non-Existent DPs were located in your database.  You should only remove them under the guidance to do so from Microsoft support.`n`nWould you like to remove the non-existent DPs now?", "Confirm Removal", 4)
            if ($RemoveOrphanedDPs -eq "Yes") {
                $RemoveOrphanedDPs2 = [windows.forms.MessageBox]::Show("Last Warning! You should only click yes under the guidance to do so from Microsoft support.`n`nWould you like to remove the non-existent DPs now?", "Final Confirmation of Removal", 4)
                if ($RemoveOrphanedDPs2 -eq "Yes") {
                    foreach ($OrphanedDP in $($OrphanedDPs)) {
                        if (($OrphanedDP -notlike "*CMG*") -and ($OrphanedDP -notlike "*PRIMARY*") -and ($DPs -notcontains $OrphanedDP)) {
                            Invoke-SQL -dataSource $ProviderMachineName -database "CM_$($SiteCode)" -sqlCommand "DECLARE @DPName NVARCHAR(100)
                                SET @DPName = '$OrphanedDP'
                                DELETE FROM ContentDPMap WHERE ServerName = @DPName
                                DELETE FROM DistributionPoints WHERE ServerName = @DPName
                                DELETE FROM DPInfo WHERE ServerName = @DPName
                                DELETE FROM PkgServers_G WHERE NALPath like '%' + @DPName + '%'
                                DELETE FROM PkgServers_L WHERE NALPath like '%' + @DPName + '%'
                                DELETE FROM PkgStatus_G WHERE PkgServer like '%' + @DPName + '%'
                                DELETE FROM PkgStatus_L WHERE PkgServer like '%' + @DPName + '%'
                                DELETE FROM SysResList WHERE RoleName = 'SMS Distribution Point' AND ServerName = @DPName
                                DELETE FROM SC_SysResUse WHERE NALPath like '%' + @DPName + '%' AND RoleTypeID = 3"
                           Write-Host " - Removed $($OrphanedDP)" -ForegroundColor Green
                        }
                    }
                }
            }
        } else {
            Write-Host "No non-existent DPs were located in the database.  Things look good!" -ForegroundColor Green
        }
    } else {
        Write-Host "No DPs were returned by the Get-CMDistributionPoint cmdlet.  The script will exit to avoid accidental deletion of valid distribution points." -ForegroundColor Yellow
    }
    Set-Location $Script:PreviousLocation
} 