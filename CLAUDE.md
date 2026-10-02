# backup-etech

Backup automático das instalações do sistema TSD (Host/Frente, Firebird 2.5) nos clientes da E-Tech.
Quem executa é o aplicativo de backup **MasterRemote**: ele roda um BAT ("BAT antes do backup") e depois
faz upload dos arquivos de "Arquivos e pastas" (`C:\E-Tech\Backups\upload\*.zip`).

## Arquivos

- `campo-bat-antes.bat`: conteúdo colado no campo "BAT antes do backup" do MasterRemote. Baixa o
  `backup-etech.bat` do GitHub (raw) para `C:\E-Tech\backup-etech.bat` e o executa com `call`. Se o download
  falhar, usa a cópia local. Só troca a cópia local se o arquivo baixado contiver `:PS_INICIO`.
- `backup-etech.bat`: o script real. Topo em batch puro e, depois do rótulo `:PS_INICIO`, PowerShell. O batch
  lê o próprio arquivo, pega o texto depois do marcador e roda com `Invoke-Expression`.
- `.gitattributes`: `*.bat -text`, para o raw do GitHub servir com CRLF.

## Restrições que já custaram tempo (não regredir)

- **O campo do MasterRemote salva só ~1.535 caracteres.** O excedente é descartado e o app acrescenta `cls` e
  `Exit` ao final. O editor mostra o texto inteiro, mas não grava. Por isso o campo contém só o bootstrap, que
  precisa continuar bem abaixo desse limite (hoje tem 542 caracteres).
- **Execução pelo MasterRemote:** como SYSTEM (`USERNAME` = `MAQUINA$`), a partir de um .bat temporário em
  `C:\Program Files (x86)\MasterRemote\<numero>.bat`. O app pode apagar esse arquivo durante a execução, e aí
  o código de saída final pode vir 1 mesmo com sucesso. O log é a fonte de verdade.
- **Windows Defender** bloqueia (`Acesso negado`, exit 5) a chamada do PowerShell com parâmetros abreviados
  (`-NoP -EP Bypass -C ... iex`). Sempre usar a forma longa:
  `-NoProfile -ExecutionPolicy Bypass -Command ... Invoke-Expression`.
- **Nada pode vir antes do batch que dependa da 1ª linha.** O truque híbrido `<# : ... #>` foi abandonado
  porque quebra quando entra qualquer coisa antes da primeira linha (`@echo off`, BOM).
- **Arquivos .bat em ASCII puro** (sem acentos, sem BOM), com CRLF.
- **gbak: só versão 2.5.x** (filtrado por `FileVersion`), com `fbclient.dll` na mesma pasta. Um `.fbk` gerado
  pelo gbak 3+ não restaura no 2.5. Ordem de procura: serviço Firebird rodando > pasta da instalação >
  registro > Program Files. Se um gbak falhar, tenta o próximo.
- **Porta sempre explícita** (`localhost/<PORTA>:<fdb>`), lida do `PORTA=` da seção `[CONEXAO]` do
  `Conexao.ini` (padrão 3050). Sem porta, o cliente usa o `gds_db` do arquivo `services`, que pode apontar para
  outro Firebird (ex.: 3.0 na mesma máquina) e dá "connection rejected by remote interface".
- **`Conexao.ini`:** ler só a seção `[CONEXAO]` (`IP_SERVIDOR`, `PORTA`, `RETAGUARDA`). Existe um `Porta=COM1`
  em `[BALANCA]`.

## Comportamento definido com o usuário

- **Detecção:** pastas com `Conexao.ini` em `X:\TSD` e `X:\TSD\*`, em todos os discos fixos. `C:\TSD-FIXO`
  existe só na máquina de desenvolvimento; nos clientes é sempre `TSD`.
- **IP_SERVIDOR local** (127.0.0.1/localhost/nome/IPs da máquina/vazio): faz o gbak. Se for de **outra máquina**
  (terminal), pula o banco e salva só os arquivos.
- **Banco já feito:** se duas instalações apontam para o mesmo `RETAGUARDA`, o gbak roda uma vez só.
- **Conteúdo do zip:** `.fbk`, `*.ini`, `Report\*.fr3`, `Certificado\*.pfx`, `Logo\`, todas as pastas `XML*`
  e `LEIA-ME_backup.txt`.
- **Upload e histórico:** 1 zip por instalação em `C:\E-Tech\Backups\upload\` (só o mais recente). No início
  de cada execução, os anteriores vão para `historico\`, que é limpo após `RETENCAO_DIAS` (7).
- **Logs:**
  - `C:\E-Tech\Backups\backup_log.txt`: detalhado, gerado pelo PowerShell.
  - `C:\E-Tech\Backups\bat_execucao.txt`: rastro do batch, gravado mesmo se o PowerShell falhar.
- **Códigos de saída:** 0 ok, 1 falha, 2 nenhuma instalação, 3 já em execução, 9 erro no PowerShell,
  8 (bootstrap) script não disponível.

## Como testar (máquina de dev)

- Ambiente: Firebird 2.5 na 3050 e 3.0 na 3060. Instalações `C:\TSD\Host` e `C:\TSD\Host2`; o `Conexao.ini`
  da Host2 aponta para o banco da Host, o que testa o banco já feito.
- **Não testar com destino real à toa:** fazer uma cópia do .bat trocando `set "DESTINO=..."` por uma pasta
  temporária.
- **Simular o MasterRemote:**
  - gravar o .bat com `@echo off` antes, em UTF-8 com BOM, com `cls`/`Exit` no fim;
  - rodar a partir de uma pasta com espaço no nome;
  - apagar o .bat ~1s depois de iniciar.
- **Bootstrap:** dá para testar sem GitHub usando
  `URL=file:///C:/Baraujo-Soft/backup-etech/backup-etech.bat` (o `curl.exe` aceita `file://`).
- **Conferir o `.fbk`:** restaurar com `gbak -c ... 127.0.0.1/3050:<pasta>\teste.fdb`.

## Pendências

- Colocar no `campo-bat-antes.bat` a URL raw do GitHub (`set "URL=..."`); hoje está `SEU-LINK-AQUI`.
- Ainda não foi validado de ponta a ponta no MasterRemote real com o bootstrap.
