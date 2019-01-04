# Settings
#=== Log
$isLogFileEnabled = $false
$logFilePath = "C:\temp\johan.log"
#=== DNS Zones
$dnsZones = @("epm.local")
#=== Output
#= SQL # NOT IMPLEMENTED YET
$isSqlOutputEnabled = $false
$sqlConnectionString = [string]::Empty
#= CSV
$isCsvOutputEnabled = $true
$csvFilePath = "C:\temp\dnshistory.csv"
$csvData = $null
#= Syslog
$syslogServer = $null
$syslogPort = $null

# Functions
function Write-Log
{
    param
    (
        [string]
        $Info,
        [switch]
        $IsError
    )
    $output = [string]::Empty
    if ($IsError)
    {
        $output = "[ERROR] === [UTC:$([System.DateTime]::UtcNow)] === $info"
    }
    else 
    {
        $output = "[INFO] === [UTC:$([System.DateTime]::UtcNow)] === $info"
    }
    if ($isLogFileEnabled)
    {
        $output | Out-File $logFilePath -Append -Encoding utf8
    }
    Write-Output $output
}
function Verify-CsvOutput
{
    param
    (
        $DnsData
    )
    if (!(Test-Path $csvFilePath))
    {
        Write-Log -Info "CSV file for output was not created, creating it"
        try
        {
            New-Item -Path $csvFilePath -ItemType "File"
            $DnsData | ConvertTo-Csv -Delimiter ";" -NoTypeInformation | Out-File $csvFilePath -Encoding utf8
        }
        catch
        {
            Write-Log -Info "Failed to create CSV file for output"
            Read-Host
            exit
        }
    }
}
function Get-CsvData
{
    $records = @()
    Import-Csv -Path $csvFilePath -Delimiter ";" -Encoding utf8 | ForEach-Object{
        $dnsData = [DnsData]::new()
        $dnsData.Discovered = $_.Discovered
        $dnsData.HostName = $_.Hostname
        $dnsData.IPAddress = $_.IPAddress
        $dnsData.RecordType = $_.RecordType
        $records += $dnsData
    }
    return $records
}
function Construct-DnsDataClassInstance
{
    param
    (
        $DnsData
    )
    $dnsObj = [DnsData]::new()
    if ($null -eq $DnsData.Discovered)
    {
        $dnsObj.Discovered = [DateTime]::UtcNow
    }
    else 
    {
        $dnsObj.Discovered = $DnsData.Discovered
    }
    $dnsObj.HostName = $DnsData.Hostname
    $dnsObj.IPAddress = $DnsData.RecordData.IPv4Address.IPAddressToString
    $dnsObj.RecordType = $DnsData.RecordType
    return $dnsObj
}
function Write-CsvOutput
{
    param
    (
        $DnsData
    )
    $DnsData | ConvertTo-Csv -Delimiter ";" -NoTypeInformation | Out-File -FilePath $csvFilePath -Encoding utf8
}

# Classes
class DnsData
{
    [string]$HostName
    [string]$RecordType
    [string]$IPAddress
    [DateTime]$Discovered
}

# Check that the DnsServer module is present, else exit
if (!(Get-Module -Name "DnsServer"))
{
    Write-Log -Info "DnsServer module was not found!" -IsError
    Read-Host
    exit
}

Write-Log -Info "Loading DnsServer module..."
try
{
    Import-Module "DnsServer"
}
catch
{
    Write-Log -Info "Failed to Import-Module DnsServer, Exception: $($_.Exception.Message)"
    Read-Host
    exit
}

foreach ($zone in $dnsZones)
{
    Write-Log -Info "Getting all DNS records for zone"
    #$records = Get-DnsServerResourceRecord -ZoneName $zone | Select-Object Hostname,RecordType -ExpandProperty RecordData
    $records = @()
    Get-DnsServerResourceRecord -ZoneName $zone |Where-Object{$_.RecordType -ne "SRV"} | ForEach-Object{
        $records += Construct-DnsDataClassInstance -DnsData $_
    }
    
    # CSV OUTPUT
    if ($isCsvOutputEnabled)
    {
        Verify-CsvOutput -DnsData $records # Make sure the file is created 
        $csvData = Get-CsvData
        foreach ($record in $records)
        {
            # We dont want to itterate records without IP addresses or the default @ address
            if ([string]::IsNullOrEmpty($record.IPAddress) -or $record.Hostname -eq "@")
            {
                continue
            }
            # Check how many matches on hostname we have in the data
            $matchesInCsvData = $csvData | Where-Object{$_.Hostname -eq $record.Hostname}
            if ($matchesInCsvData.Count -le 0)
            {
                # No matches was found so we add this new record to the data
                Write-Log -Info "New record was found!"
                $record.Discovered = [DateTime]::UtcNow
                $csvData += $record
                continue
            }
            elseif ($matchesInCsvData.Count -eq 1)
            {
                # If only one match was found we can compare the IP address directly
                if ($matchesInCsvData.IPAddress -ne $record.IPAddress)
                {
                    # The IP address was not equal, adding new row
                    Write-Log -Info "Record with modified IP address was found"
                    $record.Discovered = [DateTime]::UtcNow
                    $csvData += $record
                    continue
                }
            }
            else
            {
                # Multiple matches was found on the hostname, check if any of them has this IPAddress
                if ($matchesInCsvData.IPAddress -notcontains $record.IPAddress)
                {
                    # None of them had this IPAddress, add as new row
                    Write-Log -Info "Record with hostname $($record.Hostname) already in source was found but not with this IP address $($record.IPAddress)"
                    $record.Discovered = [DateTime]::UtcNow
                    $csvData += $record
                    continue
                }
            }
        }
        Write-CsvOutput -DnsData $csvData

        # Check if any DNS records have been removed
        $uniqueFromCsv = $csvData | Select-Object Hostname -Unique
        $uniqueFromServer = $records | Select-Object Hostname -Unique
        $diff = Compare-Object -ReferenceObject $uniqueFromCsv -DifferenceObject $uniqueFromServer
        if ($diff.Count -ge 1)
        {
            Write-Log -Info "Not all records in csvData was found in the server records, looking which have been removed"
            $diff | Where-Object{$_.SideIndicator -eq "<="} | %{
                Write-Log -Info "[ENTRY_REMOVED]" # RESUME HERE ###############################################################
            }
        }
    }
}

