#######################################################################################
# Get-BitlockerKeyforWorkstation.ps1
$Script:Version = "23.5.3.5"
# Author(s): Sean Huggans
# Based on work by Niall C. Brady 
# @ https://www.niallbrady.com/2019/05/26/how-can-i-get-recovery-keys-from-the-configmgr-database-in-sccm/
#######################################################################################

$CompName = ""
$RecoveryKeyID = ""
$global:SiteServer = "ConfigMgrSMSProvider"
$global:SiteCode = "FOO"

function Invoke-SQL
{
	param (
		[string]$dataSource = "$global:SiteServer",
		[string]$database = "CM_$global:SiteCode",
		[string]$sqlCommand = $(throw "Please specify a query.")
	)
			
	$connectionString = "Data Source=$dataSource; " +
	"Integrated Security=SSPI; " +
	"Initial Catalog=$database"
			
	$connection = new-object system.data.SqlClient.SQLConnection($connectionString)
	$command = new-object system.data.sqlclient.sqlcommand($sqlCommand, $connection)
	$connection.Open()
			
	$adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
	$dataset = New-Object System.Data.DataSet
	$adapter.Fill($dataSet) | Out-Null
			
	$connection.Close()
	$dataSet.Tables	
}

if (($CompName -ne "") -and ($CompName -ne $null)) {
    $BilockerKeys = Invoke-SQL -sqlCommand "
    select Machines.Id, Machines.Name, Volumes.VolumeId, Keys.RecoveryKeyId, Keys.LastUpdateTime, RecoveryAndHardwareCore.DecryptString(Keys.RecoveryKey, DEFAULT) AS RecoveryKey
    from dbo.RecoveryAndHardwareCore_Machines Machines
    inner join dbo.RecoveryAndHardwareCore_Machines_Volumes Volumes ON Machines.Id = Volumes.MachineId
    inner join dbo.RecoveryAndHardwareCore_Keys Keys ON Volumes.VolumeId = Keys.VolumeId
    where Machines.name = '$($CompName)'"
    return $BilockerKeys
} elseif (($RecoveryKeyID -ne "") -and ($RecoveryKeyID -ne $null)) {
    if ($RecoveryKeyID.Length -ge 8) {
        $RecoveryKey = Invoke-SQL -sqlCommand "
        select Machines.Id, Machines.Name, Volumes.VolumeId, Keys.RecoveryKeyId, Keys.LastUpdateTime, RecoveryAndHardwareCore.DecryptString(Keys.RecoveryKey, DEFAULT) AS RecoveryKey
        from dbo.RecoveryAndHardwareCore_Machines Machines
        inner join dbo.RecoveryAndHardwareCore_Machines_Volumes Volumes ON Machines.Id = Volumes.MachineId
        inner join dbo.RecoveryAndHardwareCore_Keys Keys ON Volumes.VolumeId = Keys.VolumeId
        where Keys.RecoveryKeyId LIKE '$($RecoveryKeyID)%'"
        return $RecoveryKey
    } else {
            return "You must supply at least the first 8 characters of the Recovery Key ID!"
    }
} else {
    return "You must supply either a computer name or recovery Key ID (at least the first 8 characters)!"
}

