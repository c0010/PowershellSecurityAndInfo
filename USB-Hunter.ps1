# --- USB Hunter
function Write-Info
{
    param
    (
        $info
    )
    Write-Host "[INFO]-[$(Get-Date)] --- $info" -ForegroundColor Cyan
}
function Write-Found
{
    param
    (
        $info
    )
    Write-Host "[FOUND]-[$(Get-Date)] --- $info" -ForegroundColor Yellow
}
function Get-USBSTOR
{
    param
    (
        $hostname
    )
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$hostname)
    $usbStorKey = $reg.OpenSubKey("SYSTEM\\CurrentControlSet\\Enum\\USBSTOR")
    foreach ($key in $usbStorKey.GetSubKeyNames())
    {
        $usbKey = $usbStorKey.OpenSubKey($key)
        $usbSerials = $usbKey.GetSubKeyNames()
        foreach ($serial in $usbSerials)
        {
            Write-Found "USBSTOR $serial"
            $usbInfoKey = $usbKey.OpenSubKey($serial)
            Write-OutputFile -content ($serial + ";" + $usbInfoKey.GetValue("FriendlyName") + ";" + $usbInfoKey.GetValue("Driver") + ";" + $usbInfoKey.GetValue("HardwareId"))
        }
    }
}
function Write-OutputFile
{
    param 
    (
        [switch]$initial,
        $content
    )
    if ($initial)
    {
        "Serial;FriendlyName;Driver;HardwareId" | Out-File $outputFile
    }
    if ([string]::IsNullOrEmpty($content))
    {
        return
    }
    Write-Host $content
    $content | Out-File $outputFile -Append
}
function Write-ScriptError
{
    param
    (
        $info
    )
    Write-Host "[ERROR]-[$(Get-Date)] --- $info" -ForegroundColor Red
}

$mode = Read-Host -Prompt "Choose Mode:`n1: USB Storage devices`n2: USB Devices ALL`n"
if ($mode -ne "1" -and $mode -ne "2")
{
    Write-Error "Invalid choice of mode!"
    exit
}
$systemChoiceMode = Read-Host -Prompt "Choose device(s):`n1: Local system`n2: Query Active directory`n3: Enter name of system(s) (comma separated)"
$systems = @()
switch ($systemChoiceMode)
{
    1
    {
        Write-Info "Local system choosen"
        $systems += $env:COMPUTERNAME
    }
    2
    {
        Write-Info "Active directory query mode choosen"
        $queryFilter = Read-Host -Prompt "Enter LDAP search filter: "
    }
    3
    {
        Write-Info "Enter name of system(s) mode choosen"
        $systems = (Read-Host -Prompt "Enter name of system(s), comma separated if multiple").Trim().Split(',')
    }
}
$outputFile = Read-Host -Prompt "Path to result file: "
if ((Read-Host -Prompt "Start scan? (y/n)") -ne "y")
{
    Write-Info "User aborted"
    exit
}

Write-OutputFile -content ([string]::Empty) -initial
foreach ($system in $systems)
{
    if (Test-Connection $system -Count 1)
    {
       Get-USBSTOR -hostname $system 
    }
    else
    {
        Write-ScriptError "$system dit not respond to network connection"
    }
}