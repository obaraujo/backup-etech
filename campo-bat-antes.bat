@echo off
set "URL=https://SEU-LINK-AQUI/backup-etech.bat"
set "S=C:\E-Tech\backup-etech.bat"
md C:\E-Tech 2>nul
del "%S%.new" 2>nul
curl.exe -fsSL --max-time 120 -o "%S%.new" "%URL%" 2>nul
if not exist "%S%.new" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=3072;(New-Object Net.WebClient).DownloadFile($env:URL,$env:S+'.new')" 2>nul
findstr /c:":PS_INICIO" "%S%.new" >nul 2>&1 && move /y "%S%.new" "%S%" >nul
if not exist "%S%" exit /b 8
call "%S%"
