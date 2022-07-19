# ===============================================
# Decline-SupersededUpdatesWithExclusionPeriod.ps1 
# Script to decline superseeded updates in WSUS.
# Original Script from Microsoft Blog
# Modified Version by Sean Huggans
# Version: 18.5.13.1
# ===============================================
 
# Script Modified to email report instead of displaying results and creating an external list file.
 
 
 
########################
 
#Parameters
 
############
 
$UpdateServer = SERVERNAME"
 
$Port = 8530
 
$UseSSL = $False
 
$SkipDecline = $False #$true
 
$DeclineLastLevelOnly = $False
 
$ExclusionPeriod = 30
 
$SMTPServer = "SMTPSERVERFQDN"
 
$To = "MAILTOEMAILADDRESS"
 
$FROM = "FROMADDRESS"
 
############
 
#Other Defined Items
 
########################
 
function Invoke-SQL
 
{
 
    param ($dataSource,
 
    $database,
 
    $sqlCommand)
 
 
 
    $connectionString = "Data Source=$dataSource; " +
 
    "Integrated Security=SSPI; " +
 
    "Initial Catalog=$database"
 
 
 
    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
 
    $command = new-object system.data.sqlclient.sqlcommand($sqlCommand, $connection)
 
    $command.CommandTimeout = 0
 
    $connection.Open()
 
 
 
    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
 
    $dataset = New-Object System.Data.DataSet
 
    $adapter.Fill($dataSet) | Out-Null
 
 
 
    $connection.Close()
 
    $dataSet.Tables
 
    #Usage: Invoke-SQL -datasource "<server>" -database "CfgMgrApps" -sqlCommand "Select * From Schedule_$($Minutes);"
 
}
 
 
 
 
 
 
 
#Rebuild WSUS DB Indexes
 
$PreReBuildReIndexResults = new-object System.Collections.ArrayList
 
try {
 
    $StartTime = Get-Date
 
    Invoke-SQL -dataSource $UpdateServer -database SUSDB -sqlCommand "Exec sp_msforeachtable 'DBCC DBREINDEX (''?'')';"
 
    $EndTime = Get-Date
 
    $RunTime = New-TimeSpan -Start $StartTime -End $EndTime
 
    $PreReBuildReIndexResults.Add("Rebuilding DB Indexes: Succeeded. ($($RunTime.Seconds) seconds)") | Out-Null
 
} catch {
 
    $PreReBuildReIndexResults.Add("Rebuilding DB Indexes: FAILED.") | Out-Null
 
}
 
try {
 
    $StartTime = Get-Date
 
    Invoke-SQL -dataSource $UpdateServer -database SUSDB -sqlCommand "Exec sp_msforeachtable 'update statistics ? with fullscan';"
 
    $EndTime = Get-Date
 
    $RunTime = New-TimeSpan -Start $StartTime -End $EndTime
 
    $PreReBuildReIndexResults.Add("Update Statistics: Succeeded. ($($RunTime.Seconds) seconds)") | Out-Null
 
} catch {
 
    $PreReBuildReIndexResults.Add("Update Statistics: FAILED.") | Out-Null
 
}
 
 
 
 
 
#Decline Superseded Updates
 
$Results = new-object System.Collections.ArrayList
 
 
 
$Results.Add( "") | Out-Null
 
 
 
if ($SkipDecline -and $DeclineLastLevelOnly) {
 
    $Results.Add( "Using SkipDecline and DeclineLastLevelOnly switches together is not allowed.") | Out-Null
 
       $Results.Add( "") | Out-Null
 
    return $results
 
}
 
 
 
 
 
try {
 
 
 
    if ($UseSSL) {
 
        $Results.Add( "Connecting to WSUS server $UpdateServer on Port $Port using SSL... ") | Out-Null
 
    } Else {
 
        $Results.Add( "Connecting to WSUS server $UpdateServer on Port $Port... ") | Out-Null
 
    }
 
 
 
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
 
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($UpdateServer, $UseSSL, $Port);
 
}
 
catch [System.Exception]
 
{
 
    $Results.Add( "Failed to connect.") | Out-Null
 
    $Results.Add( "Error: $($_.Exception.Message)") | Out-Null
 
    $Results.Add( "Please make sure that WSUS Admin Console is installed on this machine") | Out-Null
 
       $Results.Add( "") | Out-Null
 
    $wsus = $null
 
}
 
 
 
if ($wsus -eq $null) { return $results}
 
 
 
$Results.Add( "Connected.") | Out-Null
 
 
 
$countAllUpdates = 0
 
$countSupersededAll = 0
 
$countSupersededLastLevel = 0
 
$countSupersededExclusionPeriod = 0
 
$countSupersededLastLevelExclusionPeriod = 0
 
$countDeclined = 0
 
 
 
$Results.Add( "Getting a list of all updates... ") | Out-Null
 
 
 
try {
 
       $allUpdates = $wsus.GetUpdates()
 
}
 
 
 
catch [System.Exception]
 
{
 
       $Results.Add( "Failed to get updates.") | Out-Null
 
       $Results.Add( "Error: $($_.Exception.Message)") | Out-Null
 
    $Results.Add( "<b>If this operation timed out, please decline the superseded updates from the WSUS Console manually.</b>") | Out-Null
 
       $Results.Add( "") | Out-Null
 
       return $Results
 
}
 
 
 
$Results.Add( "Done.<br />") | Out-Null  
 
$Results.Add( "<b><u>The following Updates are Superseded:</u></b>") | Out-Null
 
foreach($update in $allUpdates) {
 
 
 
    $countAllUpdates++
 
 
 
    if ($update.IsDeclined) {
 
        $countDeclined++
 
    }
 
 
 
    if (!$update.IsDeclined -and $update.IsSuperseded) {
 
        $countSupersededAll++
 
 
 
        if (!$update.HasSupersededUpdates) {
 
            $countSupersededLastLevel++
 
        }
 
 
 
        if ($update.CreationDate -lt (get-date).AddDays(-$ExclusionPeriod))  {
 
                  $countSupersededExclusionPeriod++
 
                     if (!$update.HasSupersededUpdates) {
 
                           $countSupersededLastLevelExclusionPeriod++
 
                     }
 
        }          
 
 
 
        $Results.Add("$($countSupersededAll). Update: $($update.Title), Creation Date: $($update.CreationDate)")| Out-Null     
 
 
 
    }
 
}  
 
 
 
$Results.Add( "") | Out-Null   
 
$Results.Add( "<b><u>Update Summary:</b></u>") | Out-Null
 
 
 
$Results.Add( "<b>Total Updates:</b> $($countAllUpdates)") | Out-Null   
 
$Results.Add( "Non-Declined: $($countAllUpdates - $countDeclined)") | Out-Null   
 
$Results.Add( "<b>Total Superseded:</b> $($countSupersededAll)") | Out-Null   
 
$Results.Add( "Superseded (Intermediate): $($countSupersededAll - $countSupersededLastLevel)") | Out-Null   
 
$Results.Add( "Superseded (Last Level): $($countSupersededLastLevel)") | Out-Null   
 
$Results.Add( "Superseded (Older than $($ExclusionPeriod) days): $($countSupersededExclusionPeriod)") | Out-Null   
 
$Results.Add( "Superseded (Last Level Older than $($ExclusionPeriod) days): $($countSupersededLastLevelExclusionPeriod)") | Out-Null   
 
$Results.Add( "") | Out-Null   
 
 
 
$i = 0
 
if (!$SkipDecline) {
 
 
 
    $Results.Add( "SkipDecline flag is set to $($SkipDecline). Continuing with declining updates <b>older than $($ExclusionPeriod) days</b>...") | Out-Null   
 
    $updatesDeclined = 0
 
 
 
    if ($DeclineLastLevelOnly) {
 
        $Results.Add( "  DeclineLastLevel is set to True. Only declining <b>last level</b> superseded updates." ) | Out-Null   
 
 
 
        foreach ($update in $allUpdates) {
 
 
 
            if (!$update.IsDeclined -and $update.IsSuperseded -and !$update.HasSupersededUpdates) {
 
              if ($update.CreationDate -lt (get-date).AddDays(-$ExclusionPeriod))  {
 
                         $i++
 
                           $percentComplete = "{0:N2}" -f (($updatesDeclined/$countSupersededLastLevelExclusionPeriod) * 100)
 
                           $Results.Add("Declining update #$i/$countSupersededLastLevelExclusionPeriod - $($update.Title). $($percentComplete)% complete") | Out-Null   
 
 
 
                try
 
                {
 
                    $update.Decline()                   
 
                    $updatesDeclined++
 
                }
 
                catch [System.Exception]
 
                {
 
                    $Results.Add( "Failed to decline update $($update.Id.UpdateId.Guid). Error: $($_.Exception.Message)") | Out-Null   
 
                }
 
              }            
 
            }
 
        }       
 
    }
 
    else {
 
        $Results.Add( "  DeclineLastLevel is set to False. Declining <b>all</b> superseded updates.") | Out-Null   
 
 
 
        foreach ($update in $allUpdates) {
 
 
 
            if (!$update.IsDeclined -and $update.IsSuperseded) {
 
              if ($update.CreationDate -lt (get-date).AddDays(-$ExclusionPeriod))  {  
 
 
 
                           $i++
 
                           $percentComplete = "{0:N2}" -f (($updatesDeclined/$countSupersededAll) * 100)
 
                           $Results.Add("Declining update #$i/$countSupersededAll - $($update.Title). $($percentComplete)% complete") | Out-Null   
 
                try
 
                {
 
                    $update.Decline()
 
                    $updatesDeclined++
 
                }
 
                catch [System.Exception]
 
                {
 
                    $Results.Add( "Failed to decline update $($update.Id.UpdateId.Guid). Error: $($_.Exception.Message)") | Out-Null   
 
                }
 
              }             
 
            }
 
        }  
 
 
 
    }
 
 
 
    $Results.Add( "  Declined $updatesDeclined updates.") | Out-Null   
 
    if ($updatesDeclined -ne 0) {
 
        Copy-Item -Path $outSupersededList -Destination $outSupersededListBackup -Force  
 
    }
 
 
 
}
 
else {
 
    $Results.Add( "SkipDecline flag is set to $SkipDecline. Skipped declining updates.") | Out-Null   
 
}
 
 
 
$Results.Add( "") | Out-Null   
 
$Results.Add( "Done.") | Out-Null   
 
$Results.Add( "") | Out-Null
 
 
 
#Rebuild WSUS DB Indexes
 
$PostReBuildReIndexResults = new-object System.Collections.ArrayList
 
try {
 
    $StartTime = Get-Date
 
    Invoke-SQL -dataSource $UpdateServer -database SUSDB -sqlCommand "Exec sp_msforeachtable 'DBCC DBREINDEX (''?'')';"
 
    $EndTime = Get-Date
 
    $RunTime = New-TimeSpan -Start $StartTime -End $EndTime
 
    $PostReBuildReIndexResults.Add("Rebuilding DB Indexes: Succeeded. ($($RunTime.Seconds) seconds)") | Out-Null
 
} catch {
 
    $PostReBuildReIndexResults.Add("Rebuilding DB Indexes: FAILED.") | Out-Null
 
}
 
try {
 
    $StartTime = Get-Date
 
    Invoke-SQL -dataSource $UpdateServer -database SUSDB -sqlCommand "Exec sp_msforeachtable 'update statistics ? with fullscan';"
 
    $EndTime = Get-Date
 
    $RunTime = New-TimeSpan -Start $StartTime -End $EndTime
 
    $PostReBuildReIndexResults.Add("Update Statistics: Succeeded. ($($RunTime.Seconds) seconds)") | Out-Null
 
} catch {
 
    $PostReBuildReIndexResults.Add("Update Statistics: FAILED.") | Out-Null
 
}
 
 
 
 
 
#If anything was done, trigger a delta sync
 
$SyncTriggered = "No"
 
if (($SkipDecline -ne $true) -and ($updatesDeclined -gt 0)) {
 
    try {
 
        new-item -ItemType file -Path "D:\Program Files\Microsoft Configuration Manager\inboxes\wsyncmgr.box\SELF.SYN" -Force -Confirm:$False -ErrorAction Stop
 
        #$null | Out-File "D:\Program Files\Microsoft Configuration Manager\inboxes\wsyncmgr.box\FULL.SYN" -ErrorAction Stop
 
        $SyncTriggered = "Yes"
 
    } catch {
 
        $SyncTriggered = "Error"
 
    }
 
}
 
 
 
 
 
[string]$html = "<HTML>`n<Body>A cleanup job was performed against the top level SUPs WSUS instance to decline superseded updates.  This keeps the size of the WSUS database each client must evaluate against down and allows those evaluations to consume less resources and finish more quickly.  The report of superseded updates is below.<br />"
 
#Add Pre-Task Rebuild Index/Update Stats Results to Email
 
$html = "$($html)<br /><b><u>Pre-Task ReIndex/Update Stats Job:</u></b><br />"
 
foreach ($ResultLine in $PreReBuildReIndexResults) {
 
    $html = "$($html)`n$($ResultLine)<br />`n"
 
}
 
$html = "$($html)<br />"
 
#Add Declined Update Results to Email
 
foreach ($ResultLine in $Results) {
 
    $html = "$($html)`n$($ResultLine)<br />`n"
 
}
 
#Add Post-Task Rebuild Index/Update Stats Results to Email
 
$html = "$($html)<br /><b><u>Post-Task ReIndex/Update Stats Job:</u></b><br />"
 
foreach ($ResultLine in $PostReBuildReIndexResults) {
 
    $html = "$($html)`n$($ResultLine)<br />`n"
 
}
 
$html = "$($html)<br />"
 
 
 
switch ($SyncTriggered) {
 
    "Yes" {
 
        $html = "$($html)`n`nBecause Changes were made in WSUS, a delta sync in SCCM has been triggered.  This trigger was successful."
 
    }
 
    "No" {
 
        $html = "$($html)`n`nNo Changes were made in WSUS, therefore, no sync has been triggered in SCCM."
 
    }
 
    "Error" {
 
        $html = "$($html)`n`nBecause Changes were made in WSUS, a delta sync in SCCM was attempted, however, this trigger has failed."
 
    }
 
}
 
$html = "$($html)<br />`n"
 
 
 
$html = "$($html)<h3>End of Report.</h3><br />`n</body>`n</HTML>"
 
#Write-Host $html
 
 
#If you want an email sent, enable this, otherwise leave the out-file active and this commented out.
#Send-MailMessage -To $To -from $FROM -subject "SCCM SUP/WSUS Clean Up Report" -smtpServer $SMTPServer -Body $html -BodyAsHtml
 
$html | out-file "C:\Temp\WSUS-Cleanup-$(get-date -format 'yyyy.MM.dd-HH-mm-ss').html"