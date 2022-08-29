######################################################
# Baseline Compliance Universal Visibility Solution
# Author(s): Sean Huggans, Doug Flaten
######################################################
# Script Functions
#####################################
[string]$PolicyFile = "D:\Temp\BaselineTracking\baseline.config"
#[string]$PolicyFile = "$($PSScriptRoot)\baseline.config"
$LogFile = "BaselineCheck.log"
$LogDir = "$($env:SystemRoot)\Logs\Compliance"
$LogPath = "$($LogDir)\$($LogFile)"
$Global:BaseLineStatus = ""
$Global:BaseLineReportingRegKey = "HKLM:\Software\Compliance Tracking"
$Global:ConfigVersion = "0.0.0.0"

#####################################
# Script Functions
#####################################

function Log-Action ($Message, $StampDateTime, $WriteHost)
{
    ################################
    # Function Version 19.5.11.4
    # Function by Sean Huggans
    ################################
	New-Item -ItemType directory -Path $LogDir -Confirm:$false -Force | out-null
    if (($StampDateTime -eq $false) -or ($StampDateTime -eq "no")) {
        $Message | Out-File $LogPath -Append
    } else {
	    "[ $(get-date -Format 'yyyy.MM.dd HH:mm:ss') ] $($Message)" | Out-File $LogPath -Append
    }
    if ($WriteHost -eq $true) {
        Write-Host $Message
    }
}

function Record-Compliance ($Details, $Score) {
    if (!(Test-Path -Path $Global:BaseLineReportingRegKey)) {
        New-Item -Path $Global:BaseLineReportingRegKey -ItemType Directory -Force -erroraction SilentlyContinue | Out-Null
    }
    New-ItemProperty -Path $Global:BaseLineReportingRegKey -Name "BaselineStatus" -Value $Details -Force | Out-Null
    New-ItemProperty -Path $Global:BaseLineReportingRegKey -Name "BaselineScore" -Value $Score -Force | Out-Null
    New-ItemProperty -Path $Global:BaseLineReportingRegKey -Name "BaselineVersion" -Value $Global:ConfigVersion -Force | Out-Null
}

function Check-RegKeyValue ($FullPath, $CheckValue, $Comparison, $LineItem) {

    Try {
        # Separate out the Key path from the value name
        [array]$PathSplitParts = $FullPath.Split("\")
        $ValueName = $PathSplitParts[$($PathSplitParts.count - 1)]
        $KeyPath = ""
        foreach ($PathSplitPart in $($PathSplitParts[0..$($PathSplitParts.count - 2)])) {
            if ($KeyPath -ne "") {
                $KeyPath = "$($KeyPath)\$($PathSplitPart)"
            } else {
                $KeyPath = $PathSplitPart
            }
        }

        if (Test-Path -Path $KeyPath) {
            Try {
                $SetValue = $(Get-ItemPropertyValue -Path $KeyPath -Name $ValueName -ErrorAction Stop)
                # Normalize different value types for accurate comparisons
                switch -regex ($CheckValue)
                {
                   '^[0-9]*$' # Numbers Only
                   {
                        # turn into a version value for proper comaprison
                       do {
                           if ($SetValue.ToString() -notlike "*.*.*.*") {
                               $SetValue = "$($SetValue).0"
                           }
                       } until ($SetValue.ToString() -like "*.*.*.*")
                       #Log-Action -Message "Currently Set: $($SetValue.ToString())" -WriteHost $true
                       do {
                           if ($CheckValue.ToString() -notlike "*.*.*.*") {
                               $CheckValue = "$($CheckValue).0"
                           }
                       } until ($CheckValue.ToString() -like "*.*.*.*")
                       #Log-Action -Message "Checking Against: $($CheckValue.ToString())" -WriteHost $true
                   }
                   default {
                        # By Default we'll do nothing here, let the string be a normal string.
                   }
                }
            
                Switch ($Comparison.ToUpper()) {
                    "EQ" {                  
                        if ($SetValue.Trim() -eq $CheckValue.Trim()) {
                            Log-Action -Message " - - $($true) ($($SetValue) is equal to $($CheckValue))" -WriteHost $true
                            return $true
                        } else {
                            Log-Action -Message " - - $($false) ($($SetValue) is NOT equal to $($CheckValue))" -WriteHost $true
                            return $false
                        }
                    }
                    "GE" {
                        if ([version]$SetValue -ge [version]$CheckValue) {
                            Log-Action -Message " - - $($true) ($($SetValue) is greater than or equal to $($CheckValue))" -WriteHost $true
                            return $true
                        } else {
                            Log-Action -Message " - - $($false) ($($SetValue) is NOT greater than or equal to $($CheckValue))" -WriteHost $true
                            return $false
                        }
                    }
                    "LE" {
                        if ([version]$SetValue -le [version]$CheckValue) {
                            Log-Action -Message " - - $($true) ($($SetValue) is less than or equal to $($CheckValue))" -WriteHost $true
                            return $true
                        } else {
                            Log-Action -Message " - - $($false) - ($($SetValue) is NOT less than or equal to $($CheckValue))" -WriteHost $true
                            return $false
                        }
                    }
                    default {
                        Log-Action -Message " - - Error - Baseline item #$($CurrentCount): Comparison ($($Comparison.ToUpper())) is not a valid comparison type for REG items!" -WriteHost $true
                        return $false
                    }
                }
            } catch {
                Log-Action -Message " - - Error - Baseline item #$($CurrentCount): Cannot find a value named ""$($ValueName)"" at ""$KeyPath)""." -WriteHost $true
                return $false
            }
        } else {
            Log-Action -Message " - - Error - Baseline item #$($CurrentCount): Cannot find ""$($KeyPath)""." -WriteHost $true
            return $false
        }
    } catch {
        Log-Action -Message " - - Error - Baseline item #$($CurrentCount): Cannot find ""$($KeyPath)""." -WriteHost $true
        return $false
    }
}

#####################################
# Script Execution Logic
#####################################

if (Test-Path -Path $PolicyFile) {
    [array]$PolicyLines = Get-Content -Path $PolicyFile | Where-Object {(($_.Trim() -ne "") -and ($_.Trim() -notlike "#*") -and ($_.Trim() -ne " "))}
    if ($PolicyLines -gt 0) {
        $BaselineLength = $PolicyLines.Count
        Log-Action -Message "Current Baseline configuration contains $($BaselineLength) prospective lines..." -WriteHost $true
        Log-Action -Message "Evaluating items:" -WriteHost $true
        $CurrentCount = 0 # Variable for current loop iteration tracking
        foreach ($PolicyLine in $PolicyLines) {

            if (($PolicyLine.ToUpper() -like "VERSION*") -and ($PolicyLine.ToUpper() -like "*=*")) {
                $Global:ConfigVersion = $PolicyLine.Split("=")[1].Trim().Split("#").Trim()
                $BaselineLength -= 1
            } else {
                $CurrentCount += 1
                $PolicyLine = $PolicyLine.Trim()
                # Remove any trailing comments from specific lines before processing it
                if ($PolicyLine -like "*#*") {
                    $PolicyLine = $PolicyLine.Split('#')[0].Trim()
                }
                [array]$PolicyLineParts = $PolicyLine.Split(",")
                if ($PolicyLineParts.Count -ge 3) {
                    $ItemType = $PolicyLineParts[0]
                    $ItemPath = $PolicyLineParts[1]
                    $ItemComparisonType = $PolicyLineParts[2]
                    $ItemCheckValue = $PolicyLineParts[3]
                    $ItemDescription = ""
                    if ($PolicyLineParts[4]) {
                        $ItemDescription = $PolicyLineParts[4]
                    } else {
                        $ItemDescription = "No Description was given for this item."
                    }

                    # Validate data here vs. each item type's own switch - we may change this in the future but for now it seems more optimal
                    if (($ItemPath -ne "") -AND ($ItemPath -ne $null)) {
                        if (($ItemComparisonType.ToUpper() -eq "EQ") -OR ($ItemComparisonType.ToUpper()  -eq "GE") -OR ($ItemComparisonType.ToUpper()  -eq "LE")) {
                            Log-Action -Message " - Evaluating Item: $($ItemType) | $($ItemPath) | $($ItemComparisonType) | $($ItemCheckValue) | $($ItemDescription)" -WriteHost $true #TODO: Remove this
                            switch ($ItemType) {
                                "REG" {
                                    if ($(Check-RegKeyValue -FullPath $ItemPath -CheckValue $ItemCheckValue -Comparison $ItemComparisonType -LineItem $CurrentCount) -eq $true) {
                                        $Global:BaseLineStatus = "$($BaselineStatus)1"
                                    } else {
                                        $Global:BaseLineStatus = "$($BaselineStatus)0"
                                    }
                                }
                                "File" {
                                    Log-Action -Message " - Warning - Baseline item #$($CurrentCount): File Item Type handler not yet implemented." -WriteHost $true
                                    $Global:BaseLineStatus = "$($BaselineStatus)?"
                                }
                                default {
                                    Log-Action -Message " - Error - Baseline item #$($CurrentCount): $($ItemType) is not a valid item type." -WriteHost $true
                                    $Global:BaseLineStatus = "$($BaselineStatus)0"
                                }
                            }
                        } else {
                            Log-Action -Message " - Error - Baseline item #$($CurrentCount): $($ItemComparisonType) is not a valid comparison type." -WriteHost $true
                            $Global:BaseLineStatus = "$($BaselineStatus)0"
                        }
                    } else {
                        Log-Action -Message " - Error - Baseline item #$($CurrentCount): Item Path is not properly defined." -WriteHost $true
                        $Global:BaseLineStatus = "$($BaselineStatus)0"
                    }
                } else {
                    Log-Action -Message " - Error - Baseline item #$($CurrentCount) has too few pieces provided to check." -WriteHost $true
                    $Global:BaseLineStatus = "$($BaselineStatus)0"
                }
                #Write-Host "---"
            }
        }
        # Create an overall baseline score measure
        $BaselineScoreValue = 0
        foreach ($GoodItem in $($Global:BaseLineStatus.ToCharArray() | Where-Object {$_ -eq "1"})) {
            $BaselineScoreValue += 1
        }

        Log-Action -Message "Overall Baseline Score: $([math]::Round($($BaselineScoreValue / $BaselineLength * 100), 2))% | Baseline Version: $($Global:ConfigVersion) | Breakdown: $($BaselineScoreValue)/$($BaselineLength) items are in compliance with the provided Baseline configuration | Details: $($BaselineStatus)" -WriteHost $true
        Record-Compliance -Details $BaselineStatus -Score $([math]::Round($($($BaselineScoreValue) / $($BaselineLength) * 100),2))
    } else {
        Log-Action -Message "Warning - There are currently no useable items present in the baseline configuration!" -WriteHost $true
        Record-Compliance -Details 000000000 -Score 0
    }
    #$PolicyFile = Get-Content -Path 
} else {
    Log-Action -Message "Error - No baseline configuration file is present!" -WriteHost $true
    Record-Compliance -Details 000000000 -Score 0
}


