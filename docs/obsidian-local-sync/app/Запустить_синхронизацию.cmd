@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command "try { & '%~dp0Start-ObsidianSync.ps1' } catch { Write-Host $_ -ForegroundColor Red; Read-Host 'Нажмите Enter для закрытия окна' }"
