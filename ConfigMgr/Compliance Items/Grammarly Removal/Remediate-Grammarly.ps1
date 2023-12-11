######################
# Remediate-Grammarly.ps1
# Author(s): Sean Huggans
$ScriptVersion = "23.12.1.1"
######################

######################
# Method Detections
######################

Function Test-Grammarly1 {
    if (Test-Path -Path "$($env:USERPROFILE)\AppData\Local\Grammarly\DesktopIntegrations\Uninstall.exe") {
       # Write-Host "Grammarly detected (Method 1)"
        return $true
    } else {
        return $false
    }
}

Function Test-Grammarly2 {
    if (Test-Path -Path "$($env:USERPROFILE)\AppData\Local") {
        return $false
    } else {
        return $true
    }
}

######################
# Method Uninstalls
######################
function Uninstall-GrammarlyGeneric {
    New-Item -Path "C:\Program Files\visuaFUSION\Compliance\Banned Software Removals\Resources" | Out-Null
    Copy-Item -Path "\\SERVER\PUBLICSHARE\_Banned Software Removal Packages\Grammarly\Resources\GrammarlyInstaller.exe" -Destination "C:\Program Files\visuaFUSION\Compliance\Banned Software Removals\Resources\GrammarlyInstaller.exe" -Force -erroraction SilentlyContinue
    $G2Proc = Start-Process -FilePath "C:\Program Files\visuaFUSION\Compliance\Banned Software Removals\Resources\GrammarlyInstaller.exe" -ArgumentList "/S /uninstall" -WindowStyle Hidden -PassThru -Wait
    switch ($G2Proc.ExitCode) {
        0 {
            #return "Uninstalled Successfully"
        } 
        Default {
            #return "Unknown Exit Code ($($G2Proc.ExitCode))"
        }
    }
}

function Uninstall-Grammarly1 {
    $G1Proc = Start-Process -FilePath "$($env:USERPROFILE)\AppData\Local\Grammarly\DesktopIntegrations\Uninstall.exe" -ArgumentList "/S" -WindowStyle Hidden -PassThru -Wait
    switch ($G1Proc.ExitCode) {
        0 {
            #return "Uninstalled Successfully"
        } 
        Default {
            #return "Unknown Exit Code ($($G1Proc.ExitCode))"
        }
    }
    Uninstall-GrammarlyGeneric
}

######################
# Execution Logic
######################

if ((Test-Grammarly1 -ne $false) -and (Test-Grammarly2 -ne $false)) {
    Uninstall-Grammarly1
}

