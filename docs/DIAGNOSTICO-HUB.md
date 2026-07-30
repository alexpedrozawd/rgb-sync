# Diagnóstico: o hub de fans não mantém o modo "M/B Sync"

**Documento de handoff.** Escrito em 2026-07-29 para uma sessão nova, sem
contexto prévio. Reúne tudo que foi medido, o que foi só inferido, os
incidentes reais e as hipóteses ainda em aberto.

Leia junto com o [`README.md`](../README.md) (manual de uso) e o
[`rgb-branco.sh`](../rgb-branco.sh) (comentários no topo do arquivo).

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

## 2. Estado atual (2026-07-30 01:30)

| Item | Estado |
|---|---|
| `openrgb.service` (sistema) | `active` + `enabled` |
| `rgb-branco.service` (usuário) | `active` + `enabled` |
| Zona 3 (`Aura Addressable 3`) | 40 LEDs, preservado através de reboots |
| RAMs (2x `ENE DRAM`) | Obedecem normalmente |
| Water cooler (2 fans do radiador) | Obedecem normalmente |
| 8 fans do gabinete (hub Rise Mode) | **De volta ao M/B Sync**, obedecendo |
| Estado dos LEDs | `FFFFFF` **permanente**, 24/7 |
| Sincronia com a GPU | **removida do projeto** em 2026-07-30 |

**Atenção ao ler este documento:** ele foi escrito em 2026-07-29 e depois
corrigido em pontos específicos. As correções estão marcadas onde ocorrem. As
maiores: **H1 refutada** (seção 6), **topologia e os "40 LEDs" sem base**
(seção 3), e **splitter passivo provavelmente inviável** (seção 7).

> **Nota sobre o hub voltar ao sync:** ele voltou, mas isso **não** invalida nada
> aqui — a volta é sempre pelo botão `ON M/B`, nunca sozinha. O problema em
> aberto é a próxima perda, não a recuperação.

### O projeto foi redesenhado em 2026-07-30 — o que isso muda aqui

A sincronia com a GPU saiu. Os LEDs ficam em branco permanente. Decisão de
preferência do dono, mas com três consequências diretas para este diagnóstico:

1. **O cenário de 2026-07-27 (seção 5) deixa de ser alcançável em operação
   normal.** O header nunca fica mudo, então apertar `ON M/B` nunca cai na
   condição que travou o host — a não ser que o serviço esteja parado.
2. **A hipótese de "firmware afogado em comando" (seção 5) fica mitigada até o
   limite prático.** Sem transições, o tráfego no header cai para **2 escritas
   por hora**, contra ~6 por *minuto* na janela do travamento. ~180x menos.
3. **A hipótese de corrente (seção 5) fica PIOR.** Branco pleno é o estado de
   corrente máxima do array e agora é permanente, não só sob carga.

E abre um teste que **nunca foi possível antes**:

> No desenho antigo, a primeira ação de todo boot era *apagar* — o header ficava
> mudo pelos primeiros ~30 segundos de cada boot, e só então recebia o primeiro
> comando. Agora ele carrega branco válido desde o POST.
>
> Se o hub decide o modo dele **no próprio power-on**, conforme haja ou não sinal
> válido na linha naquele instante — design comum nessa classe de hub —, esse é o
> único arranjo com chance real de o M/B Sync sobreviver a um reboot. **Não é uma
> previsão, é uma hipótese testável que a configuração anterior impedia de
> testar.** O próximo reboot responde.
>
> Se o modo simplesmente mora em RAM e some a cada queda de alimentação do hub
> (H2), nada disso ajuda e o botão continua obrigatório.

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

### Medido em 2026-07-29 (corrige o que estava escrito acima)

O que responde na zona 3 e obedece são as **2 fans do radiador** do Pichau Aqua
240X — não "o water cooler" genericamente. Confirmado com o hardware à vista,
com o hub fora de sync (o que isola o cooler: só ele responde).

**O número 40 não tem base, e o método original não podia medir nada.** Com cor
única, "acendeu tudo uniforme sem ponta apagada" dá falso positivo em qualquer
tamanho — o teste não pode falhar. Medindo de verdade (zerar a zona toda em
`static 000000` com `-sz 40`, e depois mandar branco com a zona encolhida):

| Comando | Resultado observado |
|---|---|
| `-sz 10 -m static -c FFFFFF` | as 2 fans do cooler acenderam **inteiras** |
| `-sz 1 -m static -c FFFFFF` | as 2 fans do cooler acenderam **inteiras** |

Acender inteiras com **1** LED endereçado é impossível numa cadeia simples de 40
LEDs. Duas explicações cabem e o CLI do OpenRGB **não as separa**:

- **(a)** o controlador Aura replica a cor única em todo o quadro quando a zona
  é menor que a cadeia física; ou
- **(b)** o que está na zona 3 não é cadeia crua — há elemento ativo que consome
  o quadro e replica a cor nos LEDs dele.

Em qualquer das duas, `FAN_ZONE_SIZE=40` **não corresponde a contagem física**.
Funciona na prática; não é medição. Para separar (a) de (b) seria preciso um
padrão com fronteira visível, e o CLI não entrega: `-c` com lista de cores só
vale sem efeito, e `-m direct` **apaga o header** neste hardware.

### O que continua ASSUMIDO, não medido

1. **A contagem de LEDs por fan do gabinete.** É contagem visual dos pontos no
   anel de **uma** fan × 8, mais o cooler. Decide o orçamento de corrente do
   header e, com ele, se splitter passivo é opção (ver seção 7).
2. **A forma da ligação não foi confirmada visualmente.** Sabe-se que o cooler
   **não** está a jusante do hub — ele continua obedecendo o header enquanto o
   hub roda o Rainbow autônomo, e se o sinal passasse *através* do hub o cooler
   herdaria o Rainbow. Mas isso não distingue **splitter em paralelo** de
   **cooler primeiro, em série**. Só olhando o cabo resolve, e isso muda as
   opções de solução.

---

## 4. O que funciona de forma confiável (não mexer)

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
- RAM e fans do cooler: obedecem cor e modo de forma 100% previsível.

> A detecção de carga de GPU (`gpu_busy_percent` via sysfs do `amdgpu`) e a
> detecção automática de backend NVIDIA/AMD **saíram do projeto** em 2026-07-30,
> junto com a sincronia. Funcionavam e estão no histórico do git. O único defeito
> que tinham era o limiar herdado da NVIDIA — ver seção 5, 2026-07-30.

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

**⚠️ Hipótese concorrente, com correlação EXATAMENTE IGUAL (2026-07-29):** essa
mesma janela de 19 minutos foi, simultaneamente, o maior período contínuo de
**`FFFFFF` — branco pleno, o estado de corrente máxima possível** de todo o
array. Os dois candidatos são indistinguíveis pela correlação:

| Candidato | O que a janela 09:46→10:05 era |
|---|---|
| Firmware afogado em comando | a maior sequência de comandos repetidos do dia |
| Regulador do hub em estresse térmico | o maior período contínuo de corrente máxima |

Com ~60 mA por LED em branco pleno, o hub estava sustentando alguns ampères pelo
regulador dele por 19 minutos seguidos. Regulador em estresse prolongado é causa
tão plausível quanto comando em excesso — e o diagnóstico original só considerava
a segunda.

**Mitigação tentada em 2026-07-29 e REVERTIDA em 2026-07-30.** `LED_COLOR` passou
de `FFFFFF` para `A0A0A0` (A0 = 160/255 ≈ 63% de duty, ~37% menos corrente) e
voltou para `FFFFFF`.

Motivo da reversão, e vale registrar porque não era óbvio: **cinza neutro
(R=G=B) nesse hardware não dá "branco mais suave", dá branco AMARELADO.** Em LED
WS2812 o die azul perde eficiência em duty reduzido antes dos outros dois, então
o branco puxa pro quente. Reportado pelo usuário olhando o hardware. O ganho
estético era negativo, e a hipótese que isso mitigava é a fraca das duas
(especulação correlacional, 1 incidente), enquanto a de excesso de comando foi
corrigida de verdade.

> **Estado atual: não existe mitigação de corrente, só a de frequência.** Em
> sessão longa de carga pesada, vale checagem física das fans. E se um dia quiser
> as fans do gabinete menos ofuscantes, o caminho **não é a cor** — é o botão de
> brilho do controle IR do hub.

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

### 2026-07-30 — LEDs acendendo sozinhos em idle (bug meu, corrigido)

Reportado pelo usuário: "de tempos em tempos, talvez 5 minutos, tudo acende do
nada, sem atividade na GPU". Não era novo — sempre esteve lá, só não tinha sido
notado.

**Causa, medida:** amostrando `gpu_busy_percent` a 1Hz por 4 minutos com a
máquina parada:

```
0% -> 236 amostras
1% ->   4 amostras   @ 01:25:00, 01:26:00, 01:27:00, 01:28:00
```

Algo dispara **uma vez por minuto, exatamente no segundo `:00`**, e produz um
pico de 1% que dura menos de 1 segundo. O `UTIL_THRESHOLD_PCT=1` era herdado da
NVIDIA ("idle ~0%, qualquer utilização > 0% conta"), então `1 >= 1` era
verdadeiro e o pico virava "GPU ativa" — acendendo tudo pelos 60s do debounce.

**É um artefato de aliasing.** O laço amostra a cada 10s, então pegava o pico por
coincidência de fase, ~1 vez a cada 10 min. Isso explica os intervalos
irregulares (1min25s a 19min) e por que as ligadas espúrias caem sempre no mesmo
segundo do minuto nos logs — é a fase do laço, não atividade. No log histórico:
**~50 ligadas entre 00:00 e 04:15 de 2026-07-29**, com a máquina sozinha.

**Corrigido em duas frentes:** limiar para 10% (10x de margem sobre o teto
medido) e `ACTIVATION_SAMPLES=2`. A segunda é a correção estrutural — o limiar é
calibração que envelhece (outra GPU, outro compositor, outra tarefa de fundo),
enquanto exigir duas amostras consecutivas mata a classe inteira de "pico de 1
amostra" seja qual for a magnitude: um pico de <1s não aparece em duas amostras
separadas por 10s.

**Validado com a GPU simulada** (stub de `openrgb` + arquivo de sysfs falso, com
o script real): a configuração antiga reproduz o bug, a nova não acende com os
picos, carga real continua acendendo, e queda instantânea no meio da carga não
apaga. Um teste que passasse nas duas configurações não valeria nada.

---

## 6. Hipóteses em aberto, ranqueadas

### H1 — `-m off` mata o stream ARGB e o hub cai para o modo autônomo ❌ REFUTADA (2026-07-29)

> **Não perca tempo aqui.** A hipótese era: se o modo `Off` do Aura para de
> clockar dados, o hub vê uma linha morta e cai para o efeito interno após N
> segundos sem dados.
>
> **A evidência nos logs deste repositório refuta isso.** Na manhã de
> 2026-07-29 o header ficou em `Off` por **54min58s** seguidos:
>
> ```
> jul 29 07:37:06  GPU ociosa ha 60s - LEDs apagados.     <- header em Off
> jul 29 08:32:04  GPU ativa - LEDs ligados (branco...)   <- 54min58s depois
> ```
>
> E o hub **continuou obedecendo** depois disso: às 09:46:07 acendeu **branco**,
> que é a cor que só o script manda — um hub em Rainbow autônomo não pode
> mostrar branco. (O travamento das 09:46–10:05 aconteceu justamente com os LEDs
> em branco, o que só é possível se ele estava obedecendo o header.)
>
> A janela de silêncio de dados **do reboot que derrubou o sync** foi 16:47:57 →
> 16:49:07 = **70 segundos**. Mesmo contando que o reassert de `off` a cada 120s
> produza quadro, o silêncio máximo em idle (120s) ainda é maior que 70s.
>
> **O hub tolerou 55 minutos sem dado e voltou a obedecer; caiu numa janela de
> 70 segundos, num reboot.** Ausência de sinal não é o gatilho — em nenhuma
> variante da hipótese. Isso elimina toda a família "o hub caiu por falta de
> dado", não só a formulação com `-m off`.

Registro do que era a hipótese e do que se aprendeu testando:

**Verificado:** `Off` e `Static preto` são estados distintos no controlador —
o OpenRGB reporta `[Off]` num caso e `[Static]` no outro. O comando alternativo
é aceito sem erro:

```bash
openrgb -d "ASUS" -z 3 -sz 40 -c 000000 -m static   # aceito, fica em [Static]
openrgb -d "ASUS" -m off                            # fica em [Off]
```

**Aplicado mesmo assim, por outro motivo:** `leds_apagar()` passou a usar
`static 000000` no dispositivo Aura em vez de `off`. **Não é a correção do
sync** — é trava de segurança do botão: com o header nunca em `Off`, apertar
`ON M/B` nunca cai no cenário que travou o PC inteiro em 2026-07-27. O
`RAM_DEVICE` continua em `off` de propósito (as RAMs sempre funcionaram).

**⚠️ O modo `Direct` NÃO serve — medido em 2026-07-29.** Um único
`openrgb -d "ASUS" -z 3 -m direct -c <lista>` deixou as fans do water cooler
**apagadas**. Um frame em modo Direct não fica retido neste hardware; ele
precisaria de streaming contínuo do host, que é exatamente o padrão de tráfego
sob suspeita de ter travado o firmware do hub. Descartado nas duas pontas.

**O que sobra de pé depois de refutar H1:** só duas causas, ambas do lado do
hardware e ambas fora do alcance de qualquer código do SO, porque acontecem
antes de o SO rodar:

- **(A)** o hub perdeu alimentação nesse reboot → o modo mora em RAM (é a H2);
- **(B)** o hub viu a linha em estado inválido enquanto o MCU Aura era resetado
  no POST e desistiu sozinho.

Um dado fraco contra (A): o intervalo entre última e primeira entrada do journal
foi **idêntico** nos três reboots (15s, 16s, 16s) — nenhum sinal de ciclo
completo de rails no que falhou.

**Teste que separa (A) de (B), custo zero:** rebootar olhando as fans do
gabinete. Se elas **param e voltam a girar**, o hub perdeu alimentação → (A). Se
continuam girando, → (B).

**Hipótese mais simples que esta seção não considerava:** talvez a
não-determinismo de H4 **não exista**. As duas evidências de "reboot preservou o
sync" são de 2026-07-28 12:50 e 12:59, mas o commit que introduziu `-z 3 -sz 40`
é de 13:13:24 — não se sabe qual era o estado da zona 3 naqueles dois reboots.
Se eles nunca preservaram sync de verdade, a história fica trivial: **todo
reboot quebra o sync, sempre**, e é 100% hardware. Um reboot observado resolve.

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

**H1 está refutada** (seção 6) e o veredito de software é: nenhuma mudança no
que o host escreve no header preserva ou restaura o modo M/B Sync. A solução é
de hardware. O erro de arquitetura é o hub fazer **dois trabalhos** num único
microcontrolador de terceiro sem telemetria: distribuir energia/PWM dos motores
**e** decidir o modo ARGB. Separar os dois resolve as duas dores.

### Orçamento de corrente do header — fecha a questão do splitter passivo

Confirmado no manual da ASUS: o header **Addressable Gen 2** é **5V / máx 3A**,
e os headers endereçáveis da placa somam no máximo 500 LEDs. Um WS2812B puxa
~60 mA em branco pleno, então:

```
3000 mA / 60 mA por LED = ~50 LEDs no teto do header, em FFFFFF
```

Hoje isso não é problema porque a alimentação dos LEDs vem do **Molex do hub**,
não do header — o header só entrega dado. **Um splitter ARGB passivo joga toda
essa corrente no header**, porque não tem alimentação própria: é só cobre.

Com 8 fans, dependendo da contagem por fan (ainda não medida, ver seção 3),
o total fica plausivelmente **acima** dos 50 LEDs. Conclusão:

> **Splitter passivo: provavelmente inviável em branco pleno.** Não é
> alternativa a considerar antes de contar os LEDs. Com cor mais fraca poderia
> entrar no orçamento, mas fica uma solução que depende de nunca subir o brilho.
> **O caminho correto é um controlador com alimentação própria, não um divisor
> passivo.**

Nota relacionada: `LED_COLOR` é `FFFFFF`, o **estado de corrente máxima possível**
de todo o array — a tentativa de usar `A0A0A0` foi revertida em 2026-07-30 (ver
seção 5). Então o teto de ~50 LEDs vale como está, e o splitter passivo segue
provavelmente inviável. Depende da contagem que falta (seção 3).

### Nível 1 — resolve a classe inteira e fecha o buraco de segurança

**Iluminação:** controlador ARGB com saídas padrão 3 pinos 5V que o OpenRGB
dirija direto, sem passar pelo header da placa. **Cuidado:** Corsair, NZXT e
Lian Li usam conector RGB **proprietário** nos fans — nenhum deles acende fans
Rise Mode genéricas. As opções reais são um controlador genérico de 8 portas
ARGB com USB interno (tipo "OpenRGB/SignalRGB certified"), ou **ESP32 com
firmware WS2812 falando E1.31**, que o OpenRGB suporta via config manual no
`OpenRGB.json`. Antes de comprar, conferir o modelo exato na lista de
dispositivos suportados do OpenRGB.

**Motores + RPM:** **Corsair Commander Pro** ou **Commander Core XT**. O que
importa: as portas de **fan** são 4 pinos PWM padrão, funcionam com qualquer
ventoinha. São 6 portas, e o `liquidctl` lê **RPM por porta** no Linux (Core XT
suportado desde a 1.11.0). Com 8 fans, dois pares vão em Y: perde-se RPM
individual nesses, mantém-se a detecção de "está girando".

Isso é o único caminho que fecha o buraco que **nenhum software fecha hoje** —
uma fan parada é invisível ao sistema (seção 8), e foi exatamente esse o modo de
falha perigoso de 2026-07-29.

### Nível 2 — mais barato, mata a chatice do botão, não o risco térmico

**Blaster IR automático.** O hub tem receptor infravermelho. Um ESP32 com LED IR
disparando o código do `ON M/B` a cada boot — **só depois** do header ter branco
válido confirmado, o que elimina o cenário de 2026-07-27 por construção. Mantém
todo o hardware atual.

Dois pré-requisitos: capturar o código IR do controle (exige um receptor para
aprender), e descobrir se o `ON M/B` é **toggle** — se for, disparar com o hub já
em sync o tiraria do sync.

**Não resolve o travamento do firmware nem as fans paradas.** É conveniência,
não segurança.

### Ganho barato, independente de tudo

A placa tem **3 headers ADD_GEN2 e dois estão livres.** Mover o water cooler para
um header próprio dá controle independente dele no OpenRGB, tira o cooler do
destino do hub e divide a carga. Vale em qualquer cenário.

### O que NÃO fazer sem análise de impacto

Habilitar `nct6775` para tentar expor os fan headers da placa exige parâmetro de
kernel (`acpi_enforce_resources=lax`). É mudança global num sistema ostree —
exige análise de impacto antes de qualquer comando.

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
systemctl --user status rgb-branco.service
systemctl status openrgb.service

# Logs do script
journalctl --user -u rgb-branco.service -f

# Inventário de dispositivos e zonas
openrgb --list-devices

# Tamanho atual da zona 3
openrgb --list-devices | grep -o "'Aura Addressable 3, LED [0-9]*'" | wc -l

# Forçar branco / apagar (zona 3 = hub + water cooler)
openrgb -d "ASUS" -z 3 -sz 40 -c FFFFFF -m static   # cor atual do estado "ligado"
openrgb -d "ASUS" -m static -c 000000               # "apagado" atual (NAO usar -m off)

# Antes de apertar o botao ON M/B, force branco PLENO e confirme visualmente --
# e a condicao comprovada segura (2026-07-28). Com a zona sem sinal o botao
# travou o PC inteiro em 2026-07-27.
openrgb -d "ASUS" -z 3 -sz 40 -c FFFFFF -m static

# Carga atual da GPU
cat /sys/class/drm/card1/device/gpu_busy_percent

# Temperaturas (checagem de segurança se as fans pararem)
sensors
```

### Procedimento quando o hub para de responder

1. `systemctl --user stop rgb-branco.service`
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
| 2026-07-29 | `leds_apagar` usa `static 000000` no Aura em vez de `-m off` | H1 (refutada como correção do sync); mantido como trava de segurança do botão `ON M/B` |
| 2026-07-29 | `leds_ligar` manda **1** comando ao Aura em vez de 2 | O comando no dispositivo inteiro já cobre a zona 3; o da zona era redundante para cor e só existia pelo `-sz`. Metade das escritas no header |
| 2026-07-29 | Tamanho da zona só é reescrito se uma **leitura** mostrar que está errado | Antes redimensionava a zona a cada reafirmação (12x/hora em jogo). Resize reconfigura o canal do header, é mais invasivo que trocar cor. Leitura como cliente custa 0,04s |
| 2026-07-29 | `LED_COLOR` de `FFFFFF` para `A0A0A0` | Mitigar a hipótese de corrente. **Revertido em 2026-07-30** |
| 2026-07-30 | `LED_COLOR` de volta para `FFFFFF` | Cinza neutro dá branco **amarelado** nesse hardware (die azul perde eficiência em duty baixo). Ganho estético negativo, e a hipótese mitigada é a fraca das duas |
| 2026-07-30 | `UTIL_THRESHOLD_PCT` de 1 para 10, e `ACTIVATION_SAMPLES=2` | **Bug real:** idle da RX 9070 tem pico de 1% uma vez por minuto no segundo `:00`; com limiar 1 isso acendia tudo por 60s+, ~50x por noite. Ver seção 5 |
| 2026-07-30 | `UTIL_THRESHOLD_PCT` e `POWER_THRESHOLD_W` viraram sobrescrevíveis por env | O README dizia que eram, mas no script eram atribuições fixas — a variável era ignorada em silêncio |
| 2026-07-30 | **Redesenho completo.** `gpu-rgb-sync.sh` → `rgb-branco.sh`; sincronia com a GPU REMOVIDA; branco permanente 24/7 | Preferência do dono. De quebra: header nunca mudo, tráfego de 2 escritas/hora, e abre o teste de sync no POST que a configuração antiga impedia |

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

**Atualização 2026-07-29 (segunda sessão) — o que mudou neste documento:**

- **H1 está REFUTADA** pelos próprios logos daqui: o header ficou em `Off` por
  54min58s e o hub continuou obedecendo. Ausência de sinal não é o gatilho.
  Aplicada de todo modo, mas como trava de segurança do botão, não como
  correção do sync.
- **Modo `Direct` descartado:** medido, apaga o header neste hardware.
- **Topologia corrigida:** o que obedece na zona 3 são as 2 fans do radiador do
  cooler; o cooler não está a jusante do hub. E **`40 LEDs` não tem base** — o
  método original não podia medir nada (seção 3).
- **Splitter passivo provavelmente inviável** pelo orçamento de 3A do header
  (seção 7). A solução precisa de alimentação própria.
- **Hipótese nova para o travamento:** corrente sustentada em branco pleno, com
  correlação idêntica à do excesso de comando (seção 5).
- **Redução de tráfego aplicada no script:** uma escrita por dispositivo por
  reafirmação em vez de duas, e o tamanho da zona só é reescrito se uma leitura
  mostrar que está errado — antes redimensionava a zona em toda reafirmação.

**Ordem sugerida de ataque, revisada em 2026-07-30:**

1. **Reboot observado, agora no desenho de branco permanente.** Duas perguntas
   num único reboot, custo zero:
   - **Durante** o reboot, os LEDs das 8 fans ficam completamente escuros em
     algum instante? Escuro = o hub perdeu alimentação → (A)/H2, o modo é
     volátil e nenhum software resolve. Nunca escuro = o hub manteve energia
     → (B).
   - **Depois** do boot, as 8 fans voltam brancas ou em Rainbow? Brancas = o
     header carregando branco desde o POST preservou o sync, e o problema
     acabou. Rainbow = o botão continua obrigatório.
2. **Contar os LEDs de uma fan** (visual, gabinete aberto) — fecha o orçamento
   de corrente e decide se splitter passivo é opção.
3. **Traçar o cabo** do header (splitter em paralelo vs. cooler em série).
4. **Persistir branco no próprio controlador Aura**, para o header acender já no
   POST sem depender do SO. Dois caminhos, os dois não testados: opção de Aura no
   BIOS/UEFI (o manual desta placa não enumera opções de BIOS, então só olhando
   se sabe), ou "salvar no dispositivo" pela GUI do OpenRGB — o CLI **não** tem
   flag de save (`-sp/--save-profile` grava um arquivo de perfil, não no
   hardware). Se funcionar, é o estado ideal: o header branco desde o instante do
   POST, e possivelmente sem serviço nenhum.
5. **Decisão de hardware** (seção 7).

Notas de tentativas encerradas: `A0A0A0` em vez de `FFFFFF` foi tentado em
2026-07-29 e **revertido** em 2026-07-30 (cinza neutro dá branco amarelado nesse
hardware — seção 5). Modo `Direct` **descartado**: apaga o header (seção 6).
