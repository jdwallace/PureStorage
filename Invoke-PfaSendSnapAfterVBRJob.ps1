<#	
	.NOTES
	===========================================================================
	 Created on:   	1/26/2021
	 Updated on:    1/27/2021
	 Created by:   	JD Wallace
     Filename:     	Invoke-PfaSendSnapAfterVBRJob.ps1
     Acknowledgements: 
     Get Veeam Job Name - https://blog.mwpreston.net/2016/11/17/setting-yourself-up-for-success-with-veeam-pre-job-scripts/
	===========================================================================
	.DESCRIPTION
    A Veeam VBR post-job script to be used with Pure FlashArray snapshot only job. Will replicate the new snapshot to a secondary FlashArray.
    Requires Purity//FA 6.1.0 or later.
#>

Add-PSSnapin VeeamPSSnapIn
Import-Module PureStoragePowerShellSDK2

# FlashArray OAuth2 Connection Variables for Primary FlashArray
<#
$arrayEndpoint = "fa-1.homelab.local"
$arrayUsername = "vbr-server"
$clientName = "VeeamPowerShell"
$arrayIssuer = $Clientname
$clientId = "5772f75a-df1c-4aca-843a-304abf875741"
$keyId = "ed6d4780-61d9-4c5e-8ac0-39c48c9c85d9"
$privateKeyFile = "C:\Users\Administrator.HOMELAB\.ssh\Pure¦fa-1.homelab.local¦vbr-server¦VeeamPowerShell¦5772f75a-df1c-4aca-843a-304abf875741¦ed6d4780-61d9-4c5e-8ac0-39c48c9c85d9¦private.pem"
#>

# FlashArray Credential for user/password authentication
# Required since we're using Invoke-Pfa2CLICommand, will be replaced by OAuth2 in the future
$arrayUsername = "vbr-server"
$arrayPassword = ConvertTo-SecureString "MyPassword" -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPassword 

# Destination Array - Must already be connected to Primary FlashArray
$PfaSnapTarget = "FA-2"

# Get Veeam job name from parent process id
<#
$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
$jobid = $parentcmd.split('" "')[16]
$VbrJob = get-vbrjob | where-object { $_.Id -eq "$jobid" }
#>

# Get specific job (for development only)
$VbrJob = Get-VBRJob | Where-Object { $_.Name -eq "Test - VMonFA" }
$VbrSession = Get-VBRBackupSession | Where-Object {$_.jobId -eq $VbrJob.Id.Guid} | Sort-Object EndTimeUTC -Descending | Select-Object -First 1
$VbrTaskSession = $VbrSession | Get-VBRTaskSession -Name "VMonFA"


if (($VbrJob.info.TargetDir.ToString() -eq "Pure Storage Storage") -and $VbrSession.IsCompleted) {
	$JobRepo = $VbrJob.FindTargetRepository()

	# Connect to FlashArray via OAuth2 (Not used, unsupported by Invoke-Pfa2CLICommand)
	# $FlashArray = Connect-Pfa2Array -Endpoint $arrayEndpoint -Username $arrayUsername -Issuer $arrayIssuer -ApiClientName $clientName -ClientId $clientId -KeyId $keyId -PrivateKeyFile $privateKeyFile -IgnoreCertificateError

	# Connect to FlashArray with user/password
	$FlashArray = Connect-Pfa2Array -EndPoint $arrayEndpoint -Credential $arrayCredential -IgnoreCertificateError

	$jobSnap = "VMonFA.VEEAM-ProdSnap-Test---VMonFA-1B1096gCeP-wKmdZxLaE9nXsTA2m-frDgz" #TODO Figure out how to get snapshot name from Veeam job / Also might be multiple snaps
	$snapSendCLI = "purevol send --to $PfaSnapTarget $jobSnap"

	# Invoke-Pfa2CLICommand to call "purevol send" to replicate the new snapshot
	Invoke-Pfa2CLICommand -EndPoint $arrayEndpoint -Credential $arrayCredential -CommandText $snapSendCLI

	# Disconnect from FlashArray
	Disconnect-Pfa2Array -Array $FlashArray
}