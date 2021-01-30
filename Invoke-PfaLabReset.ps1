<#	
	.NOTES
	===========================================================================
	 Created on:   	1/29/2021
	 Updated on:    1/29/2021
	 Created by:   	JD Wallace
	 Filename:     	Invoke-PfaLabReset.ps1
	===========================================================================
	.DESCRIPTION
	Nuke it!
#>
<#===========================================================================
User Configuration - Customize these variables for your environment
===========================================================================#>
$sourceArrayEndpoint = "fa-1.homelab.local"
$targetArrayEndpoint = "fa-2.homelab.local"
$arrayUsername = "pureuser"
$arrayPassword = "pureuser"
$snapshotPattern = "VEEAM-ProdSnap"
$volumePattern = "VEEAM-ProdSnap-Replica"
<#===========================================================================
End - User Configuration
===========================================================================#>

Import-Module PureStoragePowerShellSDK2

# Connect to FlashArrays with user/password
$arrayPasswordSS = ConvertTo-SecureString $arrayPassword -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPasswordSS 
$FA1 = Connect-Pfa2Array -EndPoint $sourceArrayEndpoint -Credential $arrayCredential -IgnoreCertificateError
$FA2 = Connect-Pfa2Array -EndPoint $targetArrayEndpoint -Credential $arrayCredential -IgnoreCertificateError
$LabFAs = New-Object -TypeName System.Collections.ArrayList
$LabFAs += $FA1, $FA2

ForEach($LabFA in $LabFAs) {
    #Snapshots
    $Snapshots = Get-Pfa2VolumeSnapshot -Array $LabFA | Where-Object { $_.Name -cmatch $snapshotPattern }
    ForEach($Snapshot in $Snapshots) {
        Remove-Pfa2VolumeSnapshot -Array $LabFA -IDs $Snapshot.Id
        $CLICommand = "purevol destroy --replication-snapshot " + $Snapshot.Name
        Invoke-Pfa2CLICommand -EndPoint $LabFA.ArrayName -Credential $arrayCredential -CommandText $CLICommand
    }
    ForEach($Snapshot in $Snapshots) {
        # Remove-Pfa2VolumeSnapshot -Array $LabFA -IDs $Snapshot.Id -Eradicate
        $CLICommand = "purevol eradicate --replication-snapshot " + $Snapshot.Name
        Invoke-Pfa2CLICommand -EndPoint $LabFA.ArrayName -Credential $arrayCredential -CommandText $CLICommand
    }
    
    #Volumes
    $Volumes = Get-Pfa2Volume -Array $LabFA | Where-Object { $_.Name -cmatch $volumePattern }
    ForEach($Volume in $Volumes) {
        Remove-Pfa2Connection -Array $LabFA -VolumeNames $Volume.Name -HostGroupNames "Veeam-Proxies"
        Remove-Pfa2Volume -Array $LabFA -IDs $Volume.Id
    }
    ForEach($Volume in $Volumes) {
        $CLICommand = "purevol eradicate " + $Volume.Name
        Invoke-Pfa2CLICommand -EndPoint $LabFA.ArrayName -Credential $arrayCredential -CommandText $CLICommand
    }

    # Disconnect from FlashArray
    Disconnect-Pfa2Array -Array $LABFA
}
