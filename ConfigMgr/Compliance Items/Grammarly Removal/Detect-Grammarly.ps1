######################
# Detect-Grammarly.ps1
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
# Execution Logic
######################

if ((Test-Grammarly1 -ne $false) -and (Test-Grammarly2 -ne $false)) {
    # System is clean, return false
    return $false
} else {
    # System has grammarly, return true
    return $true
}

