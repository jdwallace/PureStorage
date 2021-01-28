<#	
	.NOTES
	===========================================================================
	 Created on:   	1/26/2021
	 Updated on:    1/27/2021
	 Created by:   	JD Wallace
	 Filename:     	Invoke-PfaSendSnapAfterVBRJob.ps1
	 Acknowledgements: 
	 Get Veeam Job Name From Process ID - https://blog.mwpreston.net/2016/11/17/setting-yourself-up-for-success-with-veeam-pre-job-scripts/
	===========================================================================
	.DESCRIPTION
	A Veeam VBR post-job script to be used with Pure FlashArray snapshot only job. Will replicate the new snapshot to a secondary FlashArray.
    Requires Purity//FA 6.1.0 or later.
#>

Add-PSSnapin VeeamPSSnapIn
Import-Module PureStoragePowerShellSDK2

# Primary FlashArray Credential for user/password authentication
# Required since we're using Invoke-Pfa2CLICommand, will be replaced by OAuth2 in the future
$arrayEndpoint = "fa-1.homelab.local"
$arrayUsername = "pureuser"
$arrayPassword = ConvertTo-SecureString "pureuser" -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPassword 

# Destination FlashArray - Must already be connected to Primary FlashArray
$PfaSnapTarget = "FA-2"

# Connect to FlashArray with user/password
$FlashArray = Connect-Pfa2Array -EndPoint $arrayEndpoint -Credential $arrayCredential -IgnoreCertificateError

# Get Veeam job name from parent process id
$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
$jobid = $parentcmd.split('" "')[16]
$VbrJob = get-vbrjob | where-object { $_.Id -eq "$jobid" }

# Get specific job (for testing only)
# $VbrJob = Get-VBRJob | Where-Object { $_.Name -eq "FA Snapshot Job" }

# Get latest job Session (should be the session that called this script)
$VbrSession = Get-VBRBackupSession | Where-Object {$_.jobId -eq $VbrJob.Id.Guid} | Sort-Object EndTimeUTC -Descending | Select-Object -First 1

# Get all FlashArray snapshots created from this Job
$jobNameInSnap = ".VEEAM-ProdSnap-" + $VbrJob.Name -replace ' ','-'
$PfaSnapshots = Get-StoragePluginSnapshot | Where-Object { $_.Name -cmatch $jobNameInSnap }

#For each FlashArray snapshot, check that it's from the latest session and replicate if so
ForEach ($PfaSnapshot in $PfaSnapshots)
{
	# If Snapshot was created after latest session start time, it must have been created during this session
	If ($PfaSnapshot.CreationTimeSrv -gt $VbrSession.Info.CreationTime)
	{
		# Construct 'purevol send' command
		$snapSendCLI = "purevol send --to $PfaSnapTarget " + $PfaSnapshot.Name
		# Invoke-Pfa2CLICommand to call 'purevol send' to replicate the snapshot
		Invoke-Pfa2CLICommand -EndPoint $arrayEndpoint -Credential $arrayCredential -CommandText $snapSendCLI
	}
}
# Disconnect from FlashArray
Disconnect-Pfa2Array -Array $FlashArray