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
$tableName = "USB_" + [DateTime]::Now.Year + [DateTime]::Now.Month + [DateTime]::Now.Day
$sqlDataBase = "SECOPS"
$sqlServer = "SERVER"
$sendResultToDatabase = $true

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
                $keyCreation = [DateTime]::MinValue
                $usbInfoKey = $usbKey.OpenSubKey($serial)
                $PartmgrKey = $usbInfoKey.OpenSubKey("Device Parameters\\Partmgr")
                $diskId = $PartmgrKey.GetValue("DiskId")
                $keyCreation = Get-KeyCreationDate -handle $usbInfoKey.Handle -serial $serial
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
            $handle,
            $serial
        )
        $cName = New-Object System.Text.StringBuilder $serial
        $cLength = 255
        [long]$tStamp =$null
        $keyQuery = [advapi32]::RegQueryInfoKey(
            $handle,
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
function Invoke-Sqlcmd2 
{
    param(
    [Parameter(Position=0, Mandatory=$true ,ValueFromPipeline = $false)] [string]$ServerInstance,
    [Parameter(Position=1, Mandatory=$true ,ValueFromPipeline = $false)] [string]$Database,
	[Parameter(Position=2, Mandatory=$false ,ValueFromPipeline = $false)] [string]$UserName,
	[Parameter(Position=3, Mandatory=$false ,ValueFromPipeline = $false)] [string]$Password,
    [Parameter(Position=4, Mandatory=$true ,ValueFromPipeline = $false)] [string]$Query,
    [Parameter(Position=5, Mandatory=$false ,ValueFromPipeline = $false)] [Int32]$QueryTimeout=30
    )

    $conn=new-object System.Data.SqlClient.SQLConnection
	if ($UserName -and $Password)
	
   		{ $conn.ConnectionString="Server={0};Database={1};User ID={2};Pwd={3}" -f $ServerInstance,$Database,$UserName,$Password }
	else
	    { $conn.ConnectionString="Server={0};Database={1};Integrated Security=True" -f $ServerInstance,$Database  }

    $conn.Open()
    $cmd=new-object system.Data.SqlClient.SqlCommand($Query,$conn)
    $cmd.CommandTimeout=$QueryTimeout
    $ds=New-Object system.Data.DataSet
    $da=New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
    [void]$da.fill($ds)
    $conn.Close()
    $ds.Tables[0]

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
            "Host;LastUsed;Serial;DiskIdPartmgr;FriendlyName;Driver;HardwareId" | Out-File ($outputDir + "\usbresult.txt")
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
        #Write-Info "Found $($system.Properties["name"]) in AD"
        $global:systems += $system.Properties["name"]
        
    }
}
function Write-ToDb
{
    param
    (
        $csvImport
    )
    $createTableQuery = @"
CREATE TABLE [dbo].[$tableName](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Host] [varchar](500) NOT NULL,
	[LastUsed] [datetime] NULL,
	[Serial] [varchar](5000) NULL,
	[DiskId] [varchar](5000) NULL,
	[FriendlyName] [varchar](5000) NULL,
    [Driver] [varchar](5000) NULL,
	[HardwareId] [varchar](5000) NULL,
 CONSTRAINT [PK_USB_2018-07-06] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
"@
    Invoke-Sqlcmd2 -ServerInstance $sqlServer -Database $sqlDataBase -Query $createTableQuery
    foreach ($row in $csvImport)
    {
        $insertQuery = @"
INSERT INTO [dbo].[$tableName]
           ([Host]
           ,[LastUsed]
           ,[Serial]
           ,[DiskId]
           ,[FriendlyName]
           ,[Driver]
           ,[HardwareId])
     VALUES
           ('$($row.Host)','$($row.LastUsed)','$($row.Serial)','$($row.DiskIdPartmgr)','$($row.FriendlyName.Replace("'",""))','$($row.Driver)','$($row.HardwareId.Replace("'",""))')
"@
    Invoke-Sqlcmd2 -ServerInstance $sqlServer -Database $sqlDataBase -Query $insertQuery
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
#if ((Read-Host -Prompt "Start scan? (y/n)") -ne "y")
#{
#    Write-Info "User aborted"
#    exit
#}

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
Start-Sleep -Seconds 60
if ($sendResultToDatabase)
{
    Write-Info "Sleeping before sending result to database"
    Write-ToDb -csvImport (Import-Csv  ($outputDir + "\usbresult.txt") -Delimiter ";")
}