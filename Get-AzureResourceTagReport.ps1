# Import Az modules
Import-Module Az.Accounts
Import-Module Az.Resources

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount | Out-Null

try {
    # Prompt for required tags to audit against
    Write-Host "`nEnter the tag keys that should be present on all resources." -ForegroundColor Cyan
    Write-Host "Separate multiple tags with a comma (e.g. Environment,Project,Owner)"

    do {
        $tagInput = Read-Host "Required tag keys"
        $tagInput  = $tagInput.Trim()
    } while ([string]::IsNullOrWhiteSpace($tagInput))

    $requiredTags = $tagInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    Write-Host "Auditing for tags: $($requiredTags -join ', ')" -ForegroundColor Cyan

    # Get all subscriptions
    try {
        $subscriptions = Get-AzSubscription -ErrorAction Stop
        Write-Host "Found $($subscriptions.Count) subscription(s)."
    }
    catch {
        Write-Host "Error retrieving subscriptions: $_" -ForegroundColor Red
        exit
    }

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

        # Get all resources in the subscription
        try {
            $resources = Get-AzResource -ErrorAction Stop
            Write-Host "Found $($resources.Count) resource(s) in $($subscription.Name)."
        }
        catch {
            Write-Host "Error retrieving resources in subscription '$($subscription.Name)': $_" -ForegroundColor Yellow
            continue
        }

        foreach ($resource in $resources) {
            # Check which required tags are missing
            $missingTags = $requiredTags | Where-Object {
                -not $resource.Tags -or -not $resource.Tags.ContainsKey($_)
            }

            $compliant    = if ($missingTags.Count -eq 0) { "Compliant" } else { "Non-compliant" }
            $missingList  = if ($missingTags.Count -gt 0) { $missingTags -join "; " } else { "None" }

            # Build existing tags string
            $existingTags = if ($resource.Tags -and $resource.Tags.Count -gt 0) {
                ($resource.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
            } else { "No tags" }

            $results.Add([PSCustomObject]@{
                "Subscription"   = $subscription.Name
                "Resource Name"  = $resource.Name
                "Resource Type"  = $resource.ResourceType
                "Resource Group" = $resource.ResourceGroupName
                "Location"       = $resource.Location
                "Tag Status"     = $compliant
                "Missing Tags"   = $missingList
                "Existing Tags"  = $existingTags
            })
        }
    }

    if ($results.Count -eq 0) {
        Write-Host "No resources found across any subscriptions." -ForegroundColor Yellow
        exit
    }

    $nonCompliant = ($results | Where-Object { $_."Tag Status" -eq "Non-compliant" }).Count
    Write-Host "`n$nonCompliant of $($results.Count) resource(s) are missing one or more required tags."

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\AzureResourceTagReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-AzAccount | Out-Null
    Write-Host "Disconnected from Azure."
}
