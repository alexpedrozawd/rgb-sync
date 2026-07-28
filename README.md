# rgb-sync

Sincroniza a iluminação ARGB do PC com a atividade real da GPU: **tudo apagado
em ocioso, tudo em branco estático quando a GPU entra em carga** (jogo, LLM via
Ollama, jobs do ComfyUI/AP AI Studio, ou qualquer outra carga pesada).

Cobre: hub de fans do gabinete (Rise Mode, 8 fans), water cooler (Pichau Aqua
240X) e as duas RAMs. Não mexe em velocidade/rotação de fan nem no display de
temperatura do water cooler — só na luz, via [OpenRGB](https://openrgb.org/).

Ver também: [`pichau-aqua-240x-linux-driver`](../pichau-aqua-240x-linux-driver)
— driver separado, do display de temperatura do pump (LCD), não da luz ARGB.

## Hardware coberto

| Componente | Como está ligado |
|---|---|
| Placa-mãe | ASUS PRIME B760M-A D4 |
| Hub de fans (8x, gabinete) | Rise Mode Galaxy Glass Standard V2 |
| Water cooler | Pichau Aqua 240X |
| RAM | 2 pentes com controlador "ENE DRAM" |

**Topologia real da fiação ARGB** (mapeada testando cor por zona com o
hardware na frente, 2026-07-28): a placa-mãe expõe 4 zonas Aura ("Aura
Mainboard" + "Aura Addressable 1/2/3"), mas só a zona 3 tem algo conectado — o
hub de fans e o water cooler estão **encadeados em série no mesmo header**
("Aura Addressable 3"), totalizando 40 LEDs endereçáveis. As zonas 1 e 2 não
têm nada plugado. Isso é o oposto do que normalmente se assume (cada
componente no seu próprio header) — se um dia trocar o hub ou o water cooler,
vale re-mapear (ver "Como remapear zonas" abaixo).

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
- GPU ativa → acende tudo em branco estático. Continua reaplicando a cada
  ciclo enquanto ativa (não só na 1ª vez — ver "Bugs corrigidos" abaixo).
- GPU ociosa por 60s (`DEBOUNCE_SECONDS`) → apaga tudo.
- Enquanto ocioso, re-afirma o "apagado" a cada 5 min (`DEFAULT_REASSERT_SECONDS`)
  pra corrigir qualquer drift (ex: alguém mexeu no software da Aura por fora).
- No arranque do serviço, força o estado padrão (apagado) antes de qualquer
  outra coisa — cobre reboot, logout/login, crash do serviço.

Variáveis de ambiente pra afinar sem editar o script (`DEBOUNCE_SECONDS`,
`DEFAULT_REASSERT_SECONDS`, `SLEEP_SECONDS`, `UTIL_THRESHOLD_PCT`,
`POWER_THRESHOLD_W`) — dá pra sobrescrever no `ExecStart` do
`systemd/gpu-rgb-sync.service` se precisar.

## Depois de uma queda de energia total

**Isso nenhum software resolve.** Se a fonte for cortada de vez (não um
desligamento normal), o hub Rise Mode pode sair do modo "M/B Sync" e passar a
rodar o Rainbow autônomo dele, ignorando o header ARGB da placa-mãe. Placa-mãe
(Aura) e RAMs voltam ao normal sozinhas; só o hub de fans + water cooler
(zona 3) ficam presos nesse estado.

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

## Como remapear zonas (se trocar hub/water cooler/placa)

1. Pare o serviço pra evitar interferência: `systemctl --user stop gpu-rgb-sync.service`.
2. Liste os dispositivos: `openrgb --list-devices`.
3. Teste cor por zona pra identificar o que é o quê:
   ```bash
   openrgb -d "ASUS" -z 1 -sz 8 -c FF0000 -m static   # zona 1 = vermelho
   openrgb -d "ASUS" -z 2 -sz 8 -c 00FF00 -m static   # zona 2 = verde
   openrgb -d "ASUS" -z 3 -sz 8 -c 0000FF -m static   # zona 3 = azul
   ```
4. Suba o tamanho aos poucos (`-sz`) até achar o total real de LEDs da cadeia —
   sem parte apagada nem cor torta no fim da fileira.
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

- **Corrida de boot no "ligar"**: o script só mandava o comando de ligar uma
  vez, na transição. Se disparasse antes do dispositivo Aura estar pronto
  (ex: jogo abrindo automático logo no login), falhava silenciosamente e nunca
  mais tentava — RAMs ligavam (mais rápidas a responder) mas fans+water cooler
  ficavam apagados. Corrigido reaplicando o comando a cada ciclo (10s) enquanto
  a GPU estiver ativa, não só na 1ª vez. Seguro porque o efeito é estático (sem
  animação pra "reiniciar").
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
