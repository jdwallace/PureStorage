<#	
	.NOTES
	===========================================================================
	 Created on:   	1/29/2021
	 Updated on:    1/31/2021
	 Created by:   	JD Wallace
	 Filename:     	Invoke-PfaLabReset.ps1
	===========================================================================
	.DESCRIPTION
    Nuke it!
    Deletes and Eradicates volumes and snapshots matching the supplied patern.
    Used for resetting test lab while developing new automaiton.
#>
<#===========================================================================
User Configuration - Customize these variables for your environment
===========================================================================#>
$FA1ArrayEndpoint = "fa-1.homelab.local"
$FA2ArrayEndpoint = "fa-2.homelab.local"
$snapshotPattern = "VEEAM-ProdSnap"
$volumePattern = "VEEAM-ProdSnap-Replica"
# $volumePattern = "VEEAM-ExportLUNSnap-"

# FlashArray OAuth2 Connection Variables
$arrayUsername = "vbr-server"
$clientName = "VeeamPowerShell"
$arrayIssuer = $Clientname
$FA1ArrayClientId = "f645d17f-cad0-415a-9d40-d58b7b00fec7"
$FA1ArrayKeyId = "be6e66c0-4deb-46be-9e9b-80f67642a8e5"
$FA2ArrayClientId = "d631a668-7e35-45f3-b77d-2fb05c5fc458"
$FA2ArrayKeyId = "b6ebc1cb-3115-4d43-96d9-d916d5ff02b1"
$privateKeyFile = "/Users/jwallace/.ssh/Pure¦fa-1.homelab.local¦vbr-server¦VeeamPowerShell¦5772f75a-df1c-4aca-843a-304abf875741¦ed6d4780-61d9-4c5e-8ac0-39c48c9c85d9¦private.pem"
<#===========================================================================
End - User Configuration
===========================================================================#>

Import-Module PureStoragePowerShellSDK2

#Still need user/password for Invoke-Pfa2CLICommand.
$arrayCredential = (Get-Credential)

# Connect to FlashArrays with OAuth2
$FA1 = Connect-Pfa2Array -Endpoint $FA1ArrayEndpoint -Username $arrayUsername -Issuer $arrayIssuer -ApiClientName $clientName -ClientId $FA1ArrayClientId -KeyId $FA1ArrayKeyId -PrivateKeyFile $privateKeyFile -IgnoreCertificateError
$FA2 = Connect-Pfa2Array -Endpoint $FA2ArrayEndpoint -Username $arrayUsername -Issuer $arrayIssuer -ApiClientName $clientName -ClientId $FA2ArrayClientId -KeyId $FA2ArrayKeyId -PrivateKeyFile $privateKeyFile -IgnoreCertificateError

$LabFAs = New-Object -TypeName System.Collections.ArrayList
$LabFAs += $FA1, $FA2

ForEach($LabFA in $LabFAs) {
    #Snapshots
    $Snapshots = Get-Pfa2VolumeSnapshot -Array $LabFA | Where-Object { $_.Name -cmatch $snapshotPattern }
    #Destroy
    ForEach($Snapshot in $Snapshots) {
        Remove-Pfa2VolumeSnapshot -Array $LabFA -IDs $Snapshot.Id
        # There is no apparent way to delete a baseline snapshot via SDK2. Fall back to CLI.
        $CLICommand = "purevol destroy --replication-snapshot " + $Snapshot.Name
        Invoke-Pfa2CLICommand -EndPoint $LabFA.ArrayName -Credential $arrayCredential -CommandText $CLICommand
    }
    #Eradicate
    ForEach($Snapshot in $Snapshots) {
        Remove-Pfa2VolumeSnapshot -Array $LabFA -Eradicate -Confirm:$false -IDs $Snapshot.Id
        # There is no apparent way to delete a baseline snapshot via SDK2. Fall back to CLI.
        $CLICommand = "purevol eradicate --replication-snapshot " + $Snapshot.Name
        Invoke-Pfa2CLICommand -EndPoint $LabFA.ArrayName -Credential $arrayCredential -CommandText $CLICommand
    }
    #Volumes
    $Volumes = Get-Pfa2Volume -Array $LabFA | Where-Object { $_.Name -cmatch $volumePattern }
    #Destroy
    ForEach($Volume in $Volumes) {
        Remove-Pfa2Connection -Array $LabFA -VolumeNames $Volume.Name -HostGroupNames "Veeam-Proxies"
        Remove-Pfa2Volume -Array $LabFA -IDs $Volume.Id
    }
    #Eradicate
    ForEach($Volume in $Volumes) {
        Remove-Pfa2Volume -Array $LabFA -Eradicate -Confirm:$false -IDs $Volume.Id
    }
    # Disconnect from FlashArray
    Disconnect-Pfa2Array -Array $LABFA
}
