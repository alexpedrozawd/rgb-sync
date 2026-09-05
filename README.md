# rgb-sync

Mantém **toda a iluminação ARGB do PC em branco estático, permanentemente**.
Sem RGB, sem efeito, sem acender e apagar: um estado só, branco, 24/7.

Cobre: 8 fans do gabinete (hub Rise Mode), 2 fans do radiador do water cooler
(Pichau Aqua 240X) e as 2 RAMs. Não mexe em velocidade/rotação de fan nem no
display de temperatura do water cooler — só na luz, via
[OpenRGB](https://openrgb.org/).

Ver também: [`pichau-aqua-240x-linux-driver`](../pichau-aqua-240x-linux-driver)
— driver separado, do display de temperatura do pump (LCD), não da luz ARGB.

> ## ⚠️ Problema em aberto (atualizado em 2026-07-30)
>
> **RAMs e fans do cooler funcionam de forma confiável. O hub Rise Mode (8 fans
> do gabinete) já travou 2 vezes em 4 dias** — controle remoto sem resposta,
> LEDs com cor presa. Em 2026-07-29 chegou a **parar as fans de girar** (risco
> térmico real).
>
> A recuperação mudou: um **corte de energia completo** (fonte desligada na
> tomada por ~1min, não um simples reinício) trouxe o hub de volta ao M/B Sync
> **sozinho, sem apertar `ON M/B`**, com anéis e pás em branco — a primeira vez
> observada. Ainda é uma amostra única, mas é o procedimento a tentar primeiro
> hoje, antes do controle remoto.
>
> Diagnóstico completo, linha do tempo dos incidentes, evidência dos logs e o
> que já foi refutado (ou corrigido): **[`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md)**.

## O projeto mudou em 2026-07-30

Antes ele sincronizava com a GPU: acendia em branco sob carga (jogo, LLM,
render) e apagava ~60s depois de ficar ocioso. Isso foi **removido** por
preferência do dono — branco permanente incomoda menos de dia e ilumina de
noite.

A mudança também é um ganho técnico, não só de gosto:

- **O header nunca mais fica mudo.** Elimina por construção o cenário que travou
  o PC inteiro em 2026-07-27 (apertar `ON M/B` com a zona sem sinal).
- **Sem transições, o tráfego no header cai para 2 escritas por hora.** O
  travamento do hub em 2026-07-29 aconteceu sob ~6 escritas por **minuto**
  sustentadas por 19 minutos — é cerca de 180x menos tráfego.
- **É a melhor chance de o sync sobreviver a um reboot, e nunca foi testada.**
  No desenho antigo, a primeira ação de todo boot era *apagar*: o header ficava
  mudo pelos primeiros ~30s. Agora ele carrega branco válido desde o POST. Se o
  hub decide o modo no próprio power-on conforme haja sinal na linha — design
  comum nessa classe de hub — o resultado muda.

> **Contrapartida honesta:** branco pleno é o estado de **corrente máxima** do
> array (~60 mA por LED), e agora é permanente em vez de só sob carga. Se a
> hipótese de que o travamento veio de corrente sustentada estiver certa, essa
> exposição aumentou. Não há como mitigar pela cor: cinza neutro dá branco
> **amarelado** nesse hardware (o die azul perde eficiência em duty reduzido).
> O caminho, se precisar, é o **botão de brilho do controle IR do hub**, que
> reduz a corrente sem tocar no header.

O que o projeto perdeu, e não volta sem reescrever: a sincronia com a GPU, a
detecção automática NVIDIA/AMD, e os limiares de atividade. Está tudo no
histórico do git se um dia for necessário.

### Hardware coberto

| Componente | Modelo | Conexão / Zona |
|---|---|---|
| Placa-mãe | ASUS PRIME B760M-A D4 | Controlador Aura USB HID (`0B05:19AF`) |
| Hub de fans (8x, gabinete) | Rise Mode Galaxy Glass Standard V2 | **Header 1 (`ADD_GEN2_1` / Zona 1)** |
| Water cooler | Pichau Aqua 240X (bomba + 2 fans) | **Header 3 (`ADD_GEN2_3` / Zona 3)** |
| RAM | 2 pentes com controlador "ENE DRAM" | Barramento SMBus I801 (`0x71` e `0x73`) |

**Topologia ARGB — medida e confirmada em 2026-09-05:**
- **Header 1 (`ADD_GEN2_1` / Zona 1):** Hub Rise Mode com as 8 fans do gabinete.
- **Header 3 (`ADD_GEN2_3` / Zona 3):** Water Cooler Pichau Aqua 240X (anel da bomba e as 2 fans do radiador).
- **Header 2 (`ADD_GEN2_2` / Zona 2):** Vazio.

> ⚠️ **Por que a separação de headers importa:** O script anterior assumia que tudo
> estava na Zona 3 e deixava a Zona 1 com tamanho 0 (sem sinal). Quando o botão
> `ON M/B` era apertado, o microcontrolador do hub tentava ler o Header 1 sem dados
> e **travava completamente** (apagando os LEDs e parando de responder ao controle).
> Com o script atual, ambas as Zonas 1 e 3 recebem sinal válido contínuo desde o
> boot com tamanho 40, prevenindo travamentos.

## Instalação

Requisitos: Fedora/Bazzite (ou qualquer systemd + `rpm-ostree`), a mesma placa
ASUS PRIME B760M-A D4, sudo.

```bash
cd ~/Projetos/rgb-sync
./install.sh
```

O instalador é idempotente — rodar de novo só confere/corrige o que falta. Ele:

1. **Remove o serviço antigo `gpu-rgb-sync.service`**, se existir (os dois
   brigariam pelos mesmos LEDs).
2. Confere se o `openrgb` está instalado; se não estiver, **pergunta antes** de
   rodar `rpm-ostree install "openrgb-1.0*"` (especifica a versão oficial para
   evitar conflito com o COPR de akmods do Bazzite; cria uma camada ostree e
   exige reboot — o script avisa e para pra você reiniciar e rodar de novo).
3. Restringe o servidor OpenRGB a `127.0.0.1` (o padrão do pacote é `0.0.0.0`,
   ouvindo em todas as interfaces — sem necessidade nenhuma nesse uso).
4. Garante a existência de `/etc/openrgb` para o daemon.
5. Habilita o `openrgb.service` (nível sistema, roda como root, é quem fala com
   o hardware).
6. Instala e habilita o `rgb-branco.service` (nível usuário) e configura a
   regra de limpeza periódica de logs em `~/.config/user-tmpfiles.d/openrgb-logs.conf`.

Em até ~30s tudo deve estar branco e calibrado.

## Como funciona

O script [`rgb-branco.sh`](rgb-branco.sh) opera em segundo plano:

1. **Sonda de arranque (`aguardar_openrgb`)** — aguarda o servidor OpenRGB responder
   e confirmar a presença do controlador Aura antes de enviar qualquer comando
   (até 30 tentativas x 2s). Elimina corridas de boot.
2. **Aplicação com proteção de canal** — lê o tamanho das Zonas 1 e 3 antes de
   escrever; se alguma tiver zerado (ex.: corte de energia), reconfigura o tamanho
   para 40 LEDs. Se já estiver correto, apenas atualiza a cor da zona sem forçar
   reconfiguração invasiva de canal.
3. **Regime** — reafirma o estado a cada `REASSERT_SECONDS` (30 min / 2 escritas por hora)
   para corrigir eventual drift de firmware ou sobrescrita acidental por apps externos.

### Calibração de cores e brilho por dispositivo

Cada componente possui sua cor específica calibrada diretamente nos valores RGB:

| Dispositivo | Header / Conexão | Cor Configurada | Justificativa |
|---|---|---|---|
| **Hub Rise Mode (8 fans)** | Zona 1 (`ADD_GEN2_1`) | `HUB_COLOR=707090` | **48% de duty cycle** — metade da corrente do branco pleno (`FFFFFF`), prevenindo desarme térmico e hiccup no hub |
| **Water Cooler (bomba + 2 fans)** | Zona 3 (`ADD_GEN2_3`) | `COOLER_COLOR=182220` | **Branco suave esverdeado** — tom sutil personalizado com brilho afinado para visual agradável e discreto |
| **Memórias RAM (2x ENE DRAM)** | SMBus `0x71` e `0x73` | `RAM_COLOR=7272C0` | **Compensação de azul (B/R 1.68)** — evita o tom amarelado causado pela perda de eficiência do die azul em duty reduzido |

Todas as cores são sobrescrevíveis por variável de ambiente no `rgb-branco.service` ou no ambiente do script.

## Quando as 8 fans do gabinete não estão brancas

Significa que o hub saiu do modo "M/B Sync" e está rodando o Rainbow autônomo
dele (ou travou — ver "Risco conhecido" abaixo), ignorando o header.

**Primeiro recurso: corte de energia completo, não o botão.** Desligue tudo,
desconecte a fonte da tomada por ~1 minuto, segure o botão de power do
gabinete por ~5s pra drenar energia residual, reconecte e ligue. Em 2026-07-30
isso trouxe o hub de volta ao M/B Sync **sozinho**, com anéis e pás em branco,
sem apertar nada no controle remoto — resultado melhor que o procedimento
antigo, embora ainda seja uma amostra única (ver
[`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md), seção 6). Um `reboot`
comum **não** teve esse efeito num teste anterior.

Se o corte de energia completo não resolver, aí sim o controle remoto:

1. **Confirme que existe sinal válido no header**: as 2 fans do cooler devem
   estar brancas. Se não estiverem, rode `./install.sh` de novo e espere.
2. Aperte **`ON M/B`** no controle IR do hub.

> ⚠️ A ordem importa. Em 2026-07-27, apertar o botão com a zona sem nenhum sinal
> configurado (tamanho 0, header mudo) **travou o sistema inteiro**, exigindo
> desligar a fonte e o HDMI. Os logs não mostram causa definitiva (o boot
> simplesmente para de logar, sem panic), mas o padrão bate com "hub esperando
> dado que nunca chega". Com sinal válido presente, o mesmo botão funcionou sem
> problema. Com este desenho o header está sempre com sinal, então a condição
> perigosa só ocorre se o serviço estiver parado.

## ⚠️ Risco conhecido: o hub trava (3 vezes em 14 dias)

**Incidente 1 (2026-07-29), sob sincronia com GPU:** durante a janela de 19 min
contínuos de branco, o microcontrolador travou — as 8 fans **pararam de girar**
e o controle remoto ficou 100% sem resposta. Risco térmico real.

**Incidente 2 (2026-07-30), já sob branco permanente:** anéis com cor presa e
misturada (branco+rainbow — retenção de frame, não efeito), pás apagadas,
controle remoto de novo sem resposta. Pás continuaram girando.

**Incidente 3 (2026-08-12), após ~24h de uptime:** fans pararam de girar de
novo — mas com um **sintoma novo e decisivo**: os LEDs estavam **piscando**, não
com cor presa. Piscar significa algo *ciclando* (liga, atinge um limite,
desliga, tenta de novo) — assinatura de **proteção de alimentação em modo
hiccup**, não de firmware travado. Aponta para energia, não para lógica.

LEDs acesos **não provam** que o hub está funcionando: WS2812 retém a última
cor recebida indefinidamente, sem sinal contínuo.

### A causa mais provável, e o que ela implica

**Antes deste projeto existir, o hub rodava Rainbow autônomo e nunca travou.**
Essa observação do dono é o melhor indício que existe, e reorienta tudo: o
problema está no que **mudamos**, não num componente que já estava morrendo.

A conta: no Rainbow cada LED mostra um tom saturado — vermelho puro acende 1
canal, amarelo 2, ciano 2. A média ao longo do arco-íris fica em ~**48% dos
canais ligados**. Branco pleno acende os **3 canais em 100%**. O projeto
**praticamente dobrou a corrente contínua** pelo hub — e desde 2026-07-30, 24/7.

O hub é especificado para até 10 fans (são 8 em uso), mas rodando **os efeitos
dele**. Branco pleno em todos os LEDs é um estado que o firmware dele nunca
produz sozinho, e que nunca foi validado.

| Candidato | Estado |
|---|---|
| Firmware afogado em comando repetido | Mitigado ao limite (2 escritas/hora) — **travou mesmo assim, descartado** |
| Corrente sustentada / proteção de alimentação | **Principal.** Mitigado em 2026-08-12: brilho a 48% de duty |
| Modo M/B Sync em si | Reserva. Se travar a 48%, é o que sobra |

**Mitigação em teste desde 2026-08-12:** `LED_COLOR=707090` e
`RAM_COLOR=72728B`, ambos calibrados para 48% de duty — a mesma corrente do
Rainbow que rodou meses sem pane. Isso deixa a configuração a **uma única
variável** do estado comprovadamente seguro (só o M/B Sync difere).

> **Ciclo de retorno longo:** o intervalo entre a 2ª e a 3ª pane foi de 13 dias.
> "Não travou hoje" não significa nada — só há sinal após **2 a 3 semanas**.
>
> **Se travar mesmo a 48%:** a hipótese de corrente cai e sobra o M/B Sync. O
> plano B é pôr o hub em **modo autônomo branco com brilho reduzido pelo
> controle IR** (ele tem branco e controle de brilho), tirando a placa-mãe do
> caminho do hub. O script continua cuidando do cooler e das RAMs. Custo: o hub
> volta a Rainbow após queda total de energia, exigindo apertar botões — mesma
> chateação do `ON M/B` de hoje.

Se as fans do hub pararem de girar, ou o controle remoto não responder:

1. Pare o serviço: `systemctl --user stop rgb-branco.service`.
2. Evite carga pesada até resolver.
3. Teste o controle remoto. Se **nenhum botão** funcionar, o microcontrolador
   travou.
4. **Tente primeiro um corte de energia COMPLETO**, não só o Molex do hub: PC
   desligado → fonte desconectada da tomada por ~1min → segure o botão de power
   do gabinete ~5s pra drenar residual → reconecte → ligue. Em 2026-07-30 isso
   recuperou o hub **sozinho, sem apertar nada**, com anéis e pás em branco —
   melhor resultado que o power-cycle isolado do hub (só o Molex, ~30s) usado
   antes. Ainda é uma amostra única; se não funcionar, tente o power-cycle
   isolado do Molex do hub como alternativa.
5. Se voltar em Rainbow autônomo (em vez de já voltar em M/B Sync sozinho),
   siga o procedimento de `ON M/B` acima.

**Limitação real, sem solução por software:** não há sensor de RPM exposto pelo
sistema para os fan headers desse hub — confirmado, o `hwmon` do `asus_wmi` não
tem nenhuma entrada de fan e não há `nct6775`/`it87` carregado. O único sensor de
fan é o da GPU. **Não dá para detectar "fans paradas" automaticamente** — depende
de checagem física/auditiva ocasional, especialmente em carga pesada prolongada.

## Como remapear zonas (se trocar hub/cooler/placa)

1. Pare o serviço: `systemctl --user stop rgb-branco.service`.
2. Liste os dispositivos: `openrgb --list-devices`.
3. Teste cor por zona para identificar o que é o quê:
   ```bash
   openrgb -d "ASUS" -z 1 -sz 8 -c FF0000 -m static   # zona 1 = vermelho
   openrgb -d "ASUS" -z 2 -sz 8 -c 00FF00 -m static   # zona 2 = verde
   openrgb -d "ASUS" -z 3 -sz 8 -c 0000FF -m static   # zona 3 = azul
   ```
4. **Não** tente achar o total de LEDs subindo `-sz` até "acender uniforme":
   com cor única esse teste não pode falhar e dá falso positivo em qualquer
   tamanho. Foi assim que o número 40 entrou aqui sem base. Medir de verdade
   exigiria um padrão com fronteira visível, e o CLI do OpenRGB não entrega —
   `-c` com lista de cores só funciona sem efeito, e `-m direct` **apaga o
   header** neste hardware (medido em 2026-07-29). Na prática: escolha um tamanho
   que funcione e não trate o número como contagem física.
5. Atualize `FAN_ZONE_INDEX` e `FAN_ZONE_SIZE` em `rgb-branco.sh`.
6. `systemctl --user restart rgb-branco.service`.

## Arquivos

- `rgb-branco.sh` — o script (aplica branco e reafirma).
- `install.sh` — instalador idempotente, com migração do serviço antigo.
- `systemd/rgb-branco.service` — unidade de usuário (template, o instalador
  substitui `{{SCRIPT_PATH}}` pelo caminho real).
- `systemd/openrgb-server-override.conf` — restringe o `openrgb.service` do
  sistema a `127.0.0.1`.

## Bugs corrigidos (histórico)

Mantido porque cada um destes custou tempo e a causa não era óbvia.

- **Corrida de boot** (2026-07-28): o comando era enviado uma única vez. Se
  disparasse antes do dispositivo Aura estar pronto, falhava em silêncio e nunca
  mais tentava — RAMs acendiam (mais rápidas a responder) e o resto ficava
  apagado. Hoje coberto pela rajada de arranque.
- **Hub travou com o fix acima** (2026-07-29): o comando passou a ser reenviado a
  cada 10s, e numa sessão longa de jogo o firmware do hub travou (ver "Risco
  conhecido").
- **LEDs acendiam sozinhos em idle** (2026-07-30, no desenho antigo): o limiar
  `UTIL_THRESHOLD_PCT=1` era herdado da NVIDIA. Medindo o idle da RX 9070 a 1Hz
  por 4 minutos com a máquina parada:

  ```
  0% -> 236 amostras
  1% ->   4 amostras   @ 01:25:00, 01:26:00, 01:27:00, 01:28:00
  ```

  Algo dispara **uma vez por minuto, exatamente no segundo `:00`**, com um pico
  de 1% que dura menos de 1 segundo. Com o limiar em 1, `1 >= 1` era verdadeiro e
  o pico virava "GPU ativa", acendendo tudo por 60s+. Como o laço amostrava a
  cada 10s, ele pegava o pico por **coincidência de fase**, ~1 vez a cada 10 min
  — daí os intervalos irregulares e as ligadas sempre no mesmo segundo do minuto
  nos logs. Na madrugada de 2026-07-29, sem ninguém usando a máquina, os LEDs
  acenderam ~50 vezes entre 00:00 e 04:15. Hoje é irrelevante: não existe mais
  limiar de atividade.
- **`A0A0A0` para reduzir corrente** (2026-07-29, revertido em 2026-07-30):
  cinza neutro nesse hardware não dá branco mais suave, dá **branco amarelado**.
- **RAMs amareladas em `FFFFFF`** (2026-07-30): não é bug de código, é física do
  LED — duty igual em R/G/B não dá branco neutro. Corrigido com uma cor
  calibrada separada para as RAMs (`RAM_COLOR`). Ver "Por que existem duas cores
  de branco".
- **"Hélices apagadas" nas 8 fans** (2026-07-30, corrigido na madrugada
  seguinte): a hipótese de que a cadeia tivesse mais LEDs que os 40 endereçados
  foi refutada (`-sz 120` não acendeu nada a mais) — descoberta lateral útil:
  **`FAN_ZONE_SIZE` não tem efeito observável entre 1 e 120**, só `0` importa
  (header mudo). Mas a conclusão seguinte, de que "as pás não têm LED próprio e
  nunca acenderiam sob M/B Sync", **estava errada** — foi inferida observando um
  hub que na verdade estava **travado**. Corrigido depois de um corte de
  energia completo: o hub voltou ao M/B Sync com anéis **e** pás em branco. Ver
  [`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md), seção 6.
- **Log dizia "Rainbow"** depois de trocar o efeito para branco — só texto.

## Desinstalar

```bash
systemctl --user disable --now rgb-branco.service
rm ~/.config/systemd/user/rgb-branco.service
systemctl --user daemon-reload
```

O `openrgb.service` e o pacote `openrgb` podem ficar (não fazem mal parados);
para remover de vez: `sudo systemctl disable --now openrgb.service` e
`sudo rpm-ostree uninstall openrgb` (exige reboot).
