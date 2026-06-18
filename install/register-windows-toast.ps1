# Register PluribusAI for WinRT toasts (AUMID + protocol handler). Run once at install.
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
$aumid = 'PluribusAI.TeamInbox'
$openPs1 = Join-Path $dir 'protocol-open.ps1'

# AppUserModelID (required for unpackaged WinRT toasts)
New-Item -Path "HKCU:\Software\Classes\AppUserModelId\$aumid" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\AppUserModelId\$aumid" -Name 'DisplayName' -Value 'PluribusAI'

New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\$aumid" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\$aumid" -Name 'ShowInActionCenter' -Value 1 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\$aumid" -Name 'Enabled' -Value 1 -Type DWord

# pluribusai://open?... protocol for toast click activation
New-Item -Path 'HKCU:\Software\Classes\pluribusai' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Classes\pluribusai' -Name '(default)' -Value 'URL:PluribusAI Protocol'
Set-ItemProperty -Path 'HKCU:\Software\Classes\pluribusai' -Name 'URL Protocol' -Value ''
New-Item -Path 'HKCU:\Software\Classes\pluribusai\shell\open\command' -Force | Out-Null
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$openPs1`" `"%1`""
Set-ItemProperty -Path 'HKCU:\Software\Classes\pluribusai\shell\open\command' -Name '(default)' -Value $cmd

Write-Output "Registered WinRT toasts: $aumid"