#########################################################################################################
# Build-PrintGPOsFromPrintServer.ps1
$ScriptVersion = "19.7.27.3"
# Script Author: Sean Huggans
##########################################################################################################
# Script Variables
#####################################################
# Edit the below to pertain to your environment
[string[]]$PrintServers = "PrintServer01","PrintServer02","PrintServer03"  #Set list of print servers
[string[]]$ExcludedPrinterNames = "Microsoft XPS Document Writer","KX DRIVER for Universal Printing","TIFF Printer" # Exclude any printer names you want to here
[string]$PrinterGroupsOU = "OU=Printer,OU=Groups,DC=Some,DC=Domain,DC=com" # Provide the Distinguished Name of the OU you want your printer groups created in (Must Exist)
 
 
# Do not touch variables below this line
#######################################################
[string]$LogonDomain = $(Get-ADDomain).NetBIOSName
[string]$PrinterHeaderXML = "<?xml version=""1.0"" encoding=""utf-8""?>
<Printers clsid=""{1F577D12-3D1B-471e-A1B7-060317597B9C}"">"
[string]$PortPrinterTemplateXML = "<PortPrinter clsid=""{C3A739D2-4A44-401e-9F9D-88E5E77DFB3E}"" name=""!PrinterName!"" status=""!PrinterName!"" image=""0"" bypassErrors=""1"" changed=""2019-07-26 04:05:56"" uid=""{!PrinterUID!}"">
		<Properties ipAddress=""!PrinterName!"" action=""C"" location="""" localName=""!PrinterName!"" comment=""!PrinterDescription!"" default=""0"" skipLocal=""0"" useDNS=""1"" useIPv6=""0"" path=""\\!PrintServerName!\!PrinterName!"" deleteAll=""0""/>
		<Filters>
			<FilterGroup bool=""AND"" not=""0"" name=""$($LogonDomain)\PRINTER-!PrinterName!"" sid=""!PrinterGroupSID!"" userContext=""0"" primaryGroup=""0"" localGroup=""0""/>
		</Filters>
	</PortPrinter>"
[string]$PrinterFooterXML = "</Printers>"
 
# Replacement Patterns
[string]$ReplacePattern_PrinterName = "!PrinterName!"
[string]$ReplacePattern_PrinterServerName = "!PrintServerName!"
[string]$ReplacePattern_PrinterUID = "!PrinterUID!"
[string]$ReplacePattern_PrinterGroupSID = "!PrinterGroupSID!"
[string]$ReplacePattern_PrinterDescription = "!PrinterDescription!"
 
# Logging Variables
[string]$LogFile = "Build-PrintGPOsFromPrintServer.log"
[string]$LogDir = "C:\Temp"
[string]$LogPath = "$($LogDir)\$($LogFile)"
 
#####################################################
# Script Functions
#####################################################
 
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
 
 
#####################################################
# Script Exectution Logic
#####################################################
 
# Import Active Directory PoSH Module
Import-Module ActiveDirectory
 
# Loop through each print server in the provided PrintServer list
foreach ($PrintServer in $PrintServers) {
    Log-Action -Message "=========================================================" -WriteHost $true
    Log-Action -Message $PrintServer -WriteHost $true
    Log-Action -Message "=========================================================" -WriteHost $true
 
    # Get GPO Object for printers shared on this serveror create it if it doesn't already exist
    Try {
        $GPOObject = Get-GPO -Name "Printers - $($PrintServer)" -ErrorAction Stop
        Log-Action -Message "Create Group Policy Object: Skipped, GPO exists" -WriteHost $true
    } catch {
        #$GPOObject = New-GPO -Name "Printers - $($PrintServer)"
        Copy-GPO -SourceName "Printers - Template" -TargetName "Printers - $($PrintServer)" | Out-Null
        $GPOObject = Get-GPO -Name "Printers - $($PrintServer)" -ErrorAction Stop
        Log-Action -Message "Create Group Policy Object: SUCCESS" -WriteHost $true
    }
 
        $XMLPATH = "c:\Windows\SYSVOL\domain\Policies\{$($GPOObject.ID)}\Machine\Preferences\Printers\Printers.xml"
        if (!(test-path -Path "c:\Windows\SYSVOL\domain\Policies\{$($GPOObject.ID)}\Machine\Preferences\Printers" -PathType Container)) {
            New-Item -ItemType Directory "c:\Windows\SYSVOL\domain\Policies\{$($GPOObject.ID)}\Machine\Preferences\Printers" | Out-Null
        }
 
        # Get an array object of all printers on the print server
    [array]$Printers = Get-Printer -ComputerName $PrintServer
 
    #Start building XML to output
    [string]$OutPutXML = $PrinterHeaderXML
 
    Write-Host $PrinterObjectLine
    # Loop through each printer in the returned array object
    Foreach ($Printer in $($Printers | where-object {(($ExcludedPrinterNames -notcontains $_.Name) -and ($_.Shared -eq $true))})) {
        Log-Action -Message "------------------" -WriteHost $true
        Log-Action -Message $Printer.Name -WriteHost $true
        Log-Action -Message "------------------" -WriteHost $true
 
        # Create AD Printer Group if it does not already exist
        [boolean]$GroupSuccess = $true
        Try {
            $PrinterGroup = Get-ADGroup -Identity "PRINTER-$($Printer.Name)" -ErrorAction Stop
            Set-ADGroup -Identity "PRINTER-$($Printer.Name)" -Description "Installs $($Printer.Location) printer ($($Printer.Name))"
            Log-Action -Message "Create Printer Group: Skipped, Group exists" -WriteHost $true
        } catch {
            Try {
                New-ADGroup -Name "PRINTER-$($Printer.Name)" -Path $PrinterGroupsOU -GroupScope Global -GroupCategory Security -Description "Installs $($Printer.Location) printer ($($Printer.Name))" -ErrorAction Stop | Out-Null
                $PrinterGroup = Get-ADGroup -Identity "PRINTER-$($Printer.Name)" -ErrorAction Stop
                Log-Action -Message "Create Printer Group: Success" -WriteHost $true
            } catch {
                Log-Action -Message "Create Printer Group: FAILED" -WriteHost $true
                [boolean]$GroupSuccess = $false
            }
        }
        # IF group creation was not set to false, continue
        if ($GroupSuccess -eq $true) {
            Try {
                $OutputXML += $PortPrinterTemplateXML.Replace($ReplacePattern_PrinterName, $Printer.Name).Replace($ReplacePattern_PrinterServerName, $PrintServer).Replace($ReplacePattern_PrinterUID, $([System.Guid]::NewGuid().toString())).Replace($ReplacePattern_PrinterGroupSID, $PrinterGroup.SID.ToString()).Replace($ReplacePattern_PrinterDescription, $Printer.Location)
                Log-Action -Message "Add Printer To GPO: Success" -WriteHost $true
            } catch {
                Log-Action -Message "Add Printer To GPO: FAILED" -WriteHost $true
            }
        }
    }
    $OutPutXML += $PrinterFooterXML
    [xml]$NewXMLFile = $OutPutXML
    $NewXMLFile.Save($XMLPATH)
}