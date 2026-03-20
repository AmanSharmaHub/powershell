# Import the Exchange Online module
Import-Module ExchangeOnlineManagement

# Connect to Exchange Online
Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false

try {
    # Prompt for the CSV file path
    do {
        $csvPath = Read-Host "Enter the full path to the input CSV file"
        if (-not (Test-Path $csvPath)) {
            Write-Host "File not found. Please check the path and try again." -ForegroundColor Yellow
        }
    } while (-not (Test-Path $csvPath))

    # Load the CSV
    try {
        $inputData = Import-Csv -Path $csvPath -ErrorAction Stop
    }
    catch {
        Write-Host "Error reading CSV file: $_" -ForegroundColor Red
        exit
    }

    # Validate required columns
    $requiredColumns = @('UserPrincipalName', 'InternalMessage', 'ExternalMessage')
    $csvColumns = $inputData[0].PSObject.Properties.Name

    foreach ($col in $requiredColumns) {
        if ($col -notin $csvColumns) {
            Write-Host "CSV is missing required column: '$col'" -ForegroundColor Red
            Write-Host "Required columns: UserPrincipalName, InternalMessage, ExternalMessage" -ForegroundColor Yellow
            Write-Host "Optional columns: StartTime, EndTime (format: yyyy-MM-dd HH:mm)" -ForegroundColor Yellow
            exit
        }
    }

    Write-Host "Found $($inputData.Count) row(s) in the CSV." -ForegroundColor Cyan

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $inputData) {
        $upn             = $row.UserPrincipalName.Trim()
        $internalMessage = $row.InternalMessage.Trim()
        $externalMessage = $row.ExternalMessage.Trim()
        $status          = "Success"

        Write-Host "Processing: $upn"

        # Build the parameters for Set-MailboxAutoReplyConfiguration
        $params = @{
            Identity                     = $upn
            AutoReplyState               = 'Enabled'
            InternalMessage              = $internalMessage
            ExternalMessage              = $externalMessage
            ExternalAudience             = 'All'
        }

        # Add scheduled times if provided
        if ($csvColumns -contains 'StartTime' -and -not [string]::IsNullOrWhiteSpace($row.StartTime)) {
            try {
                $params['StartTime'] = [datetime]::Parse($row.StartTime)
                $params['AutoReplyState'] = 'Scheduled'
            }
            catch {
                Write-Host "  Invalid StartTime for '$upn' — ignoring schedule." -ForegroundColor Yellow
            }
        }

        if ($csvColumns -contains 'EndTime' -and -not [string]::IsNullOrWhiteSpace($row.EndTime)) {
            try {
                $params['EndTime'] = [datetime]::Parse($row.EndTime)
            }
            catch {
                Write-Host "  Invalid EndTime for '$upn' — ignoring schedule." -ForegroundColor Yellow
            }
        }

        try {
            Set-MailboxAutoReplyConfiguration @params -ErrorAction Stop
            Write-Host "  Auto-reply set successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "  Error setting auto-reply for '$upn': $_" -ForegroundColor Red
            $status = "Error: $_"
        }

        $results.Add([PSCustomObject]@{
            "UPN"            = $upn
            "Auto Reply"     = $params['AutoReplyState']
            "Status"         = $status
        })
    }

    # Export results log to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\AutoReplyLog_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nLog exported to: $outputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Error exporting log: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    Write-Host "Disconnected from Exchange Online."
}
