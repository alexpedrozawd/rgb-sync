# rgb-sync

Mantém **toda a iluminação ARGB do PC em branco estático, permanentemente**.
Sem RGB, sem efeito, sem acender e apagar: um estado só, branco, 24/7.

Cobre: 8 fans do gabinete (hub Rise Mode), 2 fans do radiador do water cooler
(Pichau Aqua 240X) e as 2 RAMs. Não mexe em velocidade/rotação de fan nem no
display de temperatura do water cooler — só na luz, via
[OpenRGB](https://openrgb.org/).

Ver também: [`pichau-aqua-240x-linux-driver`](../pichau-aqua-240x-linux-driver)
— driver separado, do display de temperatura do pump (LCD), não da luz ARGB.

> ## ⚠️ Problema em aberto
>
> **RAMs e fans do cooler funcionam de forma confiável. As 8 fans do gabinete
> não.** O hub Rise Mode perde o modo "M/B Sync" em reboots/eventos de energia
> e, uma vez fora dele, ignora sinal válido da placa-mãe — só volta apertando o
> botão físico `ON M/B` no controle remoto. Em 2026-07-29 o firmware do hub
> chegou a travar por completo, **parando as fans de girar** (risco térmico
> real).
>
> Diagnóstico completo, linha do tempo dos incidentes, evidência dos logs e o
> que já foi refutado: **[`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md)**.

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

> ⚠️ **`FAN_ZONE_SIZE=40` não é uma contagem de LEDs.** Veio de subir `-sz` até
> "acender tudo uniforme, sem ponta apagada" — mas com **cor única esse teste não
> pode falhar**, qualquer tamanho parece certo. Medindo depois: com a zona em
> tamanho **1** as fans do cooler acendem **inteiras**, o que é impossível numa
> cadeia de 40 LEDs endereçáveis. Funciona na prática; não tratar como medição.

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

`REASSERT_SECONDS` é sobrescrevível por variável de ambiente no `ExecStart` do
`systemd/rgb-branco.service`.

## Quando as 8 fans do gabinete não estão brancas

Significa que o hub saiu do modo "M/B Sync" e está rodando o Rainbow autônomo
dele, ignorando o header. **Nenhum software resolve isso** — ver o diagnóstico.

Para voltar:

1. **Confirme que existe sinal válido no header**: as 2 fans do cooler devem
   estar brancas. Se não estiverem, rode `./install.sh` de novo e espere.
2. Só então aperte **`ON M/B`** no controle IR do hub.

> ⚠️ A ordem importa. Em 2026-07-27, apertar o botão com a zona sem nenhum sinal
> configurado (tamanho 0, header mudo) **travou o sistema inteiro**, exigindo
> desligar a fonte e o HDMI. Os logs não mostram causa definitiva (o boot
> simplesmente para de logar, sem panic), mas o padrão bate com "hub esperando
> dado que nunca chega". Com sinal válido presente, o mesmo botão funcionou sem
> problema. Com este desenho o header está sempre com sinal, então a condição
> perigosa só ocorre se o serviço estiver parado.

## ⚠️ Risco conhecido: o hub pode travar (fans param de girar)

**Incidente real (2026-07-29):** durante uma sessão longa de jogo, o
microcontrolador do hub travou — as 8 fans do gabinete **pararam de girar** e o
controle remoto ficou 100% sem resposta. Os LEDs continuaram acesos em branco,
**mas isso não prova que o hub estava funcionando**: LEDs endereçáveis (WS2812)
retêm a última cor recebida indefinidamente, sem sinal contínuo.

Duas causas possíveis, **com correlação exatamente igual** — aquela janela de 19
minutos foi simultaneamente a maior sequência de comandos repetidos do dia *e* o
maior período contínuo de corrente máxima:

| Candidato | Estado hoje |
|---|---|
| Firmware afogado em comando repetido | **Corrigido** — 2 escritas/hora contra ~6/minuto na época |
| Regulador do hub em estresse térmico | **Sem mitigação** — branco pleno agora é permanente |

Se as fans do hub pararem de girar:

1. Pare o serviço: `systemctl --user stop rgb-branco.service`.
2. Evite carga pesada até resolver.
3. Teste o controle remoto. Se **nenhum botão** funcionar, o microcontrolador
   travou — não tem correção por software.
4. PC desligado → desconecte só o cabo de alimentação (Molex/SATA) do hub por
   ~30s → reconecte → ligue.
5. O hub volta em Rainbow autônomo. Siga o procedimento de `ON M/B` acima.

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
