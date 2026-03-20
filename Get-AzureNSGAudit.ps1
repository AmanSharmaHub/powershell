# Import Az modules
Import-Module Az.Accounts
Import-Module Az.Network

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount | Out-Null

try {
    # Get all subscriptions
    try {
        $subscriptions = Get-AzSubscription -ErrorAction Stop
        Write-Host "Found $($subscriptions.Count) subscription(s)." -ForegroundColor Cyan
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

        # Get all NSGs in the subscription
        try {
            $nsgs = Get-AzNetworkSecurityGroup -ErrorAction Stop
            Write-Host "Found $($nsgs.Count) NSG(s) in $($subscription.Name)."
        }
        catch {
            Write-Host "Error retrieving NSGs in subscription '$($subscription.Name)': $_" -ForegroundColor Yellow
            continue
        }

        foreach ($nsg in $nsgs) {
            # Get all security rules (custom + default)
            $allRules = @($nsg.SecurityRules) + @($nsg.DefaultSecurityRules)

            if ($allRules.Count -eq 0) {
                $results.Add([PSCustomObject]@{
                    "Subscription"        = $subscription.Name
                    "NSG Name"            = $nsg.Name
                    "Resource Group"      = $nsg.ResourceGroupName
                    "Location"            = $nsg.Location
                    "Rule Name"           = "No rules defined"
                    "Rule Type"           = "N/A"
                    "Direction"           = "N/A"
                    "Priority"            = "N/A"
                    "Access"              = "N/A"
                    "Protocol"            = "N/A"
                    "Source"              = "N/A"
                    "Source Port"         = "N/A"
                    "Destination"         = "N/A"
                    "Destination Port"    = "N/A"
                })
                continue
            }

            foreach ($rule in $allRules) {
                $ruleType = if ($nsg.DefaultSecurityRules.Name -contains $rule.Name) {
                    "Default"
                } else { "Custom" }

                $results.Add([PSCustomObject]@{
                    "Subscription"        = $subscription.Name
                    "NSG Name"            = $nsg.Name
                    "Resource Group"      = $nsg.ResourceGroupName
                    "Location"            = $nsg.Location
                    "Rule Name"           = $rule.Name
                    "Rule Type"           = $ruleType
                    "Direction"           = $rule.Direction
                    "Priority"            = $rule.Priority
                    "Access"              = $rule.Access
                    "Protocol"            = $rule.Protocol
                    "Source"              = ($rule.SourceAddressPrefix -join "; ")
                    "Source Port"         = ($rule.SourcePortRange -join "; ")
                    "Destination"         = ($rule.DestinationAddressPrefix -join "; ")
                    "Destination Port"    = ($rule.DestinationPortRange -join "; ")
                })
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-Host "No NSG rules found across any subscriptions." -ForegroundColor Yellow
        exit
    }

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\AzureNSGAudit_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total rules exported: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-AzAccount | Out-Null
    Write-Host "Disconnected from Azure."
}
