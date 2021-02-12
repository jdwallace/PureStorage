<#	
	.SYNOPSIS
	A Veeam VBR post-job script to replicate Pure FlashArray snapshots to a secondary FlashArray.
	.DESCRIPTION
	A Veeam VBR post-job script to be used with Pure FlashArray snapshot only job. Will replicate the new snapshot to a secondary FlashArray.
	After replicating, the replica will be cloned to a new volume and then snapped in order to be scannable by the Pure plug-in for Veeam.
	Requires Purity//FA 6.1.0 or later.
	.NOTES
	Acknowledgements: 
	Get Veeam Job Name From Process ID - https://blog.mwpreston.net/2016/11/17/setting-yourself-up-for-success-with-veeam-pre-job-scripts/ 
	.LINK
	https://jdwallace.com
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
$DisableSourceRetention = $true
# If RescanAfterJob is TRUE, VBR will rescan Pure Storage via USAPI Plug-in to immediately detect new remote snapshots
$RescanAfterJob = $true
# TestMode will use a specific Veeam Job Name, otherwise figure out Job Name based on which one launched the script
$TestMode = $false
$TestModeJobName = "FA Snapshot Job"
# Path to VBR Installation.
$PathToVBRInstall = "C:\Program Files\Veeam\Backup and Replication\Backup"
<#===========================================================================
End - User Configuration
===========================================================================#>

Import-Module PureStoragePowerShellSDK2

# Get VBR Version
$PathToVBRDLL = $PathToVBRInstall + "\Veeam.Backup.Core.dll"
$VBRServer = Get-Item -Path $PathToVBRDLL
$VBRVersion = $VBRServer.VersionInfo.ProductMajorPart

# If running versions prior to v11, add SnapIn
switch ( $VBRVersion ) {
	{$_ -ge 11} {
		Write-Host "Detected VBR v$VBRVersion"
	}
	{$_ -le 10} {
		Write-Host "Detected VBR v$VBRVersion"
		Add-PSSnapin VeeamPSSnapIn
	}
	default {
		Write-Host "No VBR Installation detected at $PathToVBRInstall"
		Exit(0)
	}
}

# Primary FlashArray Credential for user/password authentication
$arrayPasswordSS = ConvertTo-SecureString $arrayPassword -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPasswordSS 

# Connect to FlashArrays with user/password
$sourceFAConnection = Connect-Pfa2Array -EndPoint $sourceArrayEndpoint -Credential $arrayCredential -IgnoreCertificateError
$targetFAConnection = Connect-Pfa2Array -EndPoint $targetArrayEndpoint -Credential $arrayCredential -IgnoreCertificateError
$sourceFA = Get-Pfa2Array -Array $sourceFAConnection
$targetFA = Get-Pfa2Array -Array $targetFAConnection
switch ( $sourceFA.Version) {
	{$_ -ge 6.1} {
		Write-Host "Source Purity//FA Version: $($sourceFA.Version)"
	}
	default {
		Write-Host "Unsupported Purity//FA Version. Minimum version: 6.1 "
		Write-Host "Target Purity//FA Detected Version: $($sourceFA.Version)"
		Exit(0)
	}
}
switch ( $targetFA.Version) {
	{$_ -ge 6.1} {
		Write-Host "Target Purity//FA Version: $($targetFA.Version)"
	}
	default {
		Write-Host "Unsupported Purity//FA Version. Minimum version: 6.1 "
		Write-Host "Target Purity//FA Detected Version: $($targetFA.Version)"
		Exit(0)
	}
}

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
switch ( $VBRVersion ) {
	{$_ -ge 11} {
		$VbrSession = Get-VBRBackupSession | Where-Object {$_.jobId -eq $VbrJob.Id} | Sort-Object EndTimeUTC -Descending | Select-Object -First 1
	}
	{$_ -le 10} {
		$VbrSession = Get-VBRBackupSession | Where-Object {$_.jobId -eq $VbrJob.Id.Guid} | Sort-Object EndTimeUTC -Descending | Select-Object -First 1
	}
}

# Get all FlashArray snapshots created from this Job
$jobNameInSnap = ".VEEAM-ProdSnap-" + $VbrJob.Name -replace ' ','-'
$PfaSnapshots = Get-StoragePluginSnapshot | Where-Object { $_.Name -cmatch $jobNameInSnap }
$PfaConfirmedSnapshots = New-Object -TypeName System.Collections.ArrayList

#For each FlashArray snapshot, check that it's from the latest session and replicate if so
#Do all of these first so replications can happen in parallel
ForEach ($PfaSnapshot in $PfaSnapshots) {
	# If Snapshot was created after latest session start time, it must have been created during this session
	If ($PfaSnapshot.CreationTimeSrv -gt $VbrSession.Info.CreationTime) {
		# Construct 'purevol send' command
		$snapSendCLI = "purevol send --to " + $targetFAConnection.ArrayName.Split('.')[0] + " " + $PfaSnapshot.Name
		# Invoke-Pfa2CLICommand to call 'purevol send' to replicate the snapshot
		Invoke-Pfa2CLICommand -EndPoint $sourceArrayEndpoint -Credential $arrayCredential -CommandText $snapSendCLI
		$PfaConfirmedSnapshots += $PfaSnapshot
	}
}
# For each FlashArray snapshot which was replicated, clone, snap, then clean up
ForEach ($PfaConfirmedSnapshot in $PfaConfirmedSnapshots) {
	# Wait for replication to complete
	do {
		Start-Sleep -Seconds 5
		$replicationStatus = Get-Pfa2VolumeSnapshotTransfer -Array $sourceFAConnection -Name $PfaConfirmedSnapshot.Name
	} while ($null -eq $replicationStatus.Completed)

	# Get Source and Replica Snapshots
	$PfaSnapshotSource = Get-Pfa2VolumeSnapshot -Array $sourceFAConnection -Name $PfaConfirmedSnapshot.Name
	$PfaSnapshotReplica = Get-Pfa2VolumeSnapshot -Array $targetFAConnection -Name ($sourceFAConnection.ArrayName.Split('.')[0] + ":" + $PfaConfirmedSnapshot.Name)

	# Clone Replicated Snapshot, Overwriting existing
	$src = New-Pfa2ReferenceObject -Id $PfaSnapshotReplica.id -Name $PfaSnapshotReplica.Name
	$PfaSnapshotClone = New-Pfa2Volume -Array $targetFAConnection -Overwrite $true -Source $src -Name ($PfaSnapshotReplica.Source.Name.Split(':')[1] + "-VEEAM-ProdSnap-Replica")
	# Connect clone to Veeam Proxy Host Group if it isn't connected
	if ($null -eq (Get-Pfa2Connection -Array $targetFAConnection -HostGroupNames $PfaVeeamHostGroup -VolumeNames $PfaSnapshotClone.Name)) {
		New-Pfa2Connection -Array $targetFAConnection -HostGroupNames $PfaVeeamHostGroup -VolumeNames $PfaSnapshotClone.Name
	}
	# Create Snapshot of Clone
	$PfaReplicaClone = New-Pfa2VolumeSnapshot -Array $targetFAConnection -SourceNames $PfaSnapshotClone.Name
	# Wait until Snapshot is created
	while ($null -eq $PfaReplicaClone.Created) {
		Start-Sleep -Seconds 1
	}
	
	#Get all of clone's snapshots 
	$PfaReplicaCloneSnaps = Get-Pfa2VolumeSnapshot -Array $targetFAConnection -Destroyed $false -SourceNames $PfaSnapshotClone.Name | Sort-Object Created -Descending 

	# See if number of snaps exceeds Job retention policy
	if ($PfaReplicaCloneSnaps.Length -gt $VbrJob.Options.BackupStorageOptions.RetainCycles) {
		#Delete the excess snapshots
		For ($i = $VbrJob.Options.BackupStorageOptions.RetainCycles; $i -lt $PfaReplicaCloneSnaps.Length; $i++ ) {
			Remove-Pfa2VolumeSnapshot -Array $targetFAConnection -Name $PfaReplicaCloneSnaps[$i].Name
		}
	}
	# Delete old Snapshot Replicas from Target FlashArray but keep latest as baseline
	$PfaTempSnapshots = Get-Pfa2VolumeSnapshot -Array $targetFAConnection -Destroyed $false | Where-Object { $_.Name -cmatch ($PfaSnapshotReplica.Name.Split('.')[0] + ".VEEAM-ProdSnap-FA-Snapshot-Job") }
	ForEach ($PfaTempSnapshot in $PfaTempSnapshots) {
		If ($PfaTempSnapshot.Id -ne $PfaSnapshotReplica.Id) { 
			Remove-Pfa2VolumeSnapshot -Array $targetFAConnection -Ids $PfaTempSnapshot.Id
		}
	}
	# Delete old Snapshots from Source FlashArray but keep latest as baseline
	if ($DisableSourceRetention) {
		$PfaTempSnapshots = Get-Pfa2VolumeSnapshot -Array $sourceFAConnection -Destroyed $false | Where-Object { $_.Name -cmatch ($PfaSnapshotSource.Name.Split('.')[0] + ".VEEAM-ProdSnap-FA-Snapshot-Job") }
		ForEach ($PfaTempSnapshot in $PfaTempSnapshots) {
			If ($PfaTempSnapshot.Id -ne $PfaSnapshotSource.Id) {
				Remove-Pfa2VolumeSnapshot -Array $sourceFAConnection -Ids $PfaTempSnapshot.Id
			}
		}
	}
}
# Disconnect from FlashArray
Disconnect-Pfa2Array -Array $sourceFAConnection
Disconnect-Pfa2Array -Array $targetFAConnection

# Tell VBR to Rescan Connected FlashArrays
if($RescanAfterJob) {
	$PlugInHosts = Get-StoragePluginHost -PluginType "FlashArray"
	ForEach ($PlugInHost in $PlugInHosts) {
		Sync-StoragePluginHost -Host $PlugInHost
	} 
}