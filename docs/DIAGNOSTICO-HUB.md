# Diagnóstico: o hub de fans não mantém o modo "M/B Sync"

**Documento de handoff.** Escrito em 2026-07-29 para uma sessão nova, sem
contexto prévio. Reúne tudo que foi medido, o que foi só inferido, os
incidentes reais e as hipóteses ainda em aberto.

Leia junto com o [`README.md`](../README.md) (manual de uso) e o
[`gpu-rgb-sync.sh`](../gpu-rgb-sync.sh) (comentários no topo do arquivo).

Logs brutos das janelas citadas estão em [`logs/`](logs/).

---

## 1. O problema em uma frase

O software funciona; **o hub de fans do gabinete não.** RAMs e water cooler
obedecem 100% dos comandos, sempre. O hub Rise Mode (8 fans do gabinete) só
obedece enquanto estiver no modo "M/B Sync", e ele **sai desse modo sozinho**
em eventos de energia/reboot — e a única forma conhecida de voltar é apertar
fisicamente o botão `ON M/B` no controle remoto infravermelho dele.

O objetivo original do projeto — "sobreviver a reboots, quedas de energia,
etc." — **está atingido para RAM e water cooler, e não está atingido para o
hub.**

---

## 2. Estado atual (2026-07-29 19:00)

| Item | Estado |
|---|---|
| `openrgb.service` (sistema) | `active` + `enabled` |
| `gpu-rgb-sync.service` (usuário) | `active` + `enabled` |
| Zona 3 (`Aura Addressable 3`) | 40 LEDs, preservado através de reboots |
| RAMs (2x `ENE DRAM`) | Obedecem normalmente |
| Water cooler (Pichau Aqua 240X) | Obedece normalmente |
| 8 fans do gabinete (hub Rise Mode) | **Rainbow autônomo, ignorando a placa-mãe** |
| Backend de GPU detectado | `amd` (RX 9070 XT, via `gpu_busy_percent`) |

Último `git log`:

```
79aa980 Separa intervalo de reassert do "ligado" (5min) do "apagado" (2min)
08abb9d Corrige risco de seguranca: hub travava com reassert a cada 10s
ff44b3d Reduz reassert de idle de 5min para 2min
157b7e0 Configuracao inicial: sync de LEDs ARGB com atividade da GPU
```

---

## 3. Hardware e topologia

| Componente | Modelo |
|---|---|
| Placa-mãe | ASUS PRIME B760M-A D4 (Aura, HID `/dev/hidraw2`) |
| GPU | AMD Radeon RX 9070 XT (Navi 48, `amdgpu`) |
| Gabinete / fans | Rise Mode Galaxy Glass Standard V2 — hub ativo + controle remoto IR, 8 fans em uso (o kit é de 10; 2 saíram para caber o water cooler) |
| Water cooler | Pichau Aqua 240X |
| RAM | 2 pentes, controlador `ENE DRAM` (SMBus `0x71` e `0x73`) |
| OpenRGB | `openrgb-1.0~rc2-3.20260126git74cbdcc.fc44` (layered via `rpm-ostree`) |
| SO | Bazzite 44 (Fedora Kinoite, ostree), kernel `7.1.3-ogc5.1.fc44` |

### Topologia ARGB — o que foi medido

A placa expõe 4 zonas: `Aura Mainboard`, `Aura Addressable 1`, `2` e `3`.
Testando uma cor diferente por zona com o hardware à vista (2026-07-28):

- **Zona 3** → acende o water cooler **e** o hub de fans. É a única com algo
  ligado.
- **Zonas 1 e 2** → nada conectado.

### O que é ASSUMIDO, não medido (importante)

1. **Os 40 LEDs da zona 3 são um chute que "pareceu certo"**, não uma
   contagem real. Foi definido mandando `-sz 40` e observando que tudo
   acendeu uniforme, sem ponta apagada. Nunca se determinou o número
   verdadeiro de LEDs da cadeia. Fabricante não publica a contagem por fan
   (busca feita; Rise Mode e Pichau não divulgam).
2. **A forma da ligação não foi confirmada visualmente.** O comportamento
   observado (o water cooler continua obedecendo a placa-mãe mesmo com o hub
   em Rainbow autônomo) é mais compatível com **hub e water cooler em
   paralelo, a partir de um splitter no header da zona 3**, do que com uma
   cadeia em série passando pelo hub — se o sinal passasse *através* do hub,
   o water cooler provavelmente herdaria o Rainbow dele. **Vale abrir o
   gabinete e conferir fisicamente**, porque isso muda o diagnóstico e as
   opções de solução.

---

## 4. O que funciona de forma confiável (não mexer)

- Detecção de carga de GPU: `gpu_busy_percent` via sysfs do `amdgpu`.
  Responde corretamente a jogos e cargas reais. Validado em hardware.
- Detecção automática de backend AMD/NVIDIA no arranque.
- `openrgb.service` como servidor persistente + script como cliente. Sem
  isso, cada chamada `openrgb` standalone leva ~8,7s (a RX 9070 registra ~13
  barramentos I2C que são re-sondados do zero a cada invocação).
- Bind do servidor OpenRGB restrito a `127.0.0.1` via drop-in em
  `/etc/systemd/system/openrgb.service.d/override.conf` (o default do pacote
  é `0.0.0.0`).
- Persistência do tamanho da zona: os 40 LEDs ficam gravados no controlador
  Aura e sobrevivem a restart do serviço **e a reboot** (verificado várias
  vezes, inclusive no boot atual).
- Serviços sobem sozinhos no boot, sem intervenção.
- RAM e water cooler: ligam, apagam e mudam de cor de forma 100% previsível.

---

## 5. Linha do tempo dos incidentes

### 2026-07-27 — Travamento TOTAL do PC ao apertar `ON M/B`

Contexto: nesse momento a zona 3 ainda estava com **tamanho 0** (nenhum LED
configurado) — ou seja, o header não emitia dado nenhum. Ao apertar o botão
`ON M/B` no controle do hub, as fans apagaram e **o sistema inteiro travou**:
nem o botão de LED do gabinete respondia. Precisou desligar a fonte e
desconectar o HDMI para recuperar.

**Evidência nos logs:** o boot simplesmente **para de logar** às 23:16:48, sem
kernel panic, sem oops, sem OOM, sem sequência de shutdown. Hang duro.
Ver [`logs/incidente-2026-07-27-travamento-total-fim-do-boot.log`](logs/incidente-2026-07-27-travamento-total-fim-do-boot.log).

**Pista falsa descartada:** havia 120 ocorrências de
`i2c_designware i2c_designware.0: controller timed out` naquele boot, mas o
mesmo erro aparece 186 vezes em boots saudáveis. É ruído crônico do sistema,
não relacionado (o SMBus da Aura/RAM é o `i801`, não o `designware`).

**Causa raiz: NÃO determinada.** O padrão é compatível com "hub entrou em modo
de escuta e travou porque não havia sinal válido no header", mas isso não é
provável — o hub travar não deveria derrubar o host. Não foi reproduzido
desde então (todas as vezes seguintes o botão foi apertado com sinal válido
presente e não houve travamento).

### 2026-07-28 — Corrida de boot (bug meu, corrigido)

Após reboot, as RAMs acendiam mas fans + water cooler ficavam apagados. Causa:
o script só mandava o comando "ligar" **uma vez**, na transição; se disparasse
antes do dispositivo Aura estar pronto no OpenRGB, falhava em silêncio e nunca
mais tentava. Corrigido fazendo reaplicar periodicamente.

> Essa correção, na primeira versão, reaplicava **a cada ciclo (10s)** — e foi
> ela que provavelmente causou o incidente do dia seguinte. Ver abaixo.

### 2026-07-29 (manhã) — Hub travado: FANS PARARAM DE GIRAR ⚠️

O mais grave. Sintomas:

- As 8 fans do gabinete **pararam de girar completamente**.
- Os LEDs continuaram acesos em branco, parados.
- O controle remoto do hub ficou **100% sem resposta** — nenhum botão fazia
  nada (nem cor, nem efeito, nem `ON M/B`).
- Water cooler e RAMs continuaram normais o tempo todo.

**Por que "LED aceso" não significa "hub vivo":** LEDs endereçáveis (tipo
WS2812) **retêm a última cor recebida indefinidamente**, sem precisar de sinal
contínuo. O branco parado era só a última cor *latched* antes do travamento —
não sinal de vida do controlador.

**Recuperação:** só voltou com **power-cycle isolado do hub** (desconectar o
cabo de alimentação dele da fonte). Reboot não resolveu.

**Evidência coletada:**
- **Zero** erros de kernel/USB/I2C na janela do incidente — o Linux não viu
  nada. Consistente com falha interna ao firmware do hub, invisível ao host.
- A janela 09:46–10:05 foi a **única sessão de GPU ativa longa e contínua do
  dia** (19 minutos seguidos). Todas as outras foram de 1–2 minutos.
- Nessa janela o script mandou ~**114 comandos repetidos** de "ligar" para o
  mesmo hub (um a cada ~13s: 10s de sleep + overhead).
- O problema foi notado logo após essa janela terminar.

Ver [`logs/incidente-2026-07-29-hub-travado.log`](logs/incidente-2026-07-29-hub-travado.log).

**Causa suspeita (correlação forte, NÃO provada):** o bombardeio de comandos a
cada 10s sobrecarregou o firmware frágil do hub. Não é possível provar sem
acesso ao firmware, que é caixa-preta de terceiro. **Não foi tentada
reprodução deliberada** — o custo de errar (fans paradas sob carga) não
compensa.

**Mitigação aplicada:** o "ligar" passou a ser reafirmado a cada
`ON_REASSERT_SECONDS` = **5 min** (em vez de 10s), separado do
`DEFAULT_REASSERT_SECONDS` = 2 min usado no lado "apagado". Redução de ~30x no
tráfego. **Ainda não houve sessão longa de jogo suficiente para validar essa
mitigação.**

### 2026-07-29 (16:48) — Perda de sync após reboot NORMAL ⚠️ (problema atual)

Reboot comum (`systemctl reboot`, shutdown limpo registrado nos logs, sem
corte de energia). Depois dele o hub voltou ao Rainbow autônomo e **ficou
assim por mais de 2 horas**.

**A evidência mais importante deste documento:**

```
jul 29 16:49:05  Started gpu-rgb-sync.service
jul 29 16:49:07  GPU ativa - LEDs ligados (branco estatico)
jul 29 18:57:40  GPU ociosa ha 60s - LEDs apagados
jul 29 19:01:05  GPU ativa - LEDs ligados (branco estatico)
```

O script manteve o header em **branco por 2h08min contínuos** (16:49 → 18:57)
e o hub continuou em Rainbow o tempo todo.

Timing do boot (relevante para as hipóteses H1/H3):

```
jul 29 16:49:04  Started openrgb.service
jul 29 16:49:04  [i2c_smbus_linux] Failed to read i2c device PCI device ID   (ruído normal do amdgpu)
jul 29 16:49:05  Started gpu-rgb-sync.service
jul 29 16:49:07  GPU ativa - LEDs ligados     <- primeiro comando do host ao header
```

Ou seja: entre o corte de energia do reset e as 16:49:07 existe uma janela de
**dezenas de segundos** (POST + boot + subida dos serviços) em que o header
não recebe nenhum comando do host. É nessa janela que o hub provavelmente sai
do sync.

**Conclusões diretas:**
1. Uma vez fora do modo M/B Sync, o hub **ignora sinal válido, contínuo e
   correto** no header. Não existe "re-sincronizar por software". A saída do
   modo é, na prática, **irreversível sem o botão físico**.
2. A perda de sync **não é exclusiva de queda de energia total** — como estava
   documentado até então. Um reboot limpo bastou.
3. Mas **não é determinística**: os reboots de 2026-07-28 (12:50 e 12:59)
   preservaram o sync (os fans acenderam normalmente depois deles). Só este
   perdeu. **Por que uns sim e outros não é uma questão em aberto.**

Ver [`logs/incidente-2026-07-29-perda-sync-pos-reboot.log`](logs/incidente-2026-07-29-perda-sync-pos-reboot.log).

---

## 6. Hipóteses em aberto, ranqueadas

### H1 — `-m off` mata o stream ARGB e o hub cai para o modo autônomo ⭐ testar primeiro

O script usa `openrgb -d "$MB_DEVICE" -m off` para apagar. Se o modo `Off` do
Aura **para de clockar dados** no header (em vez de enviar pixels pretos), o
hub passa a ver uma linha de dados morta. Muitos hubs com "M/B sync" caem para
o efeito interno após N segundos sem dados — e o design atual deixa o header
mudo na maior parte do tempo (ocioso = apagado), além da janela de POST/boot.

**Verificado:** `Off` e `Static preto` são estados distintos no controlador —
o OpenRGB reporta `[Off]` num caso e `[Static]` no outro. O comando alternativo
é aceito sem erro:

```bash
openrgb -d "ASUS" -z 3 -sz 40 -c 000000 -m static   # aceito, fica em [Static]
openrgb -d "ASUS" -m off                            # fica em [Off]
```

**Teste proposto:** trocar `leds_apagar()` para usar `static` com `000000` (ou
o modo `Direct`, que é streaming contínuo do host) em vez de `off`.
Visualmente idêntico (LEDs apagados), mas mantém a linha de dados viva.
Depois: reboot algumas vezes e ver se o sync sobrevive.

**Atenção ao interpretar:** o fato de o hub ter ignorado 2h de branco **não
refuta H1**. H1 explica *quando* ele sai do sync (janelas sem dado), não se
ele volta sozinho — provavelmente a volta só acontece pelo botão.

**Risco:** manter stream contínuo aumenta o tráfego ao hub — exatamente o que
se suspeita ter travado o firmware em 07-29. Se for testar o modo `Direct`,
tomar cuidado com a frequência de atualização.

### H2 — O estado "M/B Sync" é volátil no hub (RAM, não EEPROM)

Se o hub guarda o modo só em RAM, **qualquer** perda de alimentação dele volta
ao padrão de fábrica (autônomo). Explica todas as observações, inclusive a
não-determinismo entre reboots (depende de o rail que alimenta o hub cair ou
não naquele reboot específico — reboot quente costuma manter os rails, mas
firmware/BIOS pode fazer ciclo completo).

**Se H2 for verdade, nenhum software resolve.** As saídas seriam as da seção 7.

**Teste:** desligar só o cabo de alimentação do hub com o PC ligado é
arriscado; melhor: em desligamento normal (não corte de tomada), verificar se
o LED de standby do hub apaga. Ou medir com o BIOS configurado para manter
iluminação em S5 (ver H3) e comparar.

### H3 — Configuração de Aura no BIOS/UEFI

Placas ASUS têm opções de iluminação que afetam o header em POST/S3/S5
(ex.: "RGB Lighting", "When system is in sleep/hibernate/soft off state").
Se o header ficar sem alimentação ou sem dado durante o POST, o hub pode
resetar para autônomo já ali.

**Teste:** entrar no BIOS, ativar as opções que mantêm a iluminação ligada em
S5/sleep, e ver se o sync passa a sobreviver a reboots. Barato e reversível.

### H4 — Não-determinismo entre reboots

Fato não explicado: reboots de 07-28 preservaram o sync; o de 07-29 não.
Variáveis candidatas: reboot quente vs. frio, tempo de POST, se o hub estava
no modo M/B há muito ou pouco tempo, ordem de subida do `openrgb.service`.

**Sugestão:** instrumentar — depois de cada boot, registrar automaticamente se
o hub está obedecendo. Como não há telemetria do hub (ver seção 8), isso exige
confirmação visual humana; um jeito seria um script que pergunta/registra.

---

## 7. Recomendação de engenharia (opinião, para decisão do dono)

O hub Rise Mode é um hub **ativo**: tem microcontrolador próprio, efeitos
autônomos e receptor infravermelho. Toda a dor deste projeto vem daí — modo
que se perde, botão físico obrigatório, firmware que trava e para as fans.

Se H1 e H3 não resolverem, a solução real provavelmente é de hardware:

**Trocar o hub ARGB ativo por um splitter ARGB passivo.** Um splitter passivo
não tem microcontrolador, não tem modo autônomo, não tem controle remoto e não
tem firmware para travar — ele só replica eletricamente o sinal do header da
placa-mãe. Consequências:

- Fim da classe inteira de problemas: nunca sai de sync, nunca precisa de
  botão, não pode travar e parar as fans.
- Perde-se o controle remoto IR (que já é irrelevante aqui, já que o objetivo
  é controle por software).
- **Atenção à alimentação das fans:** o hub atual também distribui energia/PWM
  para os motores. Um splitter ARGB passivo cobre **só o ARGB** — seria
  preciso manter um hub de energia/PWM separado (ou um hub que seja passivo no
  lado ARGB).
- **Atenção ao limite de corrente do header** da placa-mãe (headers ARGB Gen2
  da ASUS costumam ser 5V / 3A). 8 fans + water cooler podem passar disso; um
  splitter passivo não amplifica corrente. Calcular antes de comprar.

Alternativa: um hub cujo controlador seja **diretamente endereçável** por
USB/SMBus e suportado pelo OpenRGB (aí o software fala com o hub, não com o
header da placa-mãe, e o problema de "modo sync" deixa de existir).

---

## 8. Limitações que nenhum software resolve

- **Não existe telemetria de RPM para as fans do hub.** Os únicos sensores de
  fan expostos pelo sistema são da GPU (`amdgpu`, `fan1`). Não há
  `nct6775`/`it87` carregado que exponha os headers da placa. Consequência
  direta: **é impossível detectar "fans pararam" por software.** Depende de
  checagem física/auditiva — o que é ruim, porque foi exatamente esse o modo
  de falha perigoso de 07-29.
- **O firmware do hub é caixa-preta.** Não loga, não expõe estado, e o host
  não enxerga nada do que acontece dentro dele. Toda causa raiz nesse
  componente vai ser inferência a partir de sintoma, nunca prova direta.

---

## 9. Referência rápida de comandos

```bash
# Estado dos serviços
systemctl --user status gpu-rgb-sync.service
systemctl status openrgb.service

# Logs do script
journalctl --user -u gpu-rgb-sync.service -f

# Inventário de dispositivos e zonas
openrgb --list-devices

# Tamanho atual da zona 3
openrgb --list-devices | grep -o "'Aura Addressable 3, LED [0-9]*'" | wc -l

# Forçar branco / apagar (zona 3 = hub + water cooler)
openrgb -d "ASUS" -z 3 -sz 40 -c FFFFFF -m static
openrgb -d "ASUS" -m off

# Carga atual da GPU
cat /sys/class/drm/card1/device/gpu_busy_percent

# Temperaturas (checagem de segurança se as fans pararem)
sensors
```

### Procedimento quando o hub para de responder

1. `systemctl --user stop gpu-rgb-sync.service`
2. **Evitar carga pesada** (jogo, LLM, render) até resolver.
3. Testar o controle remoto do hub. Se **nenhum** botão funcionar, o
   microcontrolador travou — não há correção por software.
4. PC desligado → desconectar só o cabo de alimentação (SATA/Molex) do hub
   por ~30s → reconectar → ligar.
5. O hub volta em Rainbow autônomo. Com o serviço rodando (header com sinal
   válido), apertar `ON M/B` no controle.
6. Confirmar: abrir uma carga de GPU e ver se acende branco.

---

## 10. Histórico de mudanças no script

| Quando | Mudança | Motivo |
|---|---|---|
| 2026-07-28 | Rainbow → branco estático | Preferência visual, comparado com o hardware à vista |
| 2026-07-28 | Passou a controlar a zona 3 (`-z 3 -sz 40`) | Antes o script só tocava device inteiro; a zona 3 estava com tamanho 0 e nunca acendia |
| 2026-07-28 | "Ligar" reaplicado a cada ciclo (10s) | Corrigir corrida de boot (RAMs ligavam, fans não) |
| 2026-07-29 | Reduzido `DEFAULT_REASSERT_SECONDS` 300s → 120s | Pedido do dono; sem risco (só reenvia o mesmo estado, não é transição) |
| 2026-07-29 | "Ligar" voltou a ser periódico, não a cada ciclo | **Suspeita de ter travado o hub.** Introduzido `ON_REASSERT_SECONDS` = 300s, separado do lado "apagado" (120s) |

Parâmetros atuais (sobrescrevíveis por variável de ambiente no `ExecStart`):

| Variável | Valor | Função |
|---|---|---|
| `DEBOUNCE_SECONDS` | 60 | Tempo de GPU ociosa até apagar |
| `DEFAULT_REASSERT_SECONDS` | 120 | Reafirmação do estado "apagado" |
| `ON_REASSERT_SECONDS` | 300 | Reafirmação do estado "ligado" (mais conservador de propósito) |
| `SLEEP_SECONDS` | 10 | Intervalo do laço |
| `UTIL_THRESHOLD_PCT` | 1 | Limiar de uso de GPU para "ativa" |
| `POWER_THRESHOLD_W` | 25 | Limiar de potência (só NVIDIA; não usado no AMD) |

---

## 11. Resumo para quem vai continuar

**Não é um bug de software.** O script faz o que promete e é verificável nos
logs. O componente que falha é o hub ARGB ativo do gabinete, cujo firmware:

1. perde o modo "M/B Sync" em eventos de energia/reboot, de forma não
   determinística;
2. uma vez fora do sync, **ignora sinal válido contínuo** (provado: 2h08min de
   branco ignorado);
3. só volta pelo botão físico `ON M/B` no controle IR;
4. e pelo menos uma vez travou por completo, **parando as fans** — que é um
   risco térmico real, não cosmético.

**Ordem sugerida de ataque:** H1 (trocar `off` por `static 000000` — barato,
rápido, plausível) → H3 (BIOS) → confirmar fisicamente a topologia real da
fiação (seção 3) → se nada resolver, decisão de hardware (seção 7).
