<#	
	.NOTES
	===========================================================================
	 Created on:   	1/26/2021
	 Updated on:    1/29/2021
	 Created by:   	JD Wallace
	 Filename:     	Invoke-PfaSendSnapAfterVBRJob.ps1
	 Acknowledgements: 
	 Get Veeam Job Name From Process ID - https://blog.mwpreston.net/2016/11/17/setting-yourself-up-for-success-with-veeam-pre-job-scripts/
	===========================================================================
	.DESCRIPTION
	A Veeam VBR post-job script to be used with Pure FlashArray snapshot only job. Will replicate the new snapshot to a secondary FlashArray.
	After replicating, the replica will be cloned to a new volume and then snapped in order to be scannable by the Pure plug-in for Veeam.
	Cleanup of unused snapshots on both source and target FlashArray not yet implemented.
	Requires Purity//FA 6.1.0 or later.
#>
<#===========================================================================
User Configuration - Customize these variables for your environment
===========================================================================#>
# Source FlashArray - Hosting VMFS Datastores being protected - Currently only 1 source FA supported per job
$sourceArrayEndpoint = "fa-1.homelab.local"
# Target FlashArray - Where will the Snapshots be replicated to?
$targetArrayEndpoint = "fa-2.homelab.local"
# User/Pass for FlashArray - Must exist on both FlashArrays. Must be storage-admin or higher
# Required since we're using Invoke-Pfa2CLICommand, will be replaced by OAuth2 in the future
$arrayUsername = "pureuser"
$arrayPassword = "pureuser"
# Name of Target FlashArray Host Group for Veeam Proxies
# Must be pre-created and populated with Veeam Proxy servers in order for Veeam to scan replicas on target FlashArray and inventory VMs
$PfaVeeamHostGroup = "Veeam-Proxies"
# If DisableSourceRetention is TRUE, Snapshots will be removed from Source FlashArray after replication
$DisableSourceRetention = $false
# TestMode will use a specific Veeam Job Name, otherwise figure out Job Name based on which one launched the script
$TestMode = $false
$TestModeJobName = "FA Snapshot Job"
<#===========================================================================
End - User Configuration
===========================================================================#>

Add-PSSnapin VeeamPSSnapIn
Import-Module PureStoragePowerShellSDK2

# Primary FlashArray Credential for user/password authentication
$arrayPasswordSS = ConvertTo-SecureString $arrayPassword -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPasswordSS 

# Connect to FlashArrays with user/password
$sourceFlashArray = Connect-Pfa2Array -EndPoint $sourceArrayEndpoint -Credential $arrayCredential -IgnoreCertificateError
$targetFlashArray = Connect-Pfa2Array -EndPoint $targetArrayEndpoint -Credential $arrayCredential -IgnoreCertificateError

if ($TestMode) {
	# Get specific job
	$VbrJob = Get-VBRJob | Where-Object { $_.Name -eq $TestModeJobName }
}else {
	# Get Veeam job name from parent process id
	$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
	$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
	$jobid = $parentcmd.split('" "')[16]
	$VbrJob = get-vbrjob | where-object { $_.Id -eq "$jobid" }
}

# Get latest job Session (should be the session that called this script)
$VbrSession = Get-VBRBackupSession | Where-Object {$_.jobId -eq $VbrJob.Id.Guid} | Sort-Object EndTimeUTC -Descending | Select-Object -First 1

# Get all FlashArray snapshots created from this Job
$jobNameInSnap = ".VEEAM-ProdSnap-" + $VbrJob.Name -replace ' ','-'
$PfaSnapshots = Get-StoragePluginSnapshot | Where-Object { $_.Name -cmatch $jobNameInSnap }
$PfaConfirmedSnapshots = New-Object -TypeName System.Collections.ArrayList

#For each FlashArray snapshot, check that it's from the latest session and replicate if so
ForEach ($PfaSnapshot in $PfaSnapshots) {
	# If Snapshot was created after latest session start time, it must have been created during this session
	If ($PfaSnapshot.CreationTimeSrv -gt $VbrSession.Info.CreationTime) {
		# Construct 'purevol send' command
		$snapSendCLI = "purevol send --to " + $targetFlashArray.ArrayName.Split('.')[0] + " " + $PfaSnapshot.Name
		# Invoke-Pfa2CLICommand to call 'purevol send' to replicate the snapshot
		Invoke-Pfa2CLICommand -EndPoint $sourceArrayEndpoint -Credential $arrayCredential -CommandText $snapSendCLI

		$PfaConfirmedSnapshots += $PfaSnapshot
	}
}
# For each FlashArray snapshot which was replicated, clone, snap, then clean up
ForEach ($PfaConfirmedSnapshot in $PfaConfirmedSnapshots) {
	# Wait for replication to complete
	do {
		Start-Sleep -s 5
		$replicationStatus = Get-Pfa2VolumeSnapshotTransfer -Array $sourceFlashArray -Name $PfaConfirmedSnapshot.Name
	} while ($null -eq $replicationStatus.Completed)

	# Get Replicated Snapshot
	$PfaSnapshotReplica = Get-Pfa2VolumeSnapshot -Array $targetFlashArray -Name ($sourceFlashArray.ArrayName.Split('.')[0] + ":" + $PfaConfirmedSnapshot.Name)

	# Clone Replicated Snapshot, Overwriting existing
	$src = New-Pfa2ReferenceObject -Id $PfaSnapshotReplica.id -Name $PfaSnapshotReplica.Name
	$PfaSnapshotClone = New-Pfa2Volume -Array $targetFlashArray -Overwrite $true -Source $src -Name ($PfaSnapshotReplica.Source.Name.Split(':')[1] + "-VEEAM-ProdSnap-Replica")
	# Connect clone to Veeam Proxy Host Group
	if ($null -eq (Get-Pfa2Connection -Array $targetFlashArray -HostGroupNames $PfaVeeamHostGroup -VolumeNames $PfaSnapshotClone.Name)) {
		New-Pfa2Connection -Array $targetFlashArray -HostGroupNames $PfaVeeamHostGroup -VolumeNames $PfaSnapshotClone.Name
	}
	# Create Snapshot of Clone
	New-Pfa2VolumeSnapshot -Array $targetFlashArray -SourceNames $PfaSnapshotClone.Name
	
	#Get all cloned snapshots 
	$PfaReplicaCloneSnaps = Get-Pfa2VolumeSnapshot -Array $targetFlashArray -Destroyed $false -SourceNames $PfaSnapshotClone.Name | Sort-Object Created -Descending 

	# See if number of snaps exceeds Job retention policy
	if ($PfaReplicaCloneSnaps.Length -gt $VbrJob.Options.BackupStorageOptions.RetainCycles) {
		#Delete the excess snapshots
		For ($i = $VbrJob.Options.BackupStorageOptions.RetainCycles; $i -lt $PfaReplicaCloneSnaps.Length; $i++ ) {
			Remove-Pfa2VolumeSnapshot -Array $targetFlashArray -Name $PfaReplicaCloneSnaps[$i].Name
		}
	}
	# Delete original Snapshot Replica
	#TODO, Handle Baseline case
	# Remove-Pfa2VolumeSnapshot -Array $targetFlashArray -Name $PfaSnapshotReplica.Name
	
	# Delete snapshot from Source FlashArray
	if ($DisableSourceRetention) {
		#TODO, Handle Baseline case
		# Remove-Pfa2VolumeSnapshot -Array $sourceFlashArray -Name $PfaConfirmedSnapshot.Name
	}
}
# Disconnect from FlashArray
Disconnect-Pfa2Array -Array $sourceFlashArray
Disconnect-Pfa2Array -Array $targetFlashArray