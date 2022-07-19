################################################################################################################################
# Run-GPUpdateSilentlyWithLoggingAndSuccessOutput.ps1
# Script Author: Sean Huggans
# Script Version 18.06.05.04
################################################################################################################################
# Variables
################
$LogDir = "C:\Temp\System Compliance"
$LogName = "GPUpdate"
$LogPath = "$($LogDir)\$($LogName).log"
 
###################
# Functions
###################
function Log-Action ($Message) {
    if (!(test-path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Confirm:$false -Force | Out-Null
    }
    "[ $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File -FilePath $LogPath -Force -Append
}
 
try {
    $JobName = "GPUpdate$PC-$(Get-Date -format "yyyyMMddHHmmss")"
    Start-Job -Name $JobName -ScriptBlock { & echo n | GPUpdate /Force /wait:0 } | Out-Null
    $count = 60
 
    do {
        switch ($(Get-Job -Name $JobName).State) {
            "Running" {
                Start-Sleep -Seconds 1
            }
            "Completed" {
                Log-Action "GPUpdate Invoked."
                Remove-job -Name $JobName -Confirm:$false -Force -erroraction SilentlyContinue
                return "Success"
            }
            "Failed" {
                Remove-job -Name $JobName -Confirm:$false -Force -erroraction SilentlyContinue
                return "Failed (GPUpdate Failed)"
            }
        }
        $count -=1
    } until ($count -le 0)
    Remove-job -Name $JobName -Confirm:$false -Force -erroraction SilentlyContinue
    return "Failed (Time Exceeded 60 Seconds)"
} catch {
    Log-Action "Invoking GPUpdate Failed."
    return "Failure (Starting Job)"
}