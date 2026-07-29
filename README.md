# rgb-sync

Sincroniza a iluminação ARGB do PC com a atividade real da GPU: **tudo apagado
em ocioso, tudo em branco estático quando a GPU entra em carga** (jogo, LLM via
Ollama, jobs do ComfyUI/AP AI Studio, ou qualquer outra carga pesada).

Cobre: hub de fans do gabinete (Rise Mode, 8 fans), water cooler (Pichau Aqua
240X) e as duas RAMs. Não mexe em velocidade/rotação de fan nem no display de
temperatura do water cooler — só na luz, via [OpenRGB](https://openrgb.org/).

Ver também: [`pichau-aqua-240x-linux-driver`](../pichau-aqua-240x-linux-driver)
— driver separado, do display de temperatura do pump (LCD), não da luz ARGB.

> ## ⚠️ Problema em aberto
>
> **RAMs e water cooler funcionam de forma confiável. As 8 fans do gabinete
> não.** O hub Rise Mode perde o modo "M/B Sync" em reboots/eventos de energia
> e, uma vez fora dele, ignora sinal válido da placa-mãe — só volta apertando
> o botão físico `ON M/B` no controle remoto. Em 2026-07-29 o firmware do hub
> chegou a travar por completo, **parando as fans de girar** (risco térmico
> real).
>
> Diagnóstico completo, linha do tempo dos incidentes, evidência dos logs e
> hipóteses ainda não testadas: **[`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md)**.

## Hardware coberto

| Componente | Como está ligado |
|---|---|
| Placa-mãe | ASUS PRIME B760M-A D4 |
| Hub de fans (8x, gabinete) | Rise Mode Galaxy Glass Standard V2 |
| Water cooler | Pichau Aqua 240X |
| RAM | 2 pentes com controlador "ENE DRAM" |

**Topologia ARGB — o que está medido** (2026-07-28 e 2026-07-29): a placa-mãe
expõe 4 zonas Aura ("Aura Mainboard" + "Aura Addressable 1/2/3") e só a zona 3
tem algo conectado; as zonas 1 e 2 estão vazias. Na zona 3 respondem as **2
fans do radiador** do water cooler (sempre obedecem) e o **hub de fans**, que
obedece só enquanto estiver no modo "M/B Sync".

O water cooler **não está a jusante do hub**: continua obedecendo o header
enquanto o hub roda o Rainbow autônomo dele. Se o sinal passasse *através* do
hub, o cooler herdaria o Rainbow. A forma exata da fiação (splitter em paralelo
vs. cooler primeiro em série) ainda **não foi confirmada visualmente**.

> ⚠️ **Versões anteriores deste README diziam "encadeados em série, 40 LEDs
> endereçáveis". Isso não tinha base.** O número 40 veio de subir `-sz` até
> "acender tudo uniforme, sem ponta apagada" — mas com **cor única esse teste
> não pode falhar**, qualquer tamanho parece certo. Medindo em 2026-07-29
> (zerar a zona e depois mandar branco com a zona em tamanho 10, e em tamanho
> 1), as fans do cooler acenderam **inteiras nos dois casos** — impossível numa
> cadeia simples de 40 LEDs. `FAN_ZONE_SIZE=40` funciona na prática, mas não
> corresponde a nenhuma contagem física. Detalhes e as duas explicações
> possíveis: [`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md).

## Instalação

Requisitos: Fedora/Bazzite (ou qualquer systemd + `rpm-ostree`), a mesma placa
ASUS PRIME B760M-A D4, sudo.

```bash
cd ~/Projetos/rgb-sync
./install.sh
```

O instalador é idempotente — rodar de novo só confere/corrige o que falta. Ele:

1. Confere se o `openrgb` está instalado; se não estiver, **pergunta antes**
   de rodar `rpm-ostree install openrgb` (isso cria uma camada na imagem
   ostree e exige reboot — o script avisa e para pra você reiniciar e rodar de
   novo).
2. Restringe o servidor OpenRGB a `127.0.0.1` (o padrão do pacote é
   `0.0.0.0`, ouvindo em todas as interfaces — sem necessidade nenhuma nesse
   uso, é só um servidor local pro script conversar com o daemon).
3. Habilita e sobe o `openrgb.service` (nível sistema, roda como root, é
   quem fala com o hardware).
4. Instala e habilita o `gpu-rgb-sync.service` (nível usuário, é o loop que
   decide ligar/apagar).

Depois de rodar, os LEDs devem ficar apagados (estado padrão ocioso). Abra um
jogo pra testar — devem acender em branco em poucos segundos e apagar ~60s
depois de fechar.

## Como funciona

- Um loop (`gpu-rgb-sync.sh`) verifica a cada 10s se a GPU está ativa:
  - **AMD** (RX 9070 XT atual): lê `gpu_busy_percent` via sysfs do `amdgpu`.
  - **NVIDIA** (RTX 5060 Ti anterior): lê utilização + potência via `nvidia-smi`.
  - Detecção de qual backend usar é automática, uma vez, no arranque — trocar
    de GPU não exige editar nada.
- GPU ativa → acende tudo em branco estático, em `A0A0A0` (~63% de duty) e não
  em `FFFFFF`. Branco pleno é o estado de **corrente máxima** de todo o array;
  `A0A0A0` corta ~37% dessa corrente com diferença visual mínima — ver
  "⚠️ Risco conhecido" abaixo. Reafirma a cada 5 min (`ON_REASSERT_SECONDS`)
  enquanto continuar ativa, não a cada ciclo/10s (intervalo mais conservador que
  o do "apagado" de propósito, por segurança extra).
- GPU ociosa por 60s (`DEBOUNCE_SECONDS`) → apaga tudo.
- Enquanto ocioso, re-afirma o "apagado" a cada 2 min (`DEFAULT_REASSERT_SECONDS`)
  pra corrigir qualquer drift (ex: alguém mexeu no software da Aura por fora).
  Só reenvia o mesmo estado (sem transição), então não tem risco de flicker —
  só custa uns writes a mais de SMBus/HID por hora, irrisório.
- No arranque do serviço, força o estado padrão (apagado) antes de qualquer
  outra coisa — cobre reboot, logout/login, crash do serviço.

Variáveis de ambiente pra afinar sem editar o script (`DEBOUNCE_SECONDS`,
`DEFAULT_REASSERT_SECONDS`, `ON_REASSERT_SECONDS`, `SLEEP_SECONDS`,
`UTIL_THRESHOLD_PCT`, `POWER_THRESHOLD_W`) — dá pra sobrescrever no
`ExecStart` do `systemd/gpu-rgb-sync.service` se precisar.

## Quando o hub sai do modo "M/B Sync"

**Isso nenhum software resolve.** O hub Rise Mode sai do modo "M/B Sync" em
eventos de reboot/energia e passa a rodar o Rainbow autônomo dele, ignorando o
header ARGB da placa-mãe. Placa-mãe (Aura), RAMs e as fans do water cooler
continuam obedecendo normalmente; só o hub fica preso nesse estado.

**Não é exclusivo de queda de energia total** — como este README dizia antes.
Um `systemctl reboot` limpo bastou (2026-07-29 16:48).

**E não é por falta de sinal no header.** Isso foi testado contra os logs e
refutado: o header ficou em `Off` por **54min58s** na manhã de 2026-07-29 e o
hub continuou obedecendo depois (acendeu branco às 09:46:07 — cor que só o
script manda). Ele caiu depois, numa janela de silêncio de **70 segundos**, num
reboot. Ausência de dado não é o gatilho; o evento de reboot é. Ver
[`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md).

Pra corrigir, é preciso apertar o botão **"ON M/B"** no controle remoto do hub.
**Antes de apertar**, garanta que já existe sinal ARGB válido no header nesse
exato momento — rode `./install.sh` de novo (ele reinicia o
`gpu-rgb-sync.service`, que aplica branco/apagado imediatamente) ou simplesmente
abra um jogo por um instante. Isso importa porque em 2026-07-27 apertar o botão
com a zona sem nenhum sinal configurado (tamanho 0, header "mudo") travou o
sistema inteiro, exigindo desligar a fonte e o HDMI pra recuperar — os logs não
mostram uma causa definitiva (o boot simplesmente para de logar, sem panic),
mas o padrão bate com "hub esperando dado que nunca chega". Com sinal válido
presente, o mesmo botão funcionou sem problema nenhum.

## ⚠️ Risco conhecido: hub pode travar (fans param de girar)

**Incidente real (2026-07-29):** durante uma sessão longa de jogo, o
microcontrolador do hub Rise Mode travou — as 8 fans do gabinete **pararam de
girar completamente** e o controle remoto do hub ficou 100% sem resposta (nem
cor, nem ON M/B, nada). Os LEDs continuaram acesos em branco, **mas isso não
prova que o hub estava funcionando**: LEDs endereçáveis (WS2812) retêm a
última cor recebida indefinidamente, sem precisar de sinal contínuo — o "LED
aceso e parado" era só a última cor latched antes do travamento, não sinal de
vida.

Causa suspeita (não 100% confirmada, só 1 incidente — analisado em detalhe:
não há nenhum erro de kernel/USB/I2C na janela do incidente, o que bate com
uma falha interna ao firmware do hub, invisível pro host): o script chegou a
reenviar o comando "ligado" a cada 10 segundos, sem parar, enquanto a GPU
ficava ativa. A única sessão ativa longa do dia (19min contínuos) terminou
bem na hora em que o problema foi notado — coincidência forte, ainda que não
seja prova definitiva. Nessa janela foram ~114 comandos repetidos pro mesmo
hub. Corrigido voltando a reafirmar o "ligado" a cada `ON_REASSERT_SECONDS`
(5 min, mais conservador de propósito que o `DEFAULT_REASSERT_SECONDS` do
lado "apagado", que ficou em 2 min).

**⚠️ Existe uma segunda causa possível, com correlação exatamente igual, que a
análise original não considerou:** aquela mesma janela de 19 min foi também o
**maior período contínuo de `FFFFFF` — corrente máxima de todo o array** (~60 mA
por LED em branco pleno). Estresse prolongado do regulador do hub é candidato
tão plausível quanto firmware afogado em comando, e as duas explicações são
indistinguíveis pelos dados. Por isso a cor passou para `A0A0A0` em 2026-07-29,
cortando ~37% da corrente. **As duas mitigações estão ativas ao mesmo tempo** —
se travar de novo, não vai dar pra saber qual hipótese estava certa, mas o
objetivo é não travar.

**Isso é uma falha de segurança real, não cosmética**: fans de gabinete
paradas comprometem o fluxo de ar sob carga (jogo, LLM, render). Se as fans do
hub pararem de girar de novo:

1. Pare o serviço: `systemctl --user stop gpu-rgb-sync.service`.
2. Evite carga pesada até resolver (temperatura pode subir mais rápido que o
   normal sem essas fans).
3. Teste o controle remoto do hub. Se **nenhum botão** funcionar (nem trocar
   cor, nem M/B), o microcontrolador dele travou — não tem correção por
   software.
4. Corrija com um power-cycle **isolado do hub**: PC desligado, desconecte só
   o cabo de alimentação (SATA/Molex) do hub por uns 30s, reconecte, ligue o
   PC. Isso resetou o problema no incidente real.
5. Depois disso o hub volta pro Rainbow autônomo dele (mesmo comportamento de
   uma queda de energia total — ver seção abaixo) — normal, siga o
   procedimento de "ON M/B".

**Limitação real, sem solução por software**: não há sensor de RPM exposto
pelo sistema operacional pros fan headers desse hub (só a GPU tem sensor de
fan próprio, sem relação). Não dá pra detectar "fans paradas" automaticamente
— depende de checagem física/auditiva ocasional, especialmente em sessões
longas de carga pesada.

## Como remapear zonas (se trocar hub/water cooler/placa)

1. Pare o serviço pra evitar interferência: `systemctl --user stop gpu-rgb-sync.service`.
2. Liste os dispositivos: `openrgb --list-devices`.
3. Teste cor por zona pra identificar o que é o quê:
   ```bash
   openrgb -d "ASUS" -z 1 -sz 8 -c FF0000 -m static   # zona 1 = vermelho
   openrgb -d "ASUS" -z 2 -sz 8 -c 00FF00 -m static   # zona 2 = verde
   openrgb -d "ASUS" -z 3 -sz 8 -c 0000FF -m static   # zona 3 = azul
   ```
4. **Não** tente achar o total de LEDs subindo `-sz` até "acender uniforme":
   com cor única esse teste não pode falhar e dá falso positivo em qualquer
   tamanho. Foi assim que o número 40 entrou aqui sem base. Para medir de
   verdade é preciso um padrão com fronteira visível, e o CLI do OpenRGB não
   entrega isso — `-c` com lista de cores só funciona sem efeito, e `-m direct`
   **apaga o header** neste hardware (medido em 2026-07-29). Na prática:
   escolha um tamanho que funcione e não trate o número como contagem física.
5. Atualize `FAN_ZONE_INDEX` e `FAN_ZONE_SIZE` em `gpu-rgb-sync.sh`.
6. `systemctl --user restart gpu-rgb-sync.service`.

## Testes já validados (2026-07-28)

- Abrir/fechar jogo (Hogwarts Legacy): liga em branco, apaga ~60s depois de
  fechar.
- Reboot normal: serviços sobem sozinhos, estado padrão apagado, zona 3 mantém
  o tamanho (40 LEDs) sem precisar reconfigurar.
- Reboot com jogo/app subindo automático no login: o auto-retry a cada ciclo
  corrige o caso em que o 1º "ligar" dispara antes do dispositivo Aura estar
  pronto (bug real encontrado e corrigido nesse dia — ver abaixo).
- Botão "ON M/B" do hub com sinal ARGB válido já presente: sem travamento.

## Bugs corrigidos (histórico)

- **Corrida de boot no "ligar"** (2026-07-28): o script só mandava o comando
  de ligar uma vez, na transição. Se disparasse antes do dispositivo Aura
  estar pronto (ex: jogo abrindo automático logo no login), falhava
  silenciosamente e nunca mais tentava — RAMs ligavam (mais rápidas a
  responder) mas fans+water cooler ficavam apagados. Corrigido reaplicando o
  comando a cada ciclo (10s) enquanto a GPU estivesse ativa.
- **Hub travou com o fix acima** (2026-07-29): reenviar o comando a cada 10s
  numa sessão longa de jogo aparentemente sobrecarregou o firmware do hub —
  fans do gabinete pararam de girar e o controle remoto ficou sem resposta
  nenhuma (ver "⚠️ Risco conhecido" acima). Corrigido trocando "a cada ciclo"
  por "a cada `ON_REASSERT_SECONDS` (5min, separado do `DEFAULT_REASSERT_SECONDS`
  de 2min usado no lado "apagado")", mantendo a correção da corrida de boot
  original sem martelar o hub continuamente.
- **Log dizia "Rainbow"** depois de trocar o efeito pra branco estático — só
  texto, sem efeito funcional.

## Arquivos

- `gpu-rgb-sync.sh` — o script principal (o loop de decisão).
- `install.sh` — instalador idempotente.
- `systemd/gpu-rgb-sync.service` — unidade de usuário (template, o instalador
  substitui `{{SCRIPT_PATH}}` pelo caminho real).
- `systemd/openrgb-server-override.conf` — restringe o `openrgb.service` do
  sistema a `127.0.0.1`.

## Desinstalar

```bash
systemctl --user disable --now gpu-rgb-sync.service
rm ~/.config/systemd/user/gpu-rgb-sync.service
systemctl --user daemon-reload
```

O `openrgb.service` e o pacote `openrgb` podem ficar (não fazem mal parados);
pra remover de vez: `sudo systemctl disable --now openrgb.service` e
`sudo rpm-ostree uninstall openrgb` (exige reboot).
