#################################################################################################
# Monitor-BITSTransferStatus.ps1
# Author: Sean Huggans
# Version: 19.12.18.1
#################################################################################################
$MachineName = "SomeNameHere"
$MachineName = $env:Computername #Comment this line out to view BITS jobs on a remote host
 
do {
    if ($MachineName.ToUpper() -ne $env:COMPUTERNAME.ToUpper()) {
        if (Test-Connection $MachineName -Count 1 -Quiet) {
 
            Try {
                $Results = Invoke-Command -computername $MachineName -ScriptBlock {
                    $Results = New-object system.collections.arraylist
                    [array]$DownloadJobs = $(Get-BitsTransfer -AllUsers)
 
                    if ($DownloadJobs.count -gt 0) {
                        foreach ($DownloadJob in $DownloadJobs) {
                           $Results.Add("[$(Get-date -format 'HH:mm:ss')]$($DownloadJob.JobID) - $($DownloadJob.JobState) - $([math]::Round($($DownloadJob.BytesTransferred / 1MB),2))MB/$([math]::Round($($DownloadJob.BytesTotal / 1MB),2))MB ($([math]::Round($($DownloadJob.BytesTransferred / $DownloadJob.BytesTotal * 100),2))%)") | out-null
                        }
                    } else {
                        $Results.Add("[$(Get-date -format 'HH:mm:ss')] No BITS transfers in progress.") | out-null
                    }
                    $Results.add("There are $($DownloadJobs.count) total BITS transfers queued.") | out-null
                    return $Results
                }
                cls
                foreach ($Result in $Results) {
                    Write-Host $Result
                }
            } catch {
                Write-Host "$($MachineName) error with PSRemoting."
            }
        } else {
            Write-Host "$($MachineName) is offline."
        }
    } else {
        [array]$DownloadJobs = $(Get-BitsTransfer -AllUsers)
        cls
        if ($DownloadJobs.count -gt 0) {
            foreach ($DownloadJob in $DownloadJobs) {
                Write-host "[$(Get-date -format 'HH:mm:ss')] $($DownloadJob.JobID) - $($DownloadJob.JobState) - $([math]::Round($($DownloadJob.BytesTransferred / 1MB),2))MB/$([math]::Round($($DownloadJob.BytesTotal / 1MB),2))MB ($([math]::Round($($DownloadJob.BytesTransferred / $DownloadJob.BytesTotal * 100),2))%)"
            }
            Write-host "There are $($DownloadJobs.count) total BITS transfers queued."
        } else {
            Write-host "[$(Get-date -format 'HH:mm:ss')] No BITS transfers in progress."
        }
    }
    Start-Sleep -Seconds 10
} until ($null)