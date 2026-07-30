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

## Hardware coberto

| Componente | Modelo |
|---|---|
| Placa-mãe | ASUS PRIME B760M-A D4 |
| Hub de fans (8x, gabinete) | Rise Mode Galaxy Glass Standard V2 |
| Water cooler | Pichau Aqua 240X (2 fans de radiador na zona ARGB) |
| RAM | 2 pentes com controlador "ENE DRAM" |

**Topologia ARGB — o que está medido:** a placa expõe 4 zonas Aura ("Aura
Mainboard" + "Aura Addressable 1/2/3") e só a zona 3 tem algo conectado; 1 e 2
estão vazias. Na zona 3 respondem as 2 fans do radiador do cooler (sempre
obedecem) e o hub das 8 fans (obedece só em "M/B Sync").

O cooler **não está a jusante do hub** — continua obedecendo o header enquanto o
hub roda o Rainbow autônomo dele. Mas isso não distingue *splitter em paralelo*
de *cooler primeiro, em série*: a fiação nunca foi conferida visualmente.

> ⚠️ **`FAN_ZONE_SIZE` não tem efeito observável entre 1 e 120 — medido.** O 40
> veio de subir `-sz` até "acender tudo uniforme, sem ponta apagada", mas com
> **cor única esse teste não pode falhar**: qualquer tamanho parece certo.
> Medindo depois: com a zona em **1** as fans do cooler acendem **inteiras**, e
> com **120** (aceito pelo controlador, 3x o valor em uso) **nada acende a mais em
> nenhum dispositivo**. Qualquer valor ≥ 1 serve.
>
> O único valor que demonstravelmente importa é **`0`** — aí nada acende e o
> header fica mudo, que foi o contexto do travamento de 2026-07-27. É por isso
> que a rede de segurança contra "queda de energia zerou o tamanho" continua no
> script, embora o valor exato não importe.

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
   rodar `rpm-ostree install openrgb` (cria uma camada na imagem ostree e exige
   reboot — o script avisa e para pra você reiniciar e rodar de novo).
3. Restringe o servidor OpenRGB a `127.0.0.1` (o padrão do pacote é `0.0.0.0`,
   ouvindo em todas as interfaces — sem necessidade nenhuma nesse uso).
4. Habilita o `openrgb.service` (nível sistema, roda como root, é quem fala com
   o hardware).
5. Instala e habilita o `rgb-branco.service` (nível usuário).

Em até ~30s tudo deve estar branco.

## Como funciona

O script é praticamente linear:

1. **Rajada de arranque** — aplica branco 4 vezes no primeiro minuto (nos
   segundos 0, 10, 30 e 60). Isso fecha a corrida de boot em que o dispositivo
   Aura ainda não está pronto no OpenRGB quando o serviço sobe (bug real de
   2026-07-28: as RAMs acendiam e o resto ficava apagado porque o único comando
   falhava em silêncio).
2. **Regime** — reafirma branco a cada `REASSERT_SECONDS` (30 min). Existe por
   dois motivos reais: corrigir *drift* (Aura ou RAMs voltando sozinhos ao efeito
   de fábrica, já observado neste projeto) e desfazer qualquer mexida externa
   (GUI do OpenRGB, outro software) em até 30 min.

Duas otimizações que importam para a segurança do hub:

- **Um comando por dispositivo.** No Aura, o comando no dispositivo inteiro já
  cobre a zona 3 — `-c` com cor única replica em todos os LEDs. Não precisa de um
  segundo comando por zona.
- **O tamanho da zona é lido antes de ser reescrito**, e só reescrito se estiver
  errado. A leitura custa ~0,04s como cliente e não escreve nada. Redimensionar
  reconfigura o canal do header, que é mais invasivo que trocar cor.

`REASSERT_SECONDS` e `RAM_COLOR` são sobrescrevíveis por variável de ambiente no
`ExecStart` do `systemd/rgb-branco.service`.

### Por que existem duas cores de "branco"

`FFFFFF` significa "R, G e B no duty máximo" — e isso **não** produz branco
neutro num LED RGB, porque os três dies têm eficiências diferentes e o azul é
tipicamente o mais fraco. O resultado varia por controlador:

| Dispositivo | Cor | Motivo |
|---|---|---|
| Aura (8 fans + 2 do cooler) | `LED_COLOR=FFFFFF` | Branco aceitável a olho |
| RAMs (ENE DRAM) | `RAM_COLOR=D0D0FF` | Em `FFFFFF` saíam visivelmente **amareladas** |

Como o azul já está no máximo, a correção é **baixar R e G** — não há como subir
azul. A calibração é visual e específica deste hardware: se ficar amarelado
ainda, baixe mais (ex. `B0B0FF`); se ficar azulado, suba (ex. `E8E8FF`). Mantenha
o azul em `FF`.

É o mesmo mecanismo que fez a tentativa de usar `A0A0A0` no Aura sair amarelada —
ver "Bugs corrigidos".

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

## ⚠️ Risco conhecido: o hub trava (2 vezes em 4 dias)

**Incidente 1 (2026-07-29), sob sincronia com GPU:** sessão longa de jogo, o
microcontrolador travou — as 8 fans **pararam de girar** e o controle remoto
ficou 100% sem resposta. Risco térmico real.

**Incidente 2 (2026-07-30), já sob branco permanente:** anéis com cor presa e
misturada (branco+rainbow — retenção de frame, não efeito), pás apagadas,
controle remoto de novo 100% sem resposta. **Desta vez as pás continuaram
girando** — sem risco térmico, mas o padrão de MCU travado é o mesmo.

LEDs acesos **não provam** que o hub está funcionando: WS2812 retém a última
cor recebida indefinidamente, sem sinal contínuo.

O segundo incidente pesa a favor de uma das duas hipóteses:

| Candidato | Estado depois do 2º travamento |
|---|---|
| Firmware afogado em comando repetido | Mitigado ao limite prático (2 escritas/hora) — **travou mesmo assim** |
| Regulador do hub em estresse térmico | Sem mitigação, exposição aumentou (branco 24/7) — **candidato mais provável agora** |

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
