# backup-etech

Backup automático das instalações dos ERPs nos clientes da E-Tech:
- **TSD** (Host/Frente, Firebird 2.5)
- **Cummins** (PostgreSQL 9.2)

Cada ERP tem um ramo próprio no laço principal (`if ($erp -eq 'TSD') { ... } else { ... }`). O resto é comum
a todos: lock, upload/histórico, zip, `LEIA-ME`, logs e códigos de saída. `Get-Erp` identifica o sistema pelo
arquivo de configuração da pasta.
Quem executa é o aplicativo de backup **MasterRemote**: ele roda um BAT ("BAT antes do backup") e depois
faz upload dos arquivos de "Arquivos e pastas" (`C:\E-Tech\Backups\upload\*.zip`).

## Arquivos

- `campo-bat-antes.bat`: conteúdo colado no campo "BAT antes do backup" do MasterRemote. Baixa o
  `backup-etech.bat` do GitHub (raw) para `C:\E-Tech\Suporte\backup-etech.bat` e o executa com `call`. Só troca a cópia local quando a
  versão baixada é maior que a local (ver Versionamento). Se o download falhar, usa a cópia local.
- `backup-etech.bat`: o script real. Topo em batch puro e, depois do rótulo `:PS_INICIO`, PowerShell. O batch
  lê o próprio arquivo, pega o texto depois do marcador e roda com `Invoke-Expression`.
- `.gitattributes`: `*.bat -text`, para o raw do GitHub servir com CRLF.

## Restrições que já custaram tempo (não regredir)

- **O campo do MasterRemote salva só ~1.535 caracteres.** O excedente é descartado e o app acrescenta `cls` e
  `Exit` ao final. O editor mostra o texto inteiro, mas não grava. Por isso o campo contém só o bootstrap, que
  precisa continuar bem abaixo desse limite (hoje tem 955 caracteres).
- **Execução pelo MasterRemote:** como SYSTEM (`USERNAME` = `MAQUINA$`), a partir de um .bat temporário em
  `C:\Program Files (x86)\MasterRemote\<numero>.bat`. O app pode apagar esse arquivo durante a execução, e aí
  o código de saída final pode vir 1 mesmo com sucesso. O log é a fonte de verdade.
- **Windows Defender** bloqueia (`Acesso negado`, exit 5) a chamada do PowerShell com parâmetros abreviados
  (`-NoP -EP Bypass -C ... iex`). Sempre usar a forma longa:
  `-NoProfile -ExecutionPolicy Bypass -Command ... Invoke-Expression`.
- **Nada pode vir antes do batch que dependa da 1ª linha.** O truque híbrido `<# : ... #>` foi abandonado
  porque quebra quando entra qualquer coisa antes da primeira linha (`@echo off`, BOM).
- **Arquivos .bat em ASCII puro** (sem acentos, sem BOM), com CRLF. Não usar `sed -i` do Git Bash neles: ele
  converte CRLF para LF.
- **gbak: só versão 2.5.x** (filtrado por `FileVersion`), com `fbclient.dll` na mesma pasta. Um `.fbk` gerado
  pelo gbak 3+ não restaura no 2.5. Ordem de procura: serviço Firebird rodando > pasta da instalação >
  registro > Program Files. Se um gbak falhar, tenta o próximo.
- **Porta sempre explícita** (`localhost/<PORTA>:<fdb>`), lida do `PORTA=` da seção `[CONEXAO]` do
  `Conexao.ini` (padrão 3050). Sem porta, o cliente usa o `gds_db` do arquivo `services`, que pode apontar para
  outro Firebird (ex.: 3.0 na mesma máquina) e dá "connection rejected by remote interface".
- **`Conexao.ini`:** ler só a seção `[CONEXAO]` (`IP_SERVIDOR`, `PORTA`, `RETAGUARDA`). Existe um `Porta=COM1`
  em `[BALANCA]`.
- **Cummins: só `pg_dump` 9.2.x** (`$PG_VERSAO`, filtrado por `pg_dump --version`). Um `.backup` gerado por
  `pg_dump` mais novo não restaura com o `pg_restore` 9.2, e a máquina pode ter outro PostgreSQL (na de dev há
  o 16 na 5434). Ordem de procura: `EDCAMINHOPGDUMP` do `CONF\CONFIGURACAO.XML` > serviço PostgreSQL >
  registro (`PostgreSQL\Installations`) > Program Files.
- **Cummins: `pg_dump` sempre com `-w`** e a senha em `PGPASSWORD`. Sem `-w`, se a senha falhar, ele fica
  esperando digitação para sempre (roda como SYSTEM, sem console).
- **Cummins: terminais também têm PostgreSQL local**, com um banco `CUMMINS` vazio (instalação padrão). Por
  isso o que decide se é terminal é o `Server` do `SERVER.XML`, nunca a existência do banco local.

## Comportamento definido com o usuário

### TSD

- **Detecção:** pastas com `Conexao.ini` em `X:\TSD` e `X:\TSD\*`, em todos os discos fixos. `C:\TSD-FIXO`
  existe só na máquina de desenvolvimento; nos clientes é sempre `TSD`.
- **IP_SERVIDOR local** (127.0.0.1/localhost/nome/IPs da máquina/vazio): faz o gbak. Se for de **outra máquina**
  (terminal), pula o banco e salva só os arquivos.
- **Banco já feito:** se duas instalações apontam para o mesmo `RETAGUARDA`, o gbak roda uma vez só.
- **Conteúdo do zip:** `.fbk`, `*.ini`, `Report\*.fr3`, `Certificado\*.pfx` e `*.p12`, `Logo\`, todas as pastas `XML*`
  e `LEIA-ME_backup.txt`.
### Cummins

- **Detecção:** `X:\Cummins` com `CONF\SERVER.XML`, em todos os discos fixos. Só a raiz: as subpastas têm
  cópias antigas de `CONF` (ex.: `BKP\BD\CONF`).
- **Conexão:** primeira `ROW` do `CONF\SERVER.XML` (atributos `Server`, `Banco`, `Usuario`, `Senha`,
  `Porta`). Padrão: `localhost`, `postgres`, `5432`.
- **Server local:** faz o `pg_dump -F c` (`<Banco>.backup`). Se for de outra máquina (terminal), salva só os
  arquivos. O banco já feito usa a chave `porta + nome do banco`.
- **Conteúdo do zip:** `<Banco>.backup`, `pg_dump.log`, `*.ini`, todas as pastas `CONF*`, `Report\*.fr3`,
  `Relatorios\`, `Imagens\`, `Certificado\` e `Certificados\` (`*.pfx` e `*.p12`), `NFe\`, `NFCe\`,
  `CFeVenda\`, `CFeCanc\` (sem as pastas `Schemas`) e `LEIA-ME_backup.txt`. Ficam de fora `BKP\` (backups
  antigos, centenas de MB), `Suporte\`, DLLs e executáveis.- **Volume:** na máquina de dev, `NFCe\NFCeVenda` tem ~19 mil XMLs (234 MB). O zip fica com ~167 MB e leva
  ~3 min.

### Comum

- **Upload e histórico:** 1 zip por instalação em `C:\E-Tech\Backups\upload\` (só o mais recente). No início
  de cada execução, os anteriores vão para `historico\`, que é limpo após `RETENCAO_DIAS` (7).
- **Logs:**
  - `C:\E-Tech\Backups\backup_log.txt`: detalhado, gerado pelo PowerShell.
  - `C:\E-Tech\Backups\bat_execucao.txt`: rastro do batch, gravado mesmo se o PowerShell falhar.
- **Códigos de saída:** 0 ok, 1 falha, 2 nenhuma instalação, 3 já em execução, 9 erro no PowerShell,
  8 (bootstrap) script não disponível.

## Versionamento

- A **linha 1** do `backup-etech.bat` é `:: VERSAO=<inteiro>`. Ela tem que ficar no início da linha, porque é lida com
  `findstr /b`.
- **Toda alteração publicada precisa aumentar esse número.** O bootstrap só atualiza um cliente quando a
  versão do GitHub é maior que a local. Sem aumentar, os clientes continuam na versão antiga.
- **Proteções do bootstrap:**
  - arquivo baixado sem `VERSAO` (página de erro, por exemplo) vale 0 e nunca substitui a cópia local;
  - versão do GitHub menor que a local não faz downgrade;
  - cópia local sem `VERSAO` vale 0, então qualquer versão publicada substitui.
- **Onde a versão aparece:** `bat_execucao.txt` (`BAT v<N> iniciado`, `script atualizado v<A> para v<B>`),
  `backup_log.txt` (`INICIO (v<N>)`) e `LEIA-ME_backup.txt` dentro do zip.
- **Atenção em testes:** não deixar uma versão de teste maior que a publicada em `C:\E-Tech\Suporte\`. Se
  isso acontecer, a máquina recusa as atualizações reais até o GitHub passar desse número.

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
- **Cummins:** `C:\Cummins` real (`Server=localhost`, `Banco=CUMMINS`, `postgres`/`123`, porta 5432),
  PostgreSQL 9.2 na 5432 e 16 na 5434.
- **Conferir o `.backup`:** `createdb cummins_teste_restore`, depois
  `pg_restore -d cummins_teste_restore <arquivo>.backup` (9.2, porta 5432), comparar a contagem de tabelas e
  rodar `dropdb`.

## Pendências

- URL raw (já configurada no bootstrap): https://raw.githubusercontent.com/obaraujo/backup-etech/main/backup-etech.bat (repo público obaraujo/backup-etech, branch main).
- Ainda não foi validado de ponta a ponta no MasterRemote real com o bootstrap.
- Cummins: validado só na máquina de dev (v2). Falta validar num cliente real e num terminal Cummins.
