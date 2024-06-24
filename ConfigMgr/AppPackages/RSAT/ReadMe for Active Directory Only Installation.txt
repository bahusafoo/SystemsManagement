Note: If you ONLY need to install the active directory piece of this, you can change the following in BOTH the detection AND installation scripts (don't forget the detection script!:

FROM:    Foreach ($RSATPackage in [array]$(Get-WindowsCapability -Name "RSAT*" -Online)) {
TO:    Foreach ($RSATPackage in [array]$(Get-WindowsCapability -Name "RSAT.ActiveDirectory*" -Online)) {
