Clear-Host

$signature = @'
[DllImport("kernel32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetVolumePathNamesForVolumeNameW([MarshalAs(UnmanagedType.LPWStr)] string lpszVolumeName,
        [MarshalAs(UnmanagedType.LPWStr)] [Out] StringBuilder lpszVolumeNamePaths, uint cchBuferLength, 
        ref UInt32 lpcchReturnLength);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr FindFirstVolume([Out] StringBuilder lpszVolumeName,
   uint cchBufferLength);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool FindNextVolume(IntPtr hFindVolume, [Out] StringBuilder lpszVolumeName, uint cchBufferLength);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint QueryDosDevice(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);
'@;

Add-Type -MemberDefinition $signature -Name Win32Utils -Namespace PInvoke -Using PInvoke,System.Text;

[UInt32] $lpcchReturnLength = 0
[UInt32] $Max = 65535
$sbVolumeName = New-Object System.Text.StringBuilder($Max, $Max)
$sbPathName = New-Object System.Text.StringBuilder($Max, $Max)
$sbMountPoint = New-Object System.Text.StringBuilder($Max, $Max)
$deviceMapping = @{ }
[IntPtr] $volumeHandle = [PInvoke.Win32Utils]::FindFirstVolume($sbVolumeName, $Max)

do {
    $volume = $sbVolumeName.toString()
    $unused = [PInvoke.Win32Utils]::GetVolumePathNamesForVolumeNameW($volume, $sbMountPoint, $Max, [Ref] $lpcchReturnLength)
    $ReturnLength = [PInvoke.Win32Utils]::QueryDosDevice($volume.Substring(4, $volume.Length - 1 - 4), $sbPathName, [UInt32] $Max)
    
    if ($ReturnLength) {
        $DriveMapping = @{
            DriveLetter = $sbMountPoint.toString()
            VolumeName = $volume
            DevicePath = $sbPathName.ToString()
        }
        $deviceMapping[$DriveMapping.DevicePath] = $DriveMapping.DriveLetter
    }
} while ([PInvoke.Win32Utils]::FindNextVolume([IntPtr] $volumeHandle, $sbVolumeName, $Max))

$xxstringsUrl = "https://github.com/ZaikoARG/xxstrings/releases/download/1.0.0/xxstrings64.exe"

$xxstringsPath = "$env:TEMP\xxstrings64.exe"

Invoke-WebRequest -Uri $xxstringsUrl -OutFile $xxstringsPath

$pidDPS = (Get-CimInstance -ClassName Win32_Service | Where-Object { $_.Name -eq 'DPS' }).ProcessId
$regexDPS = "!!.*\.exe"

$xxstringsOutput = & $xxstringsPath -p $pidDPS -raw | findstr /R $regexDPS

if ($xxstringsOutput) {
    Write-Host "Replaces strings found in DPS:`n" -ForegroundColor Magenta

    $fileHashes = @{ }

    $xxstringsOutput | ForEach-Object {
        if ($_ -match '!!([^!]+\.exe)!([^!]+)!([^!]+)') {
            $exeName = $matches[1]
            $date = $matches[2]
            $hash = $matches[3]

            if ($fileHashes.ContainsKey($exeName)) {
                if (-not ($fileHashes[$exeName] | Where-Object { $_.Date -eq $date -and $_.Hash -eq $hash })) {
                    $fileHashes[$exeName] += [PSCustomObject]@{ Date = $date; Hash = $hash }
                }
            } else {
                $fileHashes[$exeName] = @([PSCustomObject]@{ Date = $date; Hash = $hash })
            }
        }
    }

    $fileHashes.GetEnumerator() | ForEach-Object {
        $exeName = $_.Key
        $entries = $_.Value

        $groupedEntries = $entries | Group-Object -Property Date

        if ($groupedEntries.Count -gt 1) {
            Write-Host "Replace in ${exeName}:`n" -ForegroundColor DarkYellow

            $entries | ForEach-Object {
                Write-Host "$exeName!$($_.Date)!$($_.Hash)!" 
            }

            $xxstringsRelatedOutput = & $xxstringsPath -p $pidDPS -raw | findstr /R "$exeName"

            if ($xxstringsRelatedOutput) {
                Write-Host "`nPaths where the following were executed:`n" -ForegroundColor DarkGray
                $uniqueResults = $xxstringsRelatedOutput | Sort-Object -Unique
                $uniqueResults | ForEach-Object {
                    $originalPath = $_
                    
                    foreach ($device in $deviceMapping.Keys) {
                        if ($originalPath -like "*$device*") {
                            $escapedDevice = [regex]::Escape($device)
                            $newPath = $originalPath -replace $escapedDevice, "$($deviceMapping[$device])"
                            $newPath = $newPath -replace '\\+', '\'

                            if ($newPath -like "*.exe") {
                            Write-Host "$newPath"
                            }
                            break
                        }
                    }

                    if (-not $newPath) {
                        Write-Host "$originalPath"
                    }
                }
            } else {
                Write-Host "Directories could not be found..." -ForegroundColor DarkRed
            }
            Write-Host "`n"
        }
    }
} else {
    Write-Host "No replaces found in DPS process memory." -ForegroundColor Red
}

## https://github.com/spokwn/Replaceparser/
Write-Output “You can use spokwn ReplaceParser tool and make sure.”
