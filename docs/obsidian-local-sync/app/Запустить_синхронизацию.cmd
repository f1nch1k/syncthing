@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command "try { & '%~dp0Start-ObsidianSync.ps1' } catch { Write-Host $_ -ForegroundColor Red; Read-Host 'Press Enter to close' }"
