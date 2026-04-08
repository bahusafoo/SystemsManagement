###############################################################################
# Cleanup-OEMCatalogUpdatesFromWSUSInParallel.ps1
# Author(s): Sean Huggans
$ScriptVersion = "26.4.8.3"
###############################################################################
# Runs 10 background jobs, each with its own WSUS connection,
# processing batches of updates simultaneously.
###############################################################################
# Variables
######################################
$WsusServer    = "SERVERNAME.DOMAINNAME.COM"
$WsusPort      = 8530
$UseSsl        = $False
$MaxJobs       = 10

############################################################
# Execution Logic
######################################

# --- Connect and gather target update GUIDs ---
Write-Host "Connecting to WSUS and gathering targets..." -ForegroundColor Yellow
[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$Wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSsl, $WsusPort)

$AllUpdates = $Wsus.GetUpdates()
$TargetUpdates = $AllUpdates | Where-Object {
    $_.UpdateSource -eq "Other" -and
    $_.IsDeclined -eq $False -and
    $_.CompanyTitles -notcontains "Patch My PC" -and
    $_.CompanyTitles -notcontains "Local Publisher"
}

$UpdateList = @()
foreach ($Update in $TargetUpdates) {
    $UpdateList += [PSCustomObject]@{
        Guid  = $Update.Id.UpdateId.Guid
        Title = $Update.Title
    }
}

$TotalCount = $UpdateList.Count
Write-Host "Found $($TotalCount) updates to delete." -ForegroundColor Cyan

if ($TotalCount -eq 0) {
    Write-Host "Nothing to do." -ForegroundColor Green
    return
}

# --- Split into batches ---
$BatchSize = [math]::Ceiling($TotalCount / $MaxJobs)
$Batches = @()
for ($i = 0; $i -lt $TotalCount; $i += $BatchSize) {
    $End = [math]::Min($i + $BatchSize - 1, $TotalCount - 1)
    $Batches += ,@($UpdateList[$i..$End])
}

Write-Host "Split into $($Batches.Count) batches of ~$($BatchSize) updates each." -ForegroundColor Cyan
Write-Host "Launching $($Batches.Count) parallel jobs..." -ForegroundColor Yellow
Write-Host ""

# --- Scriptblock for each job ---
$JobScript = {
    param($BatchData, $Server, $Port, $Ssl)

    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
    $WsusConn = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($Server, $Ssl, $Port)

    $Success = 0
    $Errors  = 0

    foreach ($Item in $BatchData) {
        try {
            $Update = $WsusConn.GetUpdate([guid]$Item.Guid)
            $Update.Decline()
            try { $Update.ExpirePackage() } catch { }
            $WsusConn.DeleteUpdate($Item.Guid)
            $Success++
        }
        catch {
            $Errors++
        }
    }

    return [PSCustomObject]@{
        Success = $Success
        Errors  = $Errors
        Total   = $BatchData.Count
    }
}

# --- Launch jobs ---
$Jobs = @()
$BatchNum = 0
foreach ($Batch in $Batches) {
    $BatchNum++
    $Job = Start-Job -ScriptBlock $JobScript -ArgumentList @($Batch, $WsusServer, $WsusPort, $UseSsl)
    $Jobs += [PSCustomObject]@{
        Job       = $Job
        BatchNum  = $BatchNum
        BatchSize = $Batch.Count
    }
    Write-Host "  Started Job $($BatchNum): $($Batch.Count) updates" -ForegroundColor Gray
}

# --- Monitor loop ---
Write-Host ""
Write-Host "All jobs launched.  Monitoring progress..." -ForegroundColor Yellow
Write-Host ""

$TotalSuccess  = 0
$TotalErrors   = 0
$CompletedJobs = @{}
$CheckInterval = 15

while ($CompletedJobs.Count -lt $Jobs.Count) {
    # --- Check each job for completion ---
    foreach ($JobInfo in $Jobs) {
        $JobId = $JobInfo.Job.Id
        if ($CompletedJobs.ContainsKey($JobId)) { continue }

        if ($JobInfo.Job.State -eq "Completed" -or $JobInfo.Job.State -eq "Failed") {
            $Result = $JobInfo.Job | Receive-Job
            Remove-Job $JobInfo.Job

            if ($Result -ne $null) {
                $TotalSuccess += $Result.Success
                $TotalErrors  += $Result.Errors
                $StatusColor = "Green"
                if ($Result.Errors -gt 0) { $StatusColor = "Yellow" }
                Write-Host "  Job $($JobInfo.BatchNum) FINISHED: $($Result.Success) deleted, $($Result.Errors) errors (of $($Result.Total))" -ForegroundColor $StatusColor
            }
            else {
                Write-Host "  Job $($JobInfo.BatchNum) FAILED: No result returned" -ForegroundColor Red
            }

            $CompletedJobs[$JobId] = $True
        }
    }

    # --- If still running, check remaining count ---
    if ($CompletedJobs.Count -lt $Jobs.Count) {
        $RunningCount = $Jobs.Count - $CompletedJobs.Count

        # Re-query WSUS for remaining count
        $Remaining = ($Wsus.GetUpdates() | Where-Object {
            $_.UpdateSource -eq "Other" -and
            $_.IsDeclined -eq $False -and
            $_.CompanyTitles -notcontains "Patch My PC" -and
            $_.CompanyTitles -notcontains "Local Publisher"
        } | Measure-Object).Count

        $Deleted = $TotalCount - $Remaining
        $Pct = if ($TotalCount -gt 0) { [math]::Round(($Deleted / $TotalCount) * 100, 1) } else { 0 }

        Write-Host "  [$(Get-Date -Format 'HH:mm:ss')]  Jobs running: $($RunningCount)/$($Jobs.Count)  |  Deleted so far: $($Deleted)/$($TotalCount) ($($Pct)%)  |  Remaining: $($Remaining)" -ForegroundColor Cyan

        Start-Sleep -Seconds $CheckInterval
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "All jobs complete." -ForegroundColor Green
Write-Host "  Total deleted: $($TotalSuccess)" -ForegroundColor Green
Write-Host "  Total errors:  $($TotalErrors)" -ForegroundColor $(if ($TotalErrors -gt 0) { "Yellow" } else { "Green" })
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Go to Third-Party Software Update Catalogs, Sync Now on each catalog" -ForegroundColor Yellow
Write-Host "  2. Sync the SUP (Synchronize Software Updates)" -ForegroundColor Yellow
Write-Host "  3. Let your ADRs evaluate and pick up the fresh updates" -ForegroundColor Yellow