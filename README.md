# Azure Firewall Operator

Turn Azure Firewall On or Off for Cost Efficiency.
This Powershell script can be run as-is or via Azure Runbook.

This script can deallocate and reallocate multiple Public IPs back to the Azure Firewall.

## Requirements

1. An existing Azure Firewall
1. An existing Storage Account
1. An existing Storage Account Container

## Parameters

|Name|Type|Description|Mandatory|
|--|--|--|--|
|operation|string|Valid values: `start` or `stop`|`true`|
|resourcegroupname|string|Name of the Azure Firewall resource group|`true`|
|firewallname|string|Name of the Azure Firewall resource|`true`|
|storageacount|string|Name of the Azure Storage Account. This is where the firewall metadata will be saved.|`true`|
|container|string|Name of the Storage Acount Container|`true`|
|firewallinfofile|string|Strictly named "**FirewallInfo.json**" to prevent confusion. To be saved as a Blob|`true`|

### Spare a dollar for a broke IT Professional

[Buy me a Coffee](https://www.buymeacoffee.com/jcbagtas)
