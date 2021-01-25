<#	
	.NOTES
	===========================================================================
	 Created on:   	1/23/2021
	 Updated on: 	1/24/2021
	 Created by:   	JD Wallace
	 Filename:     	Get-PfaConnectionDetails.ps1
	===========================================================================
	.DESCRIPTION
		Output FlashArray connection details including Host and Volume names, LUN ID, IQN / WWN, and Volume Size.
#>

Import-Module PureStoragePowerShellSDK2

$FAReturn = Read-Host -Prompt 'Enter the FlashArray IP or DNS entry to connect'
$FlashArray = Connect-Pfa2Array -EndPoint $FAReturn -Credential (Get-Credential) -IgnoreCertificateError

$1TB = 1024*1024*1024*1024

# Create an object to store the connection details
$ConnDetails = New-Object -TypeName System.Collections.ArrayList
$Header = "HostName","VolumeName","LUNID","IQNs","WWNs","Provisioned(TB)"

# Get Connections and filter out VVOL protocol endpoints
$PureConns = (Get-Pfa2Connection -Array $FlashArray | Where-Object { !($_.Volume.Name  -eq "pure-protocol-endpoint") })

# For each Connection, build a row with the desired values from Connection, Host, and Volume objects. Add it to ConnDetails.
ForEach ($PureConn in $PureConns)
{
    $PureHost = (Get-Pfa2Host -Array $FlashArray | Where-Object { $_.Name -eq $PureConn.Host.Name })
    $PureVol = (Get-Pfa2Volume -Array $FlashArray | Where-Object { $_.Name -eq $PureConn.Volume.Name })
    $NewRow = "$($PureHost.Name),$($PureVol.Name),$($PureConn.Lun),$($PureHost.Iqns),$($PureHost.Wwns),$($PureVol.Provisioned/$1TB)"
    [void]$ConnDetails.Add($NewRow)
}

# Print ConnDetails and make it look nice
$ConnDetails | ConvertFrom-Csv -Header $Header | Sort-Object HostName | Format-Table -AutoSize