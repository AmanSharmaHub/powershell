# Import the Az module
Import-Module Az.Accounts
Import-Module Az.Compute

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount | Out-Null

# Ask the user whether to run in report-only or delete mode
Write-Host "`nRun mode:" -ForegroundColor Cyan
Write-Host "  [1] Report only  — list unattached disks, no changes made"
Write-Host "  [2] Delete mode  — prompt before deleting each unattached disk"

do {
    $modeInput = Read-Host "Enter 1 or 2"
} while ($modeInput -notin @('1', '2'))

$deleteMode = $modeInput -eq '2'

if ($deleteMode) {
    Write-Host "`nDelete mode enabled. You will be prompted before each deletion." -ForegroundColor Yellow
} else {
    Write-Host "`nReport-only mode. No changes will be made." -ForegroundColor Cyan
}

# Get all subscriptions
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

    # Get all managed disks that are not attached to a VM
    try {
        $unattachedDisks = Get-AzDisk -ErrorAction Stop |
            Where-Object { $_.DiskState -eq 'Unattached' }

        Write-Host "Found $($unattachedDisks.Count) unattached disk(s) in $($subscription.Name)."
    }
    catch {
        Write-Host "Error retrieving disks in subscription '$($subscription.Name)': $_" -ForegroundColor Yellow
        continue
    }

    foreach ($disk in $unattachedDisks) {
        # Extract tags as a readable string
        $tags = if ($disk.Tags -and $disk.Tags.Count -gt 0) {
            ($disk.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
        } else { "No tags" }

        $status = "Unattached"

        Write-Host "`n  Disk: $($disk.Name)"
        Write-Host "  Resource Group : $($disk.ResourceGroupName)"
        Write-Host "  Size           : $($disk.DiskSizeGB) GB"
        Write-Host "  SKU            : $($disk.Sku.Name)"
        Write-Host "  Location       : $($disk.Location)"

        if ($deleteMode) {
            $confirm = Read-Host "  Delete this disk? (yes/no)"
            if ($confirm -eq 'yes') {
                try {
                    Remove-AzDisk -ResourceGroupName $disk.ResourceGroupName `
                        -DiskName $disk.Name -Force -ErrorAction Stop | Out-Null
                    Write-Host "  Deleted." -ForegroundColor Green
                    $status = "Deleted"
                }
                catch {
                    Write-Host "  Error deleting disk: $_" -ForegroundColor Red
                    $status = "Error deleting"
                }
            } else {
                Write-Host "  Skipped." -ForegroundColor Yellow
                $status = "Skipped"
            }
        }

        $results.Add([PSCustomObject]@{
            "Subscription"   = $subscription.Name
            "Resource Group" = $disk.ResourceGroupName
            "Disk Name"      = $disk.Name
            "Size (GB)"      = $disk.DiskSizeGB
            "SKU"            = $disk.Sku.Name
            "Location"       = $disk.Location
            "Tags"           = $tags
            "Action"         = $status
        })
    }
}

if ($results.Count -eq 0) {
    Write-Host "`nNo unattached disks found across any subscriptions." -ForegroundColor Green
} else {
    # Build a portable output path
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\UnattachedDisksReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nReport exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total unattached disks found: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}

# Disconnect
Disconnect-AzAccount | Out-Null
Write-Host "Disconnected from Azure."
