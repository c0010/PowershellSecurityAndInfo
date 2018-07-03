Write-Output "██╗   ██╗███████╗██████╗     ██╗  ██╗██╗   ██╗███╗   ██╗████████╗███████╗██████╗ "
Write-Output "██║   ██║██╔════╝██╔══██╗    ██║  ██║██║   ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗"
Write-Output "██║   ██║███████╗██████╔╝    ███████║██║   ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝"
Write-Output "██║   ██║╚════██║██╔══██╗    ██╔══██║██║   ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗"
Write-Output "╚██████╔╝███████║██████╔╝    ██║  ██║╚██████╔╝██║ ╚████║   ██║   ███████╗██║  ██║"
Write-Output "╚═════╝ ╚══════╝╚═════╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝"
Write-Output "================================================================================="
Write-Host "This script will take input for systems from multiple sources and search them with Win32.Registry* and also advapi32.dll" -ForegroundColor Yellow
Write-Host "Author: Johan Lundberg"
                                                                                 
# Global config
$maxConcurrentJobs = 10         # Number of simultaneous PS jobs to run
$outputDir = "C:\temp\johan"    # Set this to [string]::Empty if you want to be asked for the path

$jobScriptBlock = {
    param
    (
        $_system,
        $outFolderPath
    )
    function Load-advapi32
    {
        $Domain = [AppDomain]::CurrentDomain
        $DynAssembly = New-Object System.Reflection.AssemblyName('RegAssembly')
        $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [System.Reflection.Emit.AssemblyBuilderAccess]::Run) # Only run in memory
        $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('RegistryTimeStampModule', $False)
        $TypeBuilder = $ModuleBuilder.DefineType('advapi32', 'Public, Class')
        $PInvokeMethod = $TypeBuilder.DefineMethod(
            'RegQueryInfoKey', #Method Name
            [Reflection.MethodAttributes] 'PrivateScope, Public, Static, HideBySig, PinvokeImpl', #Method Attributes
            [IntPtr], #Method Return Type
            [Type[]] @(
                [Microsoft.Win32.SafeHandles.SafeRegistryHandle], #Registry Handle
                [System.Text.StringBuilder], #Class Name
                [UInt32 ].MakeByRefType(),  #Class Length
                [UInt32], #Reserved
                [UInt32 ].MakeByRefType(), #Subkey Count
                [UInt32 ].MakeByRefType(), #Max Subkey Name Length
                [UInt32 ].MakeByRefType(), #Max Class Length
                [UInt32 ].MakeByRefType(), #Value Count
                [UInt32 ].MakeByRefType(), #Max Value Name Length
                [UInt32 ].MakeByRefType(), #Max Value Name Length
                [UInt32 ].MakeByRefType(), #Security Descriptor Size           
                [long].MakeByRefType() #LastWriteTime
            ) #Method Parameters
        )
        $DllImportConstructor = [Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
        $FieldArray = [Reflection.FieldInfo[]] @(       
            [Runtime.InteropServices.DllImportAttribute].GetField('EntryPoint'),
            [Runtime.InteropServices.DllImportAttribute].GetField('SetLastError')
        )
        $FieldValueArray = [Object[]] @(
            'RegQueryInfoKey', #CASE SENSITIVE!!
            $True
        )
        $SetLastErrorCustomAttribute = New-Object Reflection.Emit.CustomAttributeBuilder(
            $DllImportConstructor,
            @('advapi32.dll'),
            $FieldArray,
            $FieldValueArray
        )
        $PInvokeMethod.SetCustomAttribute($SetLastErrorCustomAttribute)
        [void]$TypeBuilder.CreateType()
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
                Write-Found "USBSTOR $serial on host $hostname"
                $usbInfoKey = $usbKey.OpenSubKey($serial)
                $PartmgrKey = $usbInfoKey.OpenSubKey("Device Parameters\\Partmgr")
                $diskId = $PartmgrKey.GetValue("DiskId")
                $keyCreation = Get-KeyCreationDate -handle $usbInfoKey.Handle
                Write-OutputFile -content ($hostname + ";" + $keyCreation + ";" + $serial + ";" + $diskId + ";" + $usbInfoKey.GetValue("FriendlyName") + ";" + $usbInfoKey.GetValue("Driver") + ";" + $usbInfoKey.GetValue("HardwareId"))
            }
        }
    }
    function Write-Found
    {
        param
        (
            $info
        )
        Write-Host "[FOUND]-[$(Get-Date)] --- $info" -ForegroundColor Yellow
        "[FOUND]-[$(Get-Date)] --- $info" | Out-File ($outFolderPath + "\foundlog.log") -Append
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
            "System;InitialDate;Serial;DiskIdPartmgr;FriendlyName;Driver;HardwareId" | Out-File $outputFile
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
        "[ERROR]-[$(Get-Date)] --- $info" | Out-File ($outFolderPath + "\RunTime.log") -Append
    }
    function Write-Info
    {
        param
        (
            $info
        )
        Write-Host "[INFO]-[$(Get-Date)] --- $info" -ForegroundColor Cyan
        "[INFO]-[$(Get-Date)] --- $info" | Out-File ($outFolderPath + "\RunTime.log") -Append
    }
    function Get-KeyCreationDate
    {
        param
        (
            $handle
        )
        $cName = New-Object System.Text.StringBuilder $usbInfoKey.Name
        $cLength = 255
        [long]$tStamp =$null
        $keyQuery = [advapi32]::RegQueryInfoKey(
            $usbInfoKey.Handle,
            $cName,
            [ref]$cLength,
            $null,
            [ref]$Null,
            [ref]$Null,
            [ref]$Null,
            [ref]$Null,
            [ref]$Null,
            [ref]$Null,
            [ref]$Null,
            [ref]$tStamp
        )
        if ($keyQuery -eq 0)
        {
            return [datetime]::FromFileTime($tStamp)
        }
        else
        {
            return [string]::Empty
        }
    }
    Load-advapi32
    $outputFile = $outFolderPath + "\usbresult.txt"
    if (Test-Connection $_system -Count 1)
    {
       Write-Info "$_system responded on the network, starting enumeration"
       Get-USBSTOR -hostname $_system 
    }
    else
    {
        Write-ScriptError "$_system dit not respond to network connection"
    }
}
function Write-Info
{
    param
    (
        $info
    )
    Write-Host "[INFO]-[$(Get-Date)] --- $info" -ForegroundColor Cyan
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
            "System;InitialDate;Serial;DiskIdPartmgrFriendlyName;Driver;HardwareId" | Out-File ($outputFile + "\usbresult.txt")
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
function Get-SystemsFromAd
{
    param
    (
        $domainController,
        $ldapFilter
    )
    $dirEntry = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$domainController"
    $dirSearcher = New-Object System.DirectoryServices.DirectorySearcher
    $dirSearcher.SearchRoot = $dirEntry
    $dirSearcher.Filter = $ldapFilter
    $dirSearcher.PageSize = 700
    $dirSearcher.PropertiesToLoad.Clear()
    $dirSearcher.PropertiesToLoad.Add("name")
    $dirSearcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
    $result = $dirSearcher.FindAll()
    foreach ($system in $result)
    {
        Write-Info "Found $($system.Properties["name"]) in AD"
        $global:systems += $system.Properties["name"]
        
    }
}

$mode = Read-Host -Prompt "Choose Mode:`n1: USB Storage devices"#`n2: USB Devices ALL`n"
if ($mode -ne "1"<# -and $mode -ne "2"#>)
{
    Write-Error "Invalid choice of mode!"
    exit
}
$systemChoiceMode = Read-Host -Prompt "Choose device(s):`n1: Local system`n2: Query Active directory`n3: Enter name of system(s) (comma separated)"
$global:systems = @()
switch ($systemChoiceMode)
{
    1
    {
        Write-Info "Local system choosen"
        $global:systems += $env:COMPUTERNAME
    }
    2
    {
        Write-Info "Active directory query mode choosen"
        $queryFilter = Read-Host -Prompt "Enter LDAP search filter: "
        $dc = Read-Host -Prompt "Enter domain controller in desired domain: "
        Get-SystemsFromAd -domainController $dc -ldapFilter $queryFilter
    }
    3
    {
        Write-Info "Enter name of system(s) mode choosen"
        $global:systems = (Read-Host -Prompt "Enter name of system(s), comma separated if multiple").Trim().Split(',')
    }
}
if ($outputDir -eq [string]::Empty)
{
    $outputDir = Read-Host -Prompt "Path to result folder: "
}
if (!(Test-Path $outputDir))
{
    try
    {
        New-Item -Path $outputDir -Name Directory
    }
    catch
    {
        Write-ScriptError "Unable to create result dir. Exception is: $($_.Exception.Message)"
        exit
    }
}
if ((Read-Host -Prompt "Start scan? (y/n)") -ne "y")
{
    Write-Info "User aborted"
    exit
}

Write-OutputFile -content ([string]::Empty) -initial
foreach ($system in $global:systems)
{
    if ((Get-Job -State Running).Count -ge $maxConcurrentJobs)
    {
        do
        {
            $jobCount = (Get-Job -State Running).Count
            Write-Info "Job limiter reached,running jobs $jobCount"
            Start-Sleep -Seconds 5
        }
        while((Get-Job -State Running).Count -ge $maxConcurrentJobs)
    }
    Write-Info "Starting job for $system"
    Start-Job -Name "Job_$system" -ScriptBlock $jobScriptBlock -ArgumentList $system,$outputDir
}