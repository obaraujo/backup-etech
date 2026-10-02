@echo off
setlocal
:: =====================================================================
::  BACKUP AUTOMATICO E-TECH - parte BAT (so chama o PowerShell abaixo)
::  Executado pelo campo "BAT antes do backup" (campo-bat-antes.bat),
::  que baixa este arquivo para C:\E-Tech\backup-etech.bat
:: =====================================================================
set "DESTINO=C:\E-Tech\Backups"
set "SCRIPT=%~f0"
if not exist "%DESTINO%" mkdir "%DESTINO%"

>> "%DESTINO%\bat_execucao.txt" echo [%date% %time%] BAT iniciado - usuario %USERNAME% - arquivo "%SCRIPT%"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "try { $c=[IO.File]::ReadAllText($env:SCRIPT); $i=$c.IndexOf(':PS'+'_INICIO'); if ($i -lt 0) { throw 'marcador PS_INICIO nao encontrado' }; $i=$c.IndexOf([char]10,$i)+1; Invoke-Expression $c.Substring($i) } catch { Add-Content -Path ($env:DESTINO+'\bat_execucao.txt') -Value ('ERRO PowerShell: '+$_); exit 9 }"
set RC=%ERRORLEVEL%
>> "%DESTINO%\bat_execucao.txt" echo [%date% %time%] BAT finalizado - codigo %RC%
exit /b %RC%

:PS_INICIO
# =====================================================================
#  BACKUP AUTOMATICO E-TECH  -  Host / Frente (Firebird 2.5)
#
#  - Detecta as instalacoes (pastas com Conexao.ini) em X:\TSD e X:\TSD\*
#  - Banco: gbak 2.5 via servidor local (seguro com o sistema aberto).
#    Terminais (IP_SERVIDOR de outra maquina) nao fazem backup do banco.
#  - Arquivos: *.ini, Report\*.fr3, Certificado\*.pfx, Logo\, pastas XML*
#  - Gera 1 zip por instalacao em <DESTINO>\upload (so o mais recente).
#    Os anteriores vao para <DESTINO>\historico e sao apagados apos
#    RETENCAO_DIAS.
#
#  No aplicativo de backup, em "Arquivos e pastas":  <DESTINO>\upload\*.zip
#  Codigo de saida: 0 = ok | 1 = houve falha | 2 = nada encontrado | 3 = ja em execucao | 9 = erro no PowerShell
#  Rastro de execucao (mesmo se o PowerShell falhar): <DESTINO>\bat_execucao.txt
# =====================================================================

# ------------------------------ CONFIG -------------------------------
$DESTINO       = $env:DESTINO            # definido no topo do BAT
if (-not $DESTINO) { $DESTINO = 'C:\E-Tech\Backups' }
$RETENCAO_DIAS = 7
$FB_USER       = 'SYSDBA'
$FB_PASS       = 'masterkey'
$INCLUIR_XML   = $true
$PASTAS_FIXAS  = @()     # opcional, ex.: @('D:\Sistema\Host') - desliga a deteccao automatica
# ---------------------------------------------------------------------

$ErrorActionPreference = 'Continue'
$dataHora  = Get-Date -Format 'yyyyMMdd_HHmmss'
$dirUpload = Join-Path $DESTINO 'upload'
$dirHist   = Join-Path $DESTINO 'historico'
$dirTemp   = Join-Path $DESTINO 'temp'
$logFile   = Join-Path $DESTINO 'backup_log.txt'

foreach ($d in $DESTINO, $dirUpload, $dirHist, $dirTemp) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 5MB) {
    Move-Item $logFile "$logFile.old" -Force
}

function Log($msg) {
    $linha = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $linha
    Add-Content -Path $logFile -Value $linha
}

# impede duas execucoes simultaneas
try {
    $lock = [IO.File]::Open((Join-Path $DESTINO 'backup.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    Log 'Outro backup ja esta em execucao. Abortando.'
    exit 3
}

# ----------------------------- FUNCOES -------------------------------

function Get-Instalacoes {
    if ($PASTAS_FIXAS.Count -gt 0) {
        $cand = $PASTAS_FIXAS
    } else {
        $cand = @()
        foreach ($drv in [IO.DriveInfo]::GetDrives()) {
            if ($drv.DriveType -ne 'Fixed' -or -not $drv.IsReady) { continue }
            foreach ($nome in @('TSD')) {
                $raiz = Join-Path $drv.RootDirectory.FullName $nome
                if (-not (Test-Path $raiz)) { continue }
                $cand += $raiz
                $cand += Get-ChildItem $raiz -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSIsContainer } | ForEach-Object { $_.FullName }
            }
        }
    }
    $cand | Where-Object { Test-Path (Join-Path $_ 'Conexao.ini') } | Sort-Object -Unique
}

function Read-Conexao($ini) {
    $cfg = @{}
    $secao = ''
    foreach ($l in [IO.File]::ReadAllLines($ini, [Text.Encoding]::Default)) {
        $t = $l.Trim()
        if ($t -match '^\[(.+)\]$') { $secao = $matches[1].Trim().ToUpper(); continue }
        if ($secao -eq 'CONEXAO' -and $t -match '^([^=]+)=(.*)$') {
            $cfg[$matches[1].Trim().ToUpper()] = $matches[2].Trim()
        }
    }
    $cfg
}

function Get-VersaoArquivo($p) {
    try { "$((Get-Item $p).VersionInfo.FileVersion)" } catch { '' }
}

# Lista os gbak.exe 2.5 disponiveis (com fbclient.dll ao lado), por prioridade:
# servico Firebird rodando > pasta da instalacao > registro > Program Files
function Get-GbakCandidatos($pastaInst) {
    $lista = @()
    $svcs = Get-WmiObject Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -match '(fbserver|fb_inet_server|fbguard|firebird)\.exe' } |
        Sort-Object { $_.State -ne 'Running' }
    foreach ($s in $svcs) {
        if ($s.PathName -match '^"?(.+?\\)[^\\]+\.exe') { $lista += $matches[1] + 'gbak.exe' }
    }
    $lista += Join-Path $pastaInst 'gbak.exe'
    foreach ($k in 'HKLM:\SOFTWARE\Firebird Project\Firebird Server\Instances',
                   'HKLM:\SOFTWARE\WOW6432Node\Firebird Project\Firebird Server\Instances') {
        $r = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($r -and $r.DefaultInstance) { $lista += Join-Path $r.DefaultInstance 'bin\gbak.exe' }
    }
    foreach ($pf in $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432,
                    'C:\Arquivos de Programas', 'C:\Arquivos de Programas (x86)') {
        if (-not $pf -or -not (Test-Path (Join-Path $pf 'Firebird'))) { continue }
        $lista += Get-ChildItem (Join-Path $pf 'Firebird') -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer } |
            ForEach-Object { Join-Path $_.FullName 'bin\gbak.exe'; Join-Path $_.FullName 'gbak.exe' }
    }

    $vistos = @{}
    foreach ($g in $lista) {
        if (-not $g -or -not (Test-Path $g)) { continue }
        $chave = $g.ToUpper()
        if ($vistos.ContainsKey($chave)) { continue }
        $vistos[$chave] = 1
        if ((Get-VersaoArquivo $g) -notmatch '2\.5\.') { continue }   # .fbk de gbak 3+ nao restaura no 2.5
        if (-not (Test-Path (Join-Path (Split-Path $g) 'fbclient.dll'))) { continue }
        $g
    }
}

# Tenta cada gbak ate um funcionar. Retorna o gbak usado ou $null.
function Invoke-Gbak($gbaks, $fdb, $porta, $fbk, $logGbak) {
    # porta sempre explicita: sem ela o cliente usa o 'gds_db' do arquivo services,
    # que pode apontar para outro Firebird (ex.: 3.0) instalado na maquina
    if (-not $porta) { $porta = '3050' }
    $conn = "localhost/${porta}:$fdb"
    foreach ($g in $gbaks) {
        Remove-Item $fbk, $logGbak -Force -ErrorAction SilentlyContinue
        Log "  gbak: $g"
        & $g -b -g -user $FB_USER -password $FB_PASS $conn $fbk -y $logGbak
        $rc = $LASTEXITCODE
        if ($rc -eq 0 -and (Test-Path $fbk) -and (Get-Item $fbk).Length -gt 0) { return $g }
        $erro = ''
        if (Test-Path $logGbak) { $erro = (Get-Content $logGbak | Select-Object -Last 4) -join ' | ' }
        Log "  falhou (codigo $rc): $erro"
    }
    return $null
}

function Copiar($origem, $destino, $filtro, [switch]$Recursivo) {
    if (-not (Test-Path $origem)) { return }
    $a = @($origem, $destino, $filtro, '/R:1', '/W:1', '/NP', '/NFL', '/NDL', '/NJH', '/NJS', '/XJ')
    if ($Recursivo) { $a += '/E' }
    & "$env:SystemRoot\System32\robocopy.exe" @a | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy falhou (codigo $LASTEXITCODE) em $origem" }
}

function Compactar($pasta, $zip) {
    $seteZip = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($seteZip) {
        & $seteZip a -tzip -mx=5 -bd $zip "$pasta\*" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip falhou (codigo $LASTEXITCODE)" }
        return
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($pasta, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
}

function Tamanho($bytes) { '{0:N1} MB' -f ($bytes / 1MB) }

# ------------------------------ EXECUCAO -----------------------------

Log '==================== INICIO ===================='

# o ultimo backup sai de upload\ e vai para o historico
Get-ChildItem $dirUpload -Filter *.zip -ErrorAction SilentlyContinue |
    ForEach-Object { Move-Item $_.FullName $dirHist -Force }
Get-ChildItem $dirTemp -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$insts = @(Get-Instalacoes)
if ($insts.Count -eq 0) {
    Log 'Nenhuma instalacao encontrada (pasta com Conexao.ini em X:\TSD\*).'
    $lock.Close()
    exit 2
}
Log ("Instalacoes: " + ($insts -join '; '))

$nomesLocais = @('', '127.0.0.1', 'localhost', '::1', $env:COMPUTERNAME)
try { $nomesLocais += [Net.Dns]::GetHostAddresses($env:COMPUTERNAME) | ForEach-Object { $_.IPAddressToString } } catch {}

$bancosFeitos = @{}
$falhas = 0

foreach ($inst in $insts) {
    $nome    = (($inst -replace ':', '') -replace '\\', '_').Trim('_')
    $staging = Join-Path $dirTemp $nome
    Log "--- $inst"
    try {
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        $cfg   = Read-Conexao (Join-Path $inst 'Conexao.ini')
        $ip    = "$($cfg['IP_SERVIDOR'])".Trim()
        $porta = "$($cfg['PORTA'])".Trim()
        $fdb   = "$($cfg['RETAGUARDA'])".Trim()
        if (-not $fdb) { $fdb = Join-Path $inst 'HOST.FDB' }

        $resumo = @(
            "Instalacao : $inst",
            "Computador : $env:COMPUTERNAME",
            "Data       : $dataHora",
            "IP_SERVIDOR: $ip  PORTA: $porta",
            "RETAGUARDA : $fdb"
        )

        # ----- banco -----
        if ($nomesLocais -notcontains $ip) {
            Log "  Banco em outro servidor ($ip): terminal, backup do banco ignorado."
            $resumo += 'Banco      : ignorado (terminal)'
        } elseif ($fdb.StartsWith('\\')) {
            Log "  Banco em caminho de rede ($fdb): backup do banco ignorado."
            $resumo += 'Banco      : ignorado (caminho de rede)'
        } elseif (-not (Test-Path $fdb)) {
            Log "  ERRO: banco nao encontrado: $fdb"
            $resumo += 'Banco      : NAO ENCONTRADO'
            $falhas++
        } elseif ($bancosFeitos.ContainsKey($fdb.ToUpper())) {
            Log "  Banco ja incluido no backup de $($bancosFeitos[$fdb.ToUpper()])."
            $resumo += "Banco      : incluido em backup_$($bancosFeitos[$fdb.ToUpper()])_$dataHora.zip"
        } else {
            $tamFdb = (Get-Item $fdb).Length
            $livre  = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($DESTINO))).AvailableFreeSpace
            if ($livre -lt $tamFdb * 1.5) { Log "  AVISO: pouco espaco livre ($(Tamanho $livre)) para banco de $(Tamanho $tamFdb)." }

            $gbaks = @(Get-GbakCandidatos $inst)
            $fbk   = Join-Path $staging ([IO.Path]::GetFileNameWithoutExtension($fdb) + '.fbk')
            $usado = $null
            if ($gbaks.Count -eq 0) {
                Log '  ERRO: nenhum gbak 2.5 (com fbclient.dll) encontrado na maquina.'
            } else {
                $usado = Invoke-Gbak $gbaks $fdb $porta $fbk (Join-Path $staging 'gbak.log')
            }
            if ($usado) {
                $bancosFeitos[$fdb.ToUpper()] = $nome
                Log "  OK banco: $(Tamanho $tamFdb) -> fbk $(Tamanho (Get-Item $fbk).Length)"
                $resumo += "Banco      : $([IO.Path]::GetFileName($fbk)) (gbak $(Get-VersaoArquivo $usado) - $usado)"
            } else {
                Log '  ERRO: backup do banco falhou.'
                $resumo += 'Banco      : FALHOU (ver gbak.log)'
                $falhas++
            }
        }

        # ----- arquivos -----
        Copiar $inst $staging '*.ini'
        Copiar (Join-Path $inst 'Report')      (Join-Path $staging 'Report')      '*.fr3' -Recursivo
        Copiar (Join-Path $inst 'Certificado') (Join-Path $staging 'Certificado') '*.pfx' -Recursivo
        Copiar (Join-Path $inst 'Logo')        (Join-Path $staging 'Logo')        '*.*'   -Recursivo
        if ($INCLUIR_XML) {
            Get-ChildItem $inst -Filter 'XML*' -ErrorAction SilentlyContinue |
                Where-Object { $_.PSIsContainer } |
                ForEach-Object { Copiar $_.FullName (Join-Path $staging $_.Name) '*.*' -Recursivo }
        }
        Set-Content -Path (Join-Path $staging 'LEIA-ME_backup.txt') -Value $resumo

        # ----- compacta (em temp\ e so depois move para upload\) -----
        $zipNome = "backup_${nome}_$dataHora.zip"
        $zipTemp = Join-Path $dirTemp $zipNome
        Compactar $staging $zipTemp
        Move-Item $zipTemp (Join-Path $dirUpload $zipNome) -Force
        Log "  OK zip: $zipNome ($(Tamanho (Get-Item (Join-Path $dirUpload $zipNome)).Length))"
    } catch {
        Log "  ERRO: $($_.Exception.Message)"
        $falhas++
    } finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ----- limpeza do historico -----
Get-ChildItem $dirHist -Filter *.zip -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RETENCAO_DIAS) } |
    ForEach-Object { Log "Removendo antigo: $($_.Name)"; Remove-Item $_.FullName -Force }

Log "==================== FIM (falhas: $falhas) ===================="
$lock.Close()
if ($falhas -gt 0) { exit 1 } else { exit 0 }
