# Import the Az module
Import-Module Az.Accounts
Import-Module Az.Compute

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount | Out-Null

# Get all subscriptions the account has access to
try {
    $subscriptions = Get-AzSubscription -ErrorAction Stop
    if ($subscriptions.Count -eq 0) {
        Write-Host "No subscriptions found for this account." -ForegroundColor Red
        exit
    }
    Write-Host "Found $($subscriptions.Count) subscription(s)." -ForegroundColor Cyan
}
catch {
    Write-Host "Error retrieving subscriptions: $_" -ForegroundColor Red
    exit
}

# Use a generic list to store results
$results = [System.Collections.Generic.List[object]]::new()

foreach ($subscription in $subscriptions) {
    Write-Host "`nSwitching to subscription: $($subscription.Name)" -ForegroundColor Cyan

    try {
        Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    }
    catch {
        Write-Host "Could not switch to subscription '$($subscription.Name)': $_" -ForegroundColor Yellow
        continue
    }

    # Get all VMs in the subscription
    try {
        $vms = Get-AzVM -Status -ErrorAction Stop
        Write-Host "Found $($vms.Count) VM(s) in $($subscription.Name)."
    }
    catch {
        Write-Host "Error retrieving VMs in subscription '$($subscription.Name)': $_" -ForegroundColor Yellow
        continue
    }

    foreach ($vm in $vms) {
        # Extract OS type
        $osType = if ($vm.StorageProfile.OsDisk.OsType) {
            $vm.StorageProfile.OsDisk.OsType.ToString()
        } else { "Unknown" }

        # Extract power state cleanly
        $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" } |
            Select-Object -First 1).DisplayStatus
        if (-not $powerState) { $powerState = "Unknown" }

        # Extract tags as a readable string
        $tags = if ($vm.Tags -and $vm.Tags.Count -gt 0) {
            ($vm.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
        } else { "No tags" }

        $results.Add([PSCustomObject]@{
            "Subscription"     = $subscription.Name
            "Resource Group"   = $vm.ResourceGroupName
            "VM Name"          = $vm.Name
            "Location"         = $vm.Location
            "VM Size"          = $vm.HardwareProfile.VmSize
            "OS Type"          = $osType
            "Power State"      = $powerState
            "Tags"             = $tags
        })
    }
}

if ($results.Count -eq 0) {
    Write-Host "`nNo VMs found across any subscriptions." -ForegroundColor Yellow
    exit
}

# Build a portable output path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputPath = Join-Path $env:USERPROFILE "Desktop\AzureVMReport_$timestamp.csv"

# Export to CSV
try {
    $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nReport exported to: $outputPath" -ForegroundColor Green
    Write-Host "Total VMs found: $($results.Count)"
}
catch {
    Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
}

# Disconnect
Disconnect-AzAccount | Out-Null
Write-Host "Disconnected from Azure."
