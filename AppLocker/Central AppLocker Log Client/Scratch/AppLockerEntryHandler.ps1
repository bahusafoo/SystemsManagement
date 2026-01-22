
[array]$AppLockerEntries = Get-AppLockerFileInformation -EventType Audited -EventLog -Statistics
if ($AppLockerEntries.Count -gt 0) {
    foreach ($AppLockerEntry in $AppLockerEntries) {
        foreach ($Member in $($AppLockerEntry | Get-Member)) {
            Write-Host $Member
        }
    }
} else {
    Write-Host "There were not AppLocker Entries found."
}