[CmdletBinding()]
param (
[Parameter(Mandatory)]
[string]$firewallName,
[Parameter(Mandatory)]
[string]$resourceGroupName,
[Parameter(Mandatory)]
[string]$storageaccount,
[Parameter(Mandatory)]
[string]$container,
[Parameter(Mandatory)]
[ValidateSet("FirewallInfo.json")]
[string]$firewallinfofile,
[Parameter(Mandatory)]
[ValidateSet('start','stop')]
[string]$operation
)

$servicePrincipalConnection = Get-AutomationConnection -Name AzureRunAsConnection
Connect-AzAccount -ServicePrincipal -Tenant $servicePrincipalConnection.TenantID -ApplicationId $servicePrincipalConnection.ApplicationID -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$subscriptionID = $servicePrincipalConnection.SubscriptionId

Set-StrictMode -Version Latest
$ErrorActionPreference = "stop"
$VerbosePreference = 'Continue'

#Import Modules
try {
    Import-Module -Name Az.Network -MinimumVersion 1.14.0
}
catch {
    throw "Could not import Module: $($_.Exception.Message)"
}

#Get Firewall
write-verbose -message "Get Firewall: $firewallName"
$fwObject = Get-AzFirewall -Name $firewallName -ResourceGroupName $resourceGroupName
If (!$fwObject) {
    throw "No Firewall Found: $firewallName"
}

Switch ($operation.ToLower()) {
    "stop" {
        #Save or update the current State and Metadata to JSON file in the Storage Account
        try {
            write-verbose -message "Parsing Firewall Object Details"
            $virtualNetworkName = ((($fwobject.IpConfigurations | Where-Object {$_.Subnet}).Subnet.Id -split '/subnets')[0] -split('/'))[-1] 
            $publicIpAddressIds = $fwObject.IpConfigurations.PublicIPAddress.Id
            $publicIPs = @()
            Foreach ($pip in $publicIpAddressIds) {
                write-verbose -message "Querying Public IP Object: $pip"
                $fwPublicIpAddress = (Get-AzPublicIpAddress -Name ($pip -split '/')[-1]).IpAddress
                $publicIPs += $fwPublicIpAddress
            }
            $fwEntity = [PSCUSTOMOBJECT]@{
                PublicIPAddresses = $publicIPs
                VirtualNetwork = $virtualNetworkName
                resourceGroupName = $resourceGroupName
            }
            $fwEntity = $fwEntity | ConvertTo-Json
            #Create a file called FirewallInfo.json locally
            New-Item -Path . -Name "$firewallinfofile" -ItemType "file" -Value $fwEntity
            try {
                write-verbose -message "Upload $firewallinfofile to Storage Account"
                
                $ctx=(Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageaccount).Context
                Set-AzStorageBlobContent -Force -File ".\$firewallinfofile" -Container $container -Blob "$firewallinfofile" -Context $ctx 

            } catch {
                throw "failed to save firewall information to Storage Account. skipping stop operation"
            }
        } catch {
            throw "Error gathering current IP Configuration: $($_.Exception.Message)"
        }

        #Stop the Firewall Instance and Update
        try {
            $fwObject.Deallocate()
            write-output "Stopping Firewall: $firewallName"
            # Set-AzFirewall -AzureFirewall $fwObject | Out-Null
        } catch {
            throw "Could not deallocate Firewall: $($fwObject.Name). $($_.Exception.Message)"
        }
    }
    "start" {
        #Get the FirewallInfo.json from storage account
        try {
            write-verbose -message "Reading information from $firewallinfofile" 
            $storageAcc=Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageaccount
            $ctx=$storageAcc.Context
            Get-AzStorageBlobContent -Container $container  -Context $ctx -Blob $firewallinfofile -Destination . -Force
            $fwIpConfig = Get-Content -Path ".\$firewallinfofile" | ConvertFrom-Json
            If (!$fwIpConfig) {
                throw "Error: No IP Configuration found in $firewallinfofile"
            }
            $virtualNetworkName = $fwIpConfig.VirtualNetwork
            $resourceGroupName  = $fwIpConfig.resourceGroupName
            $PublicIPAddresses  = $fwIpConfig.PublicIPAddresses
            write-verbose "$virtualNetworkName $resourceGroupName $PublicIPAddresses"
        } catch {
            throw "Error Getting entry for Azure Firewall: $($fwObject.Name). $($_.Exception.Message)"
        }
        #Attach the Public IP/s on to the Firewall.
        try {
            #get the vnet
            write-verbose -message "Query virtual Network Object: $($fwIpConfig.VirtualNetwork)"
            $vnet = Get-AzVirtualNetwork -ResourceGroupName $fwIpConfig.resourceGroupName -Name $fwIpConfig.VirtualNetwork
            
            #Allocate Primary Public IP
            write-verbose -message ('Allocating Primary Public IP Address:' + ($fwIpConfig.PublicIPAddresses)[0])
            $primaryPublicIp = Get-AzPublicIpAddress | where-object { $_.IpAddress -eq ($fwIpConfig.PublicIPAddresses)[0]}
            $prim = ($fwIpConfig.PublicIPAddresses)[0]
            try {
                $fwObject.Allocate($vnet,$primaryPublicIp)
            } Catch {
                write-warning $_.Exception.Message
            }
            

            Foreach ($pip in $fwIpConfig.PublicIPAddresses) {
                write-verbose -message ("$pip - $prim")
                If ($pip -notmatch $prim) {
                    try {
                        write-verbose -message "Allocating Additional Public IP: $pip"
                        $publicip = Get-AzPublicIpAddress | where-object {$_.IpAddress -eq $pip}
                        $fwObject.AddPublicIpAddress($publicip)
                    } Catch {
                        write-warning $_.Exception.Message
                    }
                }
            }
            #Update / Start the firewall instance
            write-output "Starting Firewall: $firewallName"
            # Set-AzFirewall -AzureFirewall $fwObject
        } catch {
            throw "Could not Azure Firewall: $($fwObject.Name). $($_.Exception.Message)"
        } 
    }
}