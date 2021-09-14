Connect-azAccount

$vmnames = Get-Content C:\Users\sounish.bose\Desktop\newtestvm.txt
$nicnames = Get-Content C:\Users\sounish.bose\Desktop\newtestnic.txt
$datadisks = Get-Content C:\Users\sounish.bose\Desktop\datadisks.txt

$resourceGoupName = 'Interview1RG'
$azureRegion = 'East US'



#### Create the vNet for the VM
$newSubnetParams = @{
    'Name'          = 'sounishsubnet'
    'AddressPrefix' = '10.16.1.0/24'
}
$subnet = New-AzVirtualNetworkSubnetConfig @newSubnetParams -ServiceEndpoint "Microsoft.Storage"

$newVNetParams = @{
    'Name'              = 'sounishvnet'
    'ResourceGroupName' = $resourceGoupName
    'Location'          = $azureRegion
    'AddressPrefix'     = '10.16.0.0/16'
}
$vNet = New-AzVirtualNetwork @newVNetParams -Subnet $subnet
#############


##foreach ($item2 in $nicnames) {
#region Create the vNic and assign to the soon-to-be created VM
#$newVNicParams = @{
#    'Name'              = $item2
#    'ResourceGroupName' = $resourceGoupName
#    'Location'          = $azureRegion
#}
#$vNic = New-AzNetworkInterface @newVNicParams -SubnetId $vNet.Subnets[0].Id
#endregion
#}


$counter = 0

foreach ($item in $vmnames) {


######### OS Setting config

$newConfigParams = @{
    'VMName' = $item
    'VMSize' = 'Standard_B1s'
}
$vmConfig = New-AzVMConfig @newConfigParams

$newVmOsParams = @{
    'Windows'          = $true
    'ComputerName'     = $item
    'Credential'       = (Get-Credential -Message 'Type the name and password of the local administrator account.')
    'ProvisionVMAgent' = $true
    'EnableAutoUpdate' = $true
}
$vm = Set-AzVMOperatingSystem @newVmOsParams -VM $vmConfig

#######image
$newSourceImageParams = @{
    'PublisherName' = 'MicrosoftWindowsServer'
    'Version'       = 'latest'
    'Skus'          = '2019-Datacenter'
}
 
$vm = Set-AzVMSourceImage @newSourceImageParams -VM $vm -Offer 'WindowsServer'
############



############# Create the vNic and assign to  VM
$newVNicParams = @{
    'Name'              = $nicnames[$counter]
    'ResourceGroupName' = $resourceGoupName
    'Location'          = $azureRegion
}
$vNic = New-AzNetworkInterface @newVNicParams -SubnetId $vNet.Subnets[0].Id
#############



############# Add the vNic 
$vm = Add-AzVMNetworkInterface -VM $vm -Id $vNic.Id

#############

############# Create the OS disk
$osDiskName = 'OSDisk' + "$counter"
$storageType = 'Premium_LRS'
$osDiskSize = "128"
#$osDiskUri = $storageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $item + $osDiskName + ".vhd"
 
#$newOsDiskParams = @{
#    'Name'         = 'OSDisk' + "$counter"
#    'CreateOption' = 'fromImage'
#}
 
#$vm = Set-AzVMOSDisk @newOsDiskParams -VM $vm -VhdUri $osDiskUri

$vm = Set-AzVMOSDisk -VM $vm -Name $osDiskName -StorageAccountType $storageType -DiskSizeInGB $osDiskSize -CreateOption FromImage -Caching $osDiskCaching
#############

############# Create the $vm variable and create the VM
New-AzVM -VM $vm -ResourceGroupName $resourceGoupName -Location $azureRegion


##############

############## Create and attach data disk
$getvm = Get-AzVM -Name $item -resourceGroupName $resourceGoupName

$dataDiskName = $item + '_datadisk1'

$diskConfig = New-AzDiskConfig -SkuName $storageType -Location $azureRegion -CreateOption Empty -DiskSizeGB 64
$dataDisk1 = New-AzDisk -DiskName $dataDiskName -Disk $diskConfig -ResourceGroupName $resourceGoupName

$getvm = Add-AzVMDataDisk -VM $getvm -Name $dataDiskName -CreateOption Attach -ManagedDiskId $dataDisk1.Id -Lun 1

Update-AzVM -VM $getvm -ResourceGroupName $resourceGoupName
##############


############## Create Log Analytics Workspace and add VMs
$Workspace = New-AzOperationalInsightsWorkspace -Location $azureRegion -Name SounishAnalytics -Sku Standard -ResourceGroupName $resourceGoupName

$vWorkspaceID = $Workspace.CustomerID
$vworkspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).PrimarySharedKey

foreach ($item3 in $vmnames) {

Set-AzVMExtension -ResourceGroupName $resourceGoupName -VMName $item3 -Name ‘MicrosoftMonitoringAgent’ -Publisher ‘Microsoft.EnterpriseCloud.Monitoring’ -ExtensionType ‘MicrosoftMonitoringAgent’ -TypeHandlerVersion ‘1.0’ -Location $azureRegion -SettingString '{"workspaceId": "$vWorkspaceID"}' -ProtectedSettingString '{"workspaceKey": "$vworkspaceKey"}'
}
##############

############# Stop the VM
Stop-AzVM -ResourceGroupName $resourceGoupName -Name $item -Force


$counter++
}

############## Create NSG with rules and add to subnet
$rule1 = New-AzNetworkSecurityRuleConfig -Name http-rule -Description "Deny HTTP" -Access Deny -Protocol Tcp -Direction Outbound -Priority 101 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80
$rule2 = New-AzNetworkSecurityRuleConfig -Name https-rule -Description "Deny HTTPS" -Access Deny -Protocol Tcp -Direction Outbound -Priority 102 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGoupName -Location $azureRegion -Name "NSG-Outbound" -SecurityRules $rule1,$rule2

Set-AzVirtualNetworkSubnetConfig -Name sounishsubnet -VirtualNetwork sounishvnet -AddressPrefix "10.16.1.0/24" -NetworkSecurityGroup $nsg
##############

############## Create the storage account
$newStorageAcctParams = @{
    'Name'              = 'sounishstorage'
    'ResourceGroupName' = $resourceGoupName
    'Type'              = 'Premium_LRS'
    'Location'          = $azureRegion
}
$storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGoupName -AccountName "sounishstorage" -Type Premium_LRS -Location $azureRegion

Update-AzStorageAccountNetworkRuleSet -ResourceGroupName "$resourceGoupName" -AccountName "sounishstorage" -Bypass AzureServices,Metrics -DefaultAction Deny -VirtualNetworkRule (@{VirtualNetworkResourceId="/subscriptions/c01a2c55-6804-428b-9d71-a21ba01f32e1/resourceGroups/$azureRegion/providers/Microsoft.Network/virtualNetworks/sounishvnet/subnets/sounishsubnet";Action="allow"})

##############


############## Create Automation Account and create a schedule to update taget VMs
New-AzAutomationAccount -Name "SounishAutomationAccount" -Location $azureRegion -ResourceGroupName $resourceGoupName

foreach ($item3 in $vmnames) {

$targetMachines = @()
$getvm3 = Get-AzVM -Name $item3 -resourceGroupName $resourceGoupName
$vmresourceid = $getvm3.Id

$targetMachines += "/subscriptions/$vmresourceid/resourceGroups/$resourceGoupName/providers/Microsoft.Compute/virtualMachines/$item3"


}

##############