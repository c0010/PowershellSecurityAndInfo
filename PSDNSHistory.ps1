# Classes

# DNS records get converted to this class, only one type of object to work with
class DnsData
{
    [string]$HostName
    [string]$RecordType
    [string]$IPAddress
    [DateTime]$Discovered
    [bool]$IsDelete
}

# Instance of the config file, isn't really used in the script but is here for "declaration" of it, example config can be created with it
class ServiceConfig
{
    # General
    [string]$OutPutType # CSV,SQL
    [string]$Logfile # Full path
    # CSV
    [string]$csvFilePath # Full path
    [string]$csvRemovedFilePath # Full path
    # SQL
    [string]$sqlServerInstance
    [string]$sqlDatabase
    [string]$sqlTable
    [string]$sqlDeleteTable
    [bool]$sqlWindowsAuth   # NOT IMPLEMENTED
    [string]$sqlUsername    # NOT IMPLEMENTED
    [string]$sqlPassword    # NOT IMPLEMENTED
    # Syslog # NOT IMPLEMENTED
    [int]$syslogPort
    [string]$syslogProtocol # UDP or TCP
    [string]$syslogServer
    # DNS
    [System.Collections.ArrayList]$DnsZones
}
# === Initiate needed vars
# Import the configuration
[ServiceConfig]$global:serviceConfig = Import-Clixml .\PSDNSHistory.config
# Define global data holder vars
$global:sqlData = @()
$global:csvData = @()
# === End variable initiation

# === Functions are declared here
# = General
function Construct-DnsDataClassInstance # Yes invalid verb, whatev
{
    param
    (
        $DnsData
        #[switch]$IsDeleted
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
    $dnsObj.IsDelete = $false # Edit when implementing inline log for deletes
    # if ($IsDeleted)
    # {
    #     $dnsObj.IsDelete = $true
    # }
    return $dnsObj
}
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
    $output | Out-File $serviceConfig.Logfile -Append -Encoding utf8
    Write-Output $output
}
# = CSV
function Verify-CsvOutput # Yes invalid verb, whatev
{
    param
    (
        $DnsData
    )
    if (!(Test-Path $serviceConfig.csvFilePath))
    {
        Write-Log -Info "CSV file for output was not created, creating it"
        try
        {
            New-Item -Path $serviceConfig.csvFilePath -ItemType "File"
            $DnsData | ConvertTo-Csv -Delimiter ";" -NoTypeInformation | Out-File $serviceConfig.csvFilePath -Encoding utf8
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
    Import-Csv -Path $serviceConfig.csvFilePath -Delimiter ";" -Encoding utf8 | ForEach-Object{
        $dnsData = [DnsData]::new()
        $dnsData.Discovered = $_.Discovered
        $dnsData.HostName = $_.Hostname
        $dnsData.IPAddress = $_.IPAddress
        $dnsData.RecordType = $_.RecordType
        $dnsData.IsDelete = $_.IsDelete
        $global:csvData += $dnsData
    }
}
function Write-CsvOutput
{
    param
    (
        $DnsData
    )
    $DnsData | ConvertTo-Csv -Delimiter ";" -NoTypeInformation | Out-File -FilePath $serviceConfig.csvFilePath -Encoding utf8
}
# = SQL
function Get-SQLData
{
    $rows = Invoke-DbaQuery -SqlInstance $serviceConfig.sqlServerInstance -Database $serviceConfig.sqlDatabase -Query "SELECT * FROM $($serviceConfig.sqlTable)"
    if ($null -ne $rows)
    {
        $rows| ForEach-Object {
            $dnsData = [DnsData]::new()
            $dnsData.Discovered = $_.Discovered
            $dnsData.HostName = $_.Hostname
            $dnsData.IPAddress = $_.IPAddress
            $dnsData.RecordType = $_.RecordType
            $dnsData.IsDelete = $_.IsDelete
            $global:sqlData += $dnsData
        }
    }
}
function Write-SqlData
{
    param
    (
        $DnsData
    )
    Invoke-DbaQuery -SqlInstance $serviceConfig.sqlServerInstance -Database $serviceConfig.sqlDatabase -Query "DELETE FROM dbo.$($serviceConfig.sqlTable)"
    Invoke-DbaQuery -SqlInstance $serviceConfig.sqlServerInstance -Database $serviceConfig.sqlDatabase -Query "DBCC CHECKIDENT ('dbo.$($serviceConfig.sqlTable)', RESEED, 0)"
    foreach ($record in $DnsData)
    {
        Invoke-DbaQuery -SqlInstance $serviceConfig.sqlServerInstance -Database $serviceConfig.sqlDatabase -Query "INSERT INTO dbo.$($serviceConfig.sqlTable) (Hostname,Discovered,IPAddress,RecordType) VALUES ('$($record.Hostname)','$($record.Discovered)','$($record.IPAddress)','$($record.RecordType)')"
        Write-Output "INSERT INTO dbo.$($serviceConfig.sqlTable) (Hostname,Discovered,IPAddress,RecordType) VALUES ('$($record.Hostname)','$($record.Discovered)','$($record.IPAddress)','$($record.RecordType)')"
    }
}
function Write-NewEntryToSqlDeleted
{
    param
    (
        $hostName
    )
    Invoke-DbaQuery -SqlInstance $serviceConfig.sqlServerInstance -Database $serviceConfig.sqlDatabase -Query "INSERT INTO dbo.$($serviceConfig.sqlDeleteTable) (Hostname,Discovered) VALUES ('$hostName','$([DateTime]::UtcNow)')"
}
# === END Functions declarations
# ===== NOT IMPLEMENTED YET
# function Verify-SqlDatabaseExists()
# {
#     Write-Log -Info "Verifying that database exists"
#     $databases = Invoke-DbaQuery -Database master -ServerInstance $serviceConfig.sqlServerInstance -Query "SELECT name FROM master.sys.databases" | Select-Object -ExpandProperty name
#     if ($databases -notcontains $serviceConfig.sqlDatabase)
#     {
#         Write-Log -Info "Database did not exist, creating it"
#         New-DbaDatabase -SqlInstance $serviceConfig.sqlServerInstance -Name $serviceConfig.sqlDatabase
#         Write-Log -Info "Database was created!nCreating table"
#     }
# }
# ===== END NOT IMPLEMENTED YET

# This is where the script 'in reality' starts......

Write-Log -Info "Script is starting..."

# Check that the DnsServer module is present, else exit
Write-Log -Info "Making sure DnsServer module is found"
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
    Write-Log -Info "DnsServer module was imported successfully"
}
catch
{
    Write-Log -Info "Failed to Import-Module DnsServer, Exception: $($_.Exception.Message)"
    Read-Host
    exit
}
if (!(Get-Module -Name "dbatools") -and $serviceConfig.OutPutType -eq "SQL")
{
    Write-Log -Info "dbatools module was not found! Check out: https://dbatools.io/" -IsError
    Read-Host
    exit
}
if ($serviceConfig.OutPutType -eq "SQL")
{
    Write-Log -Info "Loading dbatools module..."
    try
    {
        Import-Module "dbatools"
        Write-Log -Info "dbatools module was imported successfully"
    }
    catch
    {
        Write-Log -Info "Failed to Import-Module dbatools, Exception: $($_.Exception.Message)"
        Read-Host
        exit
    }
}

# Start enumerating all dns zones from config
Write-Log -Info "Starting to enumerate DNS zones"
foreach ($zone in $serviceConfig.DnsZones)
{
    Write-Log -Info "Getting all DNS records for zone $zone"
    #$records = Get-DnsServerResourceRecord -ZoneName $zone | Select-Object Hostname,RecordType -ExpandProperty RecordData
    $records = @()
    Get-DnsServerResourceRecord -ZoneName $zone |Where-Object{$_.RecordType -ne "SRV"} | ForEach-Object{
        $records += Construct-DnsDataClassInstance -DnsData $_
    }
    Write-Log -Info "Number of records returned from server was: $($records.Count)"
    switch ($serviceConfig.OutPutType)
    {
        "CSV"
        {
            Write-Log -Info "Selected output mode is CSV"
            Verify-CsvOutput -DnsData $records # Make sure the file is created 
            Get-CsvData
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
            # Write output
            Write-Log -Info "Writing output to file"
            Write-CsvOutput -DnsData $csvData
            Write-Log -Info "Writing data to file has completed!"

            # Check if any DNS records have been removed
            Write-Log -Info "Checking if any records have been deleted"
            $uniqueFromCsv = $csvData | Select-Object Hostname -Unique -ExpandProperty Hostname
            $uniqueFromServer = $records | Select-Object Hostname -Unique -ExpandProperty Hostname
            $diff = Compare-Object -ReferenceObject $uniqueFromCsv -DifferenceObject $uniqueFromServer | Where-Object{$_.SideIndicator -eq "<="}
            foreach ($removedEntry in $diff)
            {
                Write-Log -Info "[ENTRY_REMOVED] $($removedEntry.InputObject)"
                "$($removedEntry.InputObject);$([DateTime]::UtcNow)" | Out-File $serviceConfig.csvRemovedFilePath -Encoding utf8 -Append
            }
        }
        "SQL"
        {
            Write-Log -Info "Selected output mode is SQL"
            Get-SQLData
            foreach ($record in $records)
            {
                # We dont want to itterate records without IP addresses or the default @ address
                if ([string]::IsNullOrEmpty($record.IPAddress) -or $record.Hostname -eq "@")
                {
                    continue
                }
                # Check how many matches on hostname we have in the data
                $matchesInSqlData = $sqlData | Where-Object{$_.Hostname -eq $record.Hostname}
                if ($matchesInSqlData.Count -le 0)
                {
                    # No matches was found so we add this new record to the data
                    Write-Log -Info "New record was found!"
                    $record.Discovered = [DateTime]::UtcNow
                    $sqlData += $record
                    continue
                }
                elseif ($matchesInSqlData.Count -eq 1)
                {
                    # If only one match was found we can compare the IP address directly
                    if ($matchesInSqlData.IPAddress -ne $record.IPAddress)
                    {
                        # The IP address was not equal, adding new row
                        Write-Log -Info "Record with modified IP address was found"
                        $record.Discovered = [DateTime]::UtcNow
                        $sqlData += $record
                        continue
                    }
                }
                else
                {
                    # Multiple matches was found on the hostname, check if any of them has this IPAddress
                    if ($matchesInSqlData.IPAddress -notcontains $record.IPAddress)
                    {
                        # None of them had this IPAddress, add as new row
                        Write-Log -Info "Record with hostname $($record.Hostname) already in source was found but not with this IP address $($record.IPAddress)"
                        $record.Discovered = [DateTime]::UtcNow
                        $sqlData += $record
                        continue
                    }
                }
            }
            # Write data to SQL
            Write-Log -Info "Writing data to SQL"
            Write-SqlData -DnsData $sqlData
            Write-Log -Info "Writing data to SQL has completed!"

            # Check if any DNS records have been removed
            Write-Log -Info "Checking if any records have been deleted"
            $uniqueFromSql = $sqlData | Select-Object Hostname -Unique -ExpandProperty Hostname
            $uniqueFromServer = $records | Select-Object Hostname -Unique -ExpandProperty Hostname
            $diff = Compare-Object -ReferenceObject $uniqueFromSql -DifferenceObject $uniqueFromServer | Where-Object{$_.SideIndicator -eq "<="}
            foreach ($removedEntry in $diff)
            {
                Write-Log -Info "[ENTRY_REMOVED] $($removedEntry.InputObject)"
                Write-NewEntryToSqlDeleted -hostName $removedEntry.InputObject
            }
        }
    }
}

