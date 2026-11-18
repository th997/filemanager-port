param(
    [string]$ExePath = "",
    [switch]$Unregister
)

$ErrorActionPreference = "Stop"

$SupportedExtensions = @(
    ".zip", ".apk", ".apkm", ".apks", ".obb", ".cbz", ".jar", ".tar", ".tgz", ".gz", ".7z", ".epub", ".txt", ".md", ".markdown", ".json", ".jsonc", ".json5", ".geojson", ".topojson", ".map", ".lock", ".yaml", ".yml", ".xml", ".plist", ".svg", ".rs", ".dart", ".c", ".cpp", ".cc", ".h", ".hpp", ".py", ".js", ".mjs", ".jsx", ".ts", ".tsx", ".html", ".htm", ".xhtml", ".css", ".toml", ".sh", ".bash", ".zsh", ".log", ".ini", ".cfg", ".csv", ".java", ".kt", ".go", ".swift", ".sql", ".properties", ".diff", ".patch", ".conf", ".gradle", ".dockerfile", ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".heic", ".heif", ".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv", ".3gp", ".m4v", ".wmv", ".rmvb", ".rm", ".vob", ".ogv", ".m2ts", ".mts", ".f4v", ".asf", ".divx", ".mpg", ".mpeg", ".mp3", ".flac", ".wav", ".ogg", ".m4a", ".aac", ".opus", ".wma", ".amr", ".ape", ".alac", ".aiff", ".mka", ".oga", ".wv", ".mid"
)

if ($Unregister) {
    Remove-Item -Path "HKCU:\Software\Classes\FPFileManager.Document" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Classes\Applications\filemanager.exe" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Classes\Directory\shell\FPFileManager" -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($ext in $SupportedExtensions) {
        $progIdPath = "HKCU:\Software\Classes\$ext\OpenWithProgids"
        if (Test-Path $progIdPath) {
            Remove-ItemProperty -Path $progIdPath -Name "FPFileManager.Document" -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Unregistered FP File Manager Open With associations."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $AppDir = Split-Path -Parent $ScriptDir
    $Candidate = Join-Path $AppDir "build\windows\x64\runner\Release\filemanager.exe"
    if (Test-Path $Candidate) {
        $ExePath = (Resolve-Path $Candidate).Path
    } else {
        throw "filemanager.exe not found. Pass -ExePath 'C:\path\to\filemanager.exe' or build Windows release first."
    }
} else {
    $ExePath = (Resolve-Path $ExePath).Path
}

$OpenCommand = "`"$ExePath`" `"%1`""
$IconSpec = "`"$ExePath`",0"

New-Item -Path "HKCU:\Software\Classes\FPFileManager.Document\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\FPFileManager.Document" -Name "(Default)" -Value "FP File Manager Document"
Set-ItemProperty -Path "HKCU:\Software\Classes\FPFileManager.Document\DefaultIcon" -Name "(Default)" -Value $IconSpec

New-Item -Path "HKCU:\Software\Classes\FPFileManager.Document\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\FPFileManager.Document\shell\open\command" -Name "(Default)" -Value $OpenCommand

New-Item -Path "HKCU:\Software\Classes\Applications\filemanager.exe\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\Applications\filemanager.exe" -Name "FriendlyAppName" -Value "FP File Manager"
Set-ItemProperty -Path "HKCU:\Software\Classes\Applications\filemanager.exe\DefaultIcon" -Name "(Default)" -Value $IconSpec

New-Item -Path "HKCU:\Software\Classes\Applications\filemanager.exe\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\Applications\filemanager.exe\shell\open\command" -Name "(Default)" -Value $OpenCommand

$SupportedTypesKey = "HKCU:\Software\Classes\Applications\filemanager.exe\SupportedTypes"
New-Item -Path $SupportedTypesKey -Force | Out-Null

foreach ($ext in $SupportedExtensions) {
    Set-ItemProperty -Path $SupportedTypesKey -Name $ext -Value ""
    $progIdPath = "HKCU:\Software\Classes\$ext\OpenWithProgids"
    New-Item -Path $progIdPath -Force | Out-Null
    $progIdKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\$ext\OpenWithProgids", $true)
    $progIdKey.SetValue("FPFileManager.Document", [byte[]]@(), [Microsoft.Win32.RegistryValueKind]::None)
    $progIdKey.Close()
}

New-Item -Path "HKCU:\Software\Classes\Directory\shell\FPFileManager\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\Directory\shell\FPFileManager" -Name "(Default)" -Value "Open with FP File Manager"
Set-ItemProperty -Path "HKCU:\Software\Classes\Directory\shell\FPFileManager" -Name "Icon" -Value $IconSpec
Set-ItemProperty -Path "HKCU:\Software\Classes\Directory\shell\FPFileManager\command" -Name "(Default)" -Value $OpenCommand

$registeredKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\FPFileManager.Document", $true)
$registeredKey.SetValue("RegisteredExecutable", $ExePath)
$registeredKey.Close()

Write-Host "Registered FP File Manager in Windows Open With for $($SupportedExtensions.Count) extensions and directories."
