################################
# RSAT Detection Script
$ScriptVersion = "24.6.22.4"
# Author(s): Sean Huggans
################################

# Get OS Name
$OS = $(Get-WmiObject Win32_OperatingSystem).Caption

$AllPresent = $True
if ($OS -notlike "*Windows Server*") {
    # Handle Windows Client OS
    Foreach ($RSATPackage in [array]$(Get-WindowsCapability -Name "RSAT*" -Online)) {
        if ($RSATPackage.State -eq "NotPresent") {
            $AllPresent = $false
        }
    }
} else {
    Foreach ($RSATPackage in [array]$(Get-WindowsFeature -Name "RSAT*")) {
        if ($RSATPackage.InstallState -eq "Available") {
            $AllPresent = $false
        }
    }
}

if ($AllPresent -eq $True) {
    Return $True
} else {
    # Return Nothing so Detection Fails   
}