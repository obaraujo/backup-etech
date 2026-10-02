@echo off
set "URL=https://raw.githubusercontent.com/obaraujo/backup-etech/main/backup-etech.bat"
set "S=C:\E-Tech\Suporte\backup-etech.bat"
set "LOG=C:\E-Tech\Backups\bat_execucao.txt"
md C:\E-Tech\Suporte C:\E-Tech\Backups 2>nul
del "%S%.new" 2>nul
curl.exe -fsSL --max-time 120 -o "%S%.new" "%URL%" 2>nul
if not exist "%S%.new" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=3072;(New-Object Net.WebClient).DownloadFile($env:URL,$env:S+'.new')" 2>nul
set VL=0
set VN=0
if exist "%S%" for /f "tokens=2 delims==" %%a in ('findstr /b /c:":: VERSAO=" "%S%"') do set VL=%%a
if exist "%S%.new" for /f "tokens=2 delims==" %%a in ('findstr /b /c:":: VERSAO=" "%S%.new"') do set VN=%%a
if %VN% GTR %VL% (move /y "%S%.new" "%S%" >nul
>>"%LOG%" echo [%date% %time%] script atualizado v%VL% para v%VN%) else del "%S%.new" 2>nul
if not exist "%S%" exit /b 8
call "%S%"
