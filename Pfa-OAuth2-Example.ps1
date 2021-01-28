<#	
	.NOTES
	===========================================================================
	 Created on:   	1/27/2021
	 Updated on:    1/27/2021
	 Created by:   	JD Wallace
	 Filename:     Pfa-OAuth2-Example.ps1
	===========================================================================
	.DESCRIPTION
	Example using Pure Storage PowerShell SDK 2 OAuth2
#>

Import-Module PureStoragePowerShellSDK2

# FlashArray OAuth2 Connection Variables for Primary FlashArray
$arrayEndpoint = "fa-1.homelab.local"
$arrayUsername = "vbr-server"
$clientName = "VeeamPowerShell"
$arrayIssuer = $Clientname
$clientId = "5772f75a-df1c-4aca-843a-304abf875741"
$keyId = "ed6d4780-61d9-4c5e-8ac0-39c48c9c85d9"
$privateKeyFile = "C:\Users\Administrator.HOMELAB\.ssh\Pure¦fa-1.homelab.local¦vbr-server¦VeeamPowerShell¦5772f75a-df1c-4aca-843a-304abf875741¦ed6d4780-61d9-4c5e-8ac0-39c48c9c85d9¦private.pem"

# Connect to FlashArray via OAuth2 
$FlashArray = Connect-Pfa2Array -Endpoint $arrayEndpoint -Username $arrayUsername -Issuer $arrayIssuer -ApiClientName $clientName -ClientId $clientId -KeyId $keyId -PrivateKeyFile $privateKeyFile -IgnoreCertificateError

# Disconnect from FlashArray
Disconnect-Pfa2Array -Array $FlashArray
