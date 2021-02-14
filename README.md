# PureStorage
 
Coding samples and tools for use with Pure Storage solutions. 

## Get-PfaConnectionDetails.ps1
Output FlashArray connection details including Host and Volume names, LUN ID, IQN / WWN, Volume Provisioned Size, and Host Capacity Written. 

## Invoke-PfaSendSnapAfterVBRJob.ps1  
This script can be used as a Veeam Backup and Replication post-job script with Pure Flash Array Snapshot Only Backup Jobs to add automated replication of FlashArray snapshots to a secondary FlashArray. If that target array is also connected to VBR via the Pure plug-in for Veeam, then those replicated snapshots will be visible in the VBR Console and may be used for Veeam recovery including Instant VM Recovery, Guest Files Recovery, and Application Item Recovery.  

For more information and configuration details, visit https://www.jdwallace.com/post/veeam-flasharray-secondary-snaps.
