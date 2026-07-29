#!/bin/bash
# gpu-rgb-sync -- controla os LEDs (placa-mae: hub de fans + water cooler; e as
# RAMs) conforme a GPU. Estado PADRAO = tudo apagado; liga tudo em BRANCO ESTATICO
# quando a GPU entra em atividade real (jogo, LLM no Ollama, job no ComfyUI/AP AI
# Studio, ou qualquer outra carga), e volta a apagar 60s depois que ela fica
# ociosa. Nao mexe na velocidade/rotacao das fans, so na iluminacao via OpenRGB.
#
# TOPOLOGIA ARGB -- o que esta MEDIDO (2026-07-28 e 2026-07-29):
#   A placa-mae expoe 4 zonas no dispositivo Aura ("Aura Mainboard" + "Aura
#   Addressable 1/2/3"). So a zona 3 tem algo conectado; zonas 1 e 2 estao vazias.
#   Na zona 3 respondem: as 2 fans do radiador do water cooler Pichau Aqua 240X
#   (sempre obedecem) e o hub Rise Mode com as 8 fans do gabinete (obedece so
#   enquanto estiver no modo "M/B Sync" dele).
#
#   O water cooler NAO esta a jusante do hub: ele continua obedecendo o header
#   enquanto o hub roda o Rainbow autonomo. Se o sinal passasse atraves do hub,
#   herdaria o Rainbow. A forma exata da fiacao (splitter em paralelo vs. cooler
#   primeiro em serie) nao foi confirmada visualmente.
#
#   ATENCAO -- "40 LEDs em serie" era ERRADO, ou pelo menos sem base:
#   Medido em 2026-07-29: zerando a zona toda e depois mandando branco com a zona
#   em tamanho 10, e depois em tamanho 1, as 2 fans do cooler acenderam INTEIRAS
#   nos dois casos. Isso e impossivel numa cadeia simples de 40 LEDs
#   enderecaveis. Duas explicacoes cabem e o CLI do OpenRGB nao as separa:
#     (a) o controlador Aura replica a cor unica pra todo o quadro quando a zona
#         e menor que a cadeia fisica; ou
#     (b) o que esta na zona 3 nao e cadeia crua -- ha elemento ativo que consome
#         o quadro e replica a cor nos LEDs dele.
#   Em qualquer das duas, FAN_ZONE_SIZE nao corresponde a uma contagem fisica e o
#   metodo original ("subir -sz ate acender uniforme") nao podia medir nada: com
#   cor unica, qualquer tamanho parece certo.
#
# HIBRIDO NVIDIA/AMD (2026-07-08): detecta o backend de GPU no arranque, pra
#   sobreviver a troca da RTX 5060 Ti -> RX 9070 XT (RDNA4) sem intervencao.
#   - NVIDIA -> le utilizacao/potencia via `nvidia-smi` (comportamento original,
#               inalterado).
#   - AMD    -> le utilizacao via sysfs do amdgpu (`gpu_busy_percent`).
#   Validado em hardware real com a RX 9070 XT (2026-07-28): deteccao "amd" ok,
#   utilizacao via gpu_busy_percent responde corretamente a jogos/cargas.
#
# PERFORMANCE (2026-07-28): com a RX 9070 a placa registra ~13 barramentos I2C
#   (DM/aux/SMU do amdgpu) no OpenRGB. Em modo standalone (--noautoconnect) cada
#   chamada resonda TUDO do zero e leva ~8,7s (media 17s por transicao, 2
#   chamadas) -- e o motivo do script "nao funcionar" na pratica. Agora conecta
#   como cliente no servidor persistente (openrgb.service); se o servidor nao
#   estiver de pe, cai sozinho no standalone lento (mesmo comportamento de antes,
#   so mais devagar). Ver openrgb.service -- precisa estar habilitado e, por
#   seguranca, com bind restrito a 127.0.0.1 (o default do pacote e 0.0.0.0).
#
# BLINDAGEM (2026-07-06, reforcada em 2026-07-28, corrigida em 2026-07-29):
#   (1) forca o estado padrao (apagado) ja no ARRANQUE -> cobre reboot / shutdown
#       / queda de energia: assim que a sessao grafica sobe e o servico inicia,
#       os LEDs voltam ao padrao;
#   (2) RE-AFIRMA o estado apagado a cada DEFAULT_REASSERT_SECONDS e o ligado a
#       cada ON_REASSERT_SECONDS, NAO a cada ciclo/10s -> corrige "drift"
#       (Aura/RAM voltarem sozinhos pro efeito de fabrica, ou uma corrida de boot
#       em que o 1o comando nao pegou porque o dispositivo ainda nao estava
#       pronto) sem martelar o hub com comando repetido o tempo todo;
#   (3) manda o MINIMO de escrita por reafirmacao -- um comando por dispositivo,
#       e o tamanho da zona so e reescrito se uma leitura mostrar que esta errado
#       (ver leds_ligar). Antes eram dois comandos ao Aura por reafirmacao, um
#       deles redimensionando a zona toda vez.
#
#   HISTORICO DESSE PONTO (importante nao repetir): entre 2026-07-28 e 07-29 o
#   "ligado" chegou a ser reenviado a CADA ciclo (10s) enquanto a GPU ficava
#   ativa, pra fechar uma corrida de boot (RAMs ligavam mas fans+water cooler
#   ficavam apagados ate reaplicacao manual). Ficou detectado que isso E
#   PERIGOSO: numa sessao longa de jogo (2026-07-29), o microcontrolador do hub
#   Rise Mode travou -- fans do gabinete PARARAM DE GIRAR e o controle remoto
#   ficou 100% sem resposta (nem ON M/B, nem cor, nada), so voltando com um
#   power-cycle isolado do cabo de energia do hub. Os LEDs endereçaveis (estilo
#   WS2812) RETEM a ultima cor recebida indefinidamente sem precisar de sinal
#   continuo -- entao "LED branco aceso e parado" NAO prova que o hub estava
#   vivo, so que a ultima cor ficou latched enquanto o controlador ja tinha
#   travado. Suspeita forte (nao 100% provada, so 1 incidente): o bombardeio de
#   comando a cada 10s sobrecarregou o firmware fragil do hub. Corrigido
#   voltando a reafirmar so a cada DEFAULT_REASSERT_SECONDS (mesmo intervalo do
#   lado "apagado"). NAO reverter pra "a cada ciclo" sem entender esse risco.
#
# LIMITE FISICO (nenhum software resolve): quando o hub Rise Mode sai do modo
#   "M/B Sync", ele passa a ignorar o header ARGB da placa-mae e roda o Rainbow
#   autonomo dele -> so volta apertando o botao "ON M/B" no controle remoto. A
#   re-afirmacao acima manda "off"/"branco" pro header, mas o hub nesse estado
#   nao obedece (provado: 2h08min de branco continuo ignorado). Placa-mae (Aura)
#   e RAMs sao corrigidas normalmente; so o hub depende do botao fisico.
#
#   NAO e exclusivo de queda de energia total: um `systemctl reboot` limpo bastou
#   (2026-07-29 16:48). E NAO e por falta de dado no header -- isso foi testado
#   contra o log e refutado: em 2026-07-29 o header ficou em "Off" das 07:37:06
#   as 08:32:04 (54min58s) e o hub continuou obedecendo depois (acendeu branco as
#   09:46:07, cor que so o script manda). Depois disso ele caiu numa janela de
#   silencio de 70 segundos, num reboot. Ausencia de sinal nao e o gatilho; o
#   evento de reboot e. Ver docs/DIAGNOSTICO-HUB.md.
#
#   ATENCAO ao reativar o M/B Sync no controle: so aperte o botao com o
#   openrgb.service ATIVO e depois de rodar `gpu-rgb-sync.sh` (ou o comando de
#   "ligar" manual) pelo menos uma vez, garantindo sinal ARGB valido no header
#   NO MOMENTO do aperto. Ja aconteceu 1x (2026-07-27) o hub travar o sistema
#   inteiro (precisou desligar fonte + HDMI) ao apertar o botao com a zona sem
#   nenhum sinal valido -- root cause exato nao confirmado nos logs (nao ha
#   panic/oops, so o log parando), mas o padrao bateu com "sem dado no header".

MB_DEVICE="ASUS PRIME B760M-A D4"
RAM_DEVICE="ENE DRAM"

# Zona 3 = hub de fans do gabinete + water cooler (ver TOPOLOGIA ARGB acima).
#
# ATENCAO ao FAN_ZONE_SIZE=40: esse numero NAO foi medido. Foi escolhido mandando
#   -sz 40 e observando "acendeu tudo uniforme, sem ponta apagada" -- mas com uma
#   COR UNICA esse teste nao pode falhar, qualquer tamanho parece certo. Pra medir
#   de verdade precisa de um padrao com fronteira visivel (ver docs/DIAGNOSTICO-HUB.md,
#   secao 3). Mantido em 40 porque funciona na pratica; nao e uma contagem real.
FAN_ZONE_INDEX=3
FAN_ZONE_SIZE=40

# Rotulo dos LEDs dessa zona em `openrgb --list-devices`, usado pra LER o tamanho
# atual antes de reescreve-lo. Nao e derivavel do indice: a zona 0 e a "Aura
# Mainboard", entao indice 3 <-> "Aura Addressable 3" e coincidencia, nao regra.
FAN_ZONE_LED_LABEL="Aura Addressable ${FAN_ZONE_INDEX}, LED "

# Cor do estado "ligado". Branco estatico escolhido no lugar do Rainbow (2026-07-28,
# comparado lado a lado com o hardware na frente -- decisao do usuario).
#
# A0A0A0 em vez de FFFFFF (2026-07-29, aprovado pelo usuario): FFFFFF e o estado de
#   CORRENTE MAXIMA POSSIVEL de todo o array ARGB (~60 mA por LED em branco pleno).
#   A janela de 19 min que travou o hub em 2026-07-29 foi, ao mesmo tempo, a maior
#   sequencia de comandos repetidos do dia E o maior periodo continuo de corrente
#   maxima -- as duas hipoteses tem correlacao identica e o diagnostico original so
#   considerava a primeira. A0 = 160/255 = ~63% de duty, o que corta ~37% da
#   corrente do array com diferenca visual minima (continua branco, so um pouco
#   menos ofuscante). Mitigacao da segunda hipotese; a da primeira e o
#   ON_REASSERT_SECONDS. Se quiser voltar ao branco pleno, e so trocar aqui -- mas
#   veja o orcamento de 3A do header na secao 7 do docs/DIAGNOSTICO-HUB.md antes de
#   considerar splitter passivo com branco pleno.
LED_COLOR="A0A0A0"

# Baseline ociosa observada (NVIDIA): ~0% de utilizacao, ~16W de potencia. Qualquer
# utilizacao > 0% ja conta como atividade; a potencia e so uma rede de seguranca
# caso a amostra de utilizacao caia bem no meio de uma rajada curta.
UTIL_THRESHOLD_PCT=1
POWER_THRESHOLD_W=25

# Tempos (segundos). Overrideaveis por variavel de ambiente so pra teste/afinacao.
#  DEBOUNCE_SECONDS         : quanto os LEDs ficam acesos apos a ultima atividade
#                            (evita strobar entre consultas curtas ao Ollama).
#  DEFAULT_REASSERT_SECONDS : de quanto em quanto re-afirmar o "off" enquanto
#                            ocioso. So reenvia o MESMO estado (sem transicao,
#                            sem risco de flicker) -- 120s corrige drift em ate
#                            2min, com trafego SMBus/HID irrisorio (30 writes/h).
#  ON_REASSERT_SECONDS      : de quanto em quanto re-afirmar o "ligado" enquanto
#                            a GPU continua ativa. Mais conservador que o do
#                            "off" (300s = 5min) por seguranca extra: o hub de
#                            fans ja travou 1x (2026-07-29) com reassert
#                            frequente demais (10s) numa sessao longa de jogo --
#                            ver BLINDAGEM no topo do arquivo.
#  SLEEP_SECONDS            : intervalo do laco de verificacao (tambem controla
#                            a velocidade do auto-retry do "ligar" no boot).
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-60}"
DEFAULT_REASSERT_SECONDS="${DEFAULT_REASSERT_SECONDS:-120}"
ON_REASSERT_SECONDS="${ON_REASSERT_SECONDS:-300}"
SLEEP_SECONDS="${SLEEP_SECONDS:-10}"

# --- Deteccao do backend de GPU (uma vez, no arranque) -----------------------
# amd -> sysfs amdgpu (gpu_busy_percent) ; nvidia -> nvidia-smi ; none -> fail-safe.
GPU_BACKEND="none"
AMD_BUSY_FILE=""

detectar_backend_gpu() {
  local busy card vendor
  for busy in /sys/class/drm/card[0-9]*/device/gpu_busy_percent; do
    [ -r "$busy" ] || continue
    card="${busy%/gpu_busy_percent}"
    vendor="$(cat "$card/vendor" 2>/dev/null)"
    if [ "$vendor" = "0x1002" ]; then   # 0x1002 = AMD
      GPU_BACKEND="amd"
      AMD_BUSY_FILE="$busy"
      return
    fi
  done
  if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_BACKEND="nvidia"
    return
  fi
  GPU_BACKEND="none"
}

gpu_ativa() {
  case "$GPU_BACKEND" in
    amd)
      # AMD: utilizacao via sysfs (gpu_busy_percent). Baseline ociosa = 0%.
      # Usa SO utilizacao de proposito: o limiar de POTENCIA (25W) foi calibrado
      # pro idle da NVIDIA (~16W), e o idle da AMD em 4K144 pode ser mais alto ->
      # incluir potencia aqui arriscaria "LED preso ligado". Se quiser a rede de
      # seguranca por potencia na AMD, calibrar o idle real e adicionar aqui.
      local util
      util="$(cat "$AMD_BUSY_FILE" 2>/dev/null)" || return 1
      [ "${util%.*}" -ge "$UTIL_THRESHOLD_PCT" ] 2>/dev/null && return 0
      return 1
      ;;
    nvidia)
      # NVIDIA: comportamento original (utilizacao OU potencia).
      local stats util power
      stats=$(nvidia-smi --query-gpu=utilization.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null) || return 1
      util=$(echo "$stats" | cut -d',' -f1 | tr -d ' ')
      power=$(echo "$stats" | cut -d',' -f2 | tr -d ' ')
      [ "${util%.*}" -ge "$UTIL_THRESHOLD_PCT" ] 2>/dev/null && return 0
      [ "${power%.*}" -ge "$POWER_THRESHOLD_W" ] 2>/dev/null && return 0
      return 1
      ;;
    *)
      # Backend desconhecido -> fail-safe: nunca liga (LEDs ficam no padrao off).
      return 1
      ;;
  esac
}

# Le o tamanho atual da zona do hub. Como CLIENTE do openrgb.service isso custa
# ~0,04s e nao escreve nada no header -- barato o bastante pra rodar a cada
# "ligar" e caro zero comparado a reescrever o tamanho as cegas.
zona_tamanho_atual() {
  # `grep -o | wc -l`, NAO `grep -c`: o --list-devices imprime todos os LEDs numa
  # UNICA linha, entao grep -c retornaria 1 e o teste de tamanho nunca casaria --
  # o resize voltaria a disparar em todo ciclo, que e justamente o que se quer
  # eliminar aqui. Falha silenciosa; ja aconteceu ao escrever esta funcao.
  openrgb --list-devices 2>/dev/null \
    | grep -o "'${FAN_ZONE_LED_LABEL}[0-9]*'" \
    | wc -l
}

leds_ligar() {
  # REDUCAO DE TRAFEGO NO HEADER (2026-07-29, ver BLINDAGEM acima): antes esta
  # funcao mandava DOIS comandos pro dispositivo Aura -- um na zona 3 (que ainda
  # reescrevia o TAMANHO da zona) e outro no dispositivo inteiro. O segundo ja
  # cobre a zona 3 sozinho: `-c` com uma cor unica replica ela em todos os LEDs
  # do dispositivo ("If there are more LEDs than colors given, the last color
  # will be applied to the remaining LEDs" -- openrgb --help). Ou seja, o
  # primeiro comando era redundante pra cor e so servia pro `-sz`.
  #
  # Agora o tamanho e LIDO antes e so reescrito se estiver errado. Isso corta o
  # numero de escritas no header pela metade e elimina o redimensionamento
  # repetido da zona -- que e a operacao mais invasiva das duas, porque
  # reconfigura o canal do header em vez de so trocar cor. A rede de seguranca
  # contra "queda de energia zerou o tamanho" continua: se a leitura nao der
  # FAN_ZONE_SIZE, reescreve na hora.
  if [ "$(zona_tamanho_atual)" != "$FAN_ZONE_SIZE" ]; then
    openrgb -d "$MB_DEVICE" -z "$FAN_ZONE_INDEX" -sz "$FAN_ZONE_SIZE" -c "$LED_COLOR" -m static > /dev/null 2>&1
  fi
  openrgb -d "$MB_DEVICE" -m static -c "$LED_COLOR" > /dev/null 2>&1
  openrgb -d "$RAM_DEVICE" -m static -c "$LED_COLOR" > /dev/null 2>&1
}

leds_apagar() {
  # O dispositivo Aura vai pra "Static preto" em vez de "Off" (hipotese H1 do
  # diagnostico). Visualmente identico -- LED apagado e LED em 000000 sao a
  # mesma coisa a olho nu -- mas o controlador fica num modo que produz quadro
  # de dados em vez de um modo que pode simplesmente parar de clocar o header.
  #
  # HONESTIDADE SOBRE O QUE ISSO RESOLVE: os logos deste repo indicam que H1 nao
  # e a causa da perda de sync (ver docs/DIAGNOSTICO-HUB.md, secao 6). O motivo
  # de manter a mudanca e outro e independente: com o header nunca em "Off", o
  # aperto do botao ON M/B nunca cai no cenario que travou o PC inteiro em
  # 2026-07-27 (zona sem sinal). E uma trava de seguranca, nao a correcao do sync.
  #
  # O RAM_DEVICE continua em "Off" de proposito: as RAMs sempre funcionaram e
  # nao ha motivo pra mexer no que esta provado.
  openrgb -d "$MB_DEVICE" -m static -c 000000 > /dev/null 2>&1
  openrgb -d "$RAM_DEVICE" -m off > /dev/null 2>&1
}

detectar_backend_gpu
echo "gpu-rgb-sync: backend de GPU detectado = ${GPU_BACKEND}."

# Arranque: forca o estado padrao (apagado).
leds_apagar
estado_atual="off"
ultima_atividade_epoch=0
ultima_reafirmacao_epoch=0   # 0 => re-afirma logo no 1o ciclo ocioso (fecha a corrida de boot)

while true; do
  agora=$(date +%s)

  if gpu_ativa; then
    ultima_atividade_epoch=$agora
    if [ "$estado_atual" != "on" ]; then
      leds_ligar
      estado_atual="on"
      ultima_reafirmacao_epoch=$agora
      echo "GPU ativa - LEDs ligados (branco estatico)."
    elif [ $((agora - ultima_reafirmacao_epoch)) -ge "$ON_REASSERT_SECONDS" ]; then
      # Blindagem: reafirma o "ligado" a cada ON_REASSERT_SECONDS (nao mais
      # a cada ciclo/10s) -- fecha a mesma corrida de boot do dispositivo Aura
      # nao estar pronto, mas SEM martelar o hub com comando repetido o tempo
      # todo. Suspeita forte (2026-07-29): reenviar a cada 10s numa sessao longa
      # de jogo parece ter travado o microcontrolador do hub (fans pararam de
      # girar e o controle remoto ficou 100% sem resposta, ate um power-cycle
      # isolado do hub religar) -- os LEDs WS2812 retem a ultima cor recebida
      # indefinidamente sem precisar de sinal continuo, entao "LED aceso e
      # parado" NAO prova que o hub estava vivo, so que a ultima cor ficou
      # latched enquanto o controlador ja tinha travado.
      leds_ligar
      ultima_reafirmacao_epoch=$agora
    fi
  else
    if [ "$estado_atual" = "on" ] && [ $((agora - ultima_atividade_epoch)) -ge "$DEBOUNCE_SECONDS" ]; then
      leds_apagar
      estado_atual="off"
      ultima_reafirmacao_epoch=$agora
      echo "GPU ociosa ha ${DEBOUNCE_SECONDS}s - LEDs apagados."
    elif [ "$estado_atual" = "off" ] && [ $((agora - ultima_reafirmacao_epoch)) -ge "$DEFAULT_REASSERT_SECONDS" ]; then
      # Blindagem: re-afirma o padrao apagado (corrige drift/corrida de boot).
      leds_apagar
      ultima_reafirmacao_epoch=$agora
    fi
  fi

  sleep "$SLEEP_SECONDS"
done
