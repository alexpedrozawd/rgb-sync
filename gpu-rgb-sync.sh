#!/bin/bash
# gpu-rgb-sync -- controla os LEDs (placa-mae: hub de fans + water cooler; e as
# RAMs) conforme a GPU. Estado PADRAO = tudo apagado; liga tudo em BRANCO ESTATICO
# quando a GPU entra em atividade real (jogo, LLM no Ollama, job no ComfyUI/AP AI
# Studio, ou qualquer outra carga), e volta a apagar 60s depois que ela fica
# ociosa. Nao mexe na velocidade/rotacao das fans, so na iluminacao via OpenRGB.
#
# TOPOLOGIA ARGB (mapeada em 2026-07-28, testando cor por zona com o hardware na
#   frente): a placa-mae expoe 4 zonas no dispositivo Aura ("Aura Mainboard" +
#   "Aura Addressable 1/2/3"), mas so a zona 3 tem algo fisico conectado -- o hub
#   Rise Mode (8 fans do gabinete) e o water cooler Pichau Aqua 240X estao
#   ENCADEADOS EM SERIE no mesmo header ("Aura Addressable 3"), num total de 40
#   LEDs enderecaveis (confirmado: 40 acendeu tudo uniforme, sem ponta apagada
#   nem cor torta no fim da fileira -- ver FAN_ZONE_INDEX/FAN_ZONE_SIZE abaixo).
#   Zonas 1 e 2 nao tem nada plugado (sobraram do teste de mapeamento, sem efeito
#   pratico). O tamanho da zona fica gravado no proprio controlador Aura (sobrevive
#   a restart do openrgb.service), mas o script redefine o tamanho a cada "ligar"
#   mesmo assim, como rede de seguranca contra uma queda de energia zerar isso.
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
# BLINDAGEM (2026-07-06, reforcada em 2026-07-28):
#   (1) forca o estado padrao (apagado) ja no ARRANQUE -> cobre reboot / shutdown
#       / queda de energia: assim que a sessao grafica sobe e o servico inicia,
#       os LEDs voltam ao padrao;
#   (2) RE-AFIRMA o estado padrao periodicamente enquanto ocioso -> corrige
#       qualquer "drift" (Aura/RAM voltarem sozinhos pro efeito de fabrica depois
#       de uma queda de energia, ou uma corrida de boot em que o 1o "off" nao
#       pegou porque o dispositivo ainda nao estava pronto);
#   (3) reaplica o "ligado" a CADA CICLO enquanto a GPU estiver ativa, nao so na
#       1a transicao -> fecha a mesma corrida de boot do lado do "ligar": se o
#       dispositivo Aura ainda nao estava pronto no exato momento em que a GPU
#       ficou ativa logo apos o boot, o proximo ciclo (10s depois) corrige
#       sozinho. Bug real observado em 2026-07-28: RAMs ligavam no boot mas
#       fans+water cooler (zona 3) ficavam apagados ate uma reaplicacao manual.
#
# LIMITE FISICO (nenhum software resolve): se o hub Rise Mode sair do modo
#   "M/B Sync" apos uma queda de energia TOTAL, ele passa a ignorar o header ARGB
#   da placa-mae e roda o Rainbow autonomo dele -> precisa apertar o botao "ON M/B"
#   no controle remoto do hub. A re-afirmacao acima manda "off"/"branco" pro
#   header, mas o hub nesse estado nao obedece. Placa-mae (Aura) e RAMs sao
#   corrigidas normalmente; so o hub depende do botao fisico. Ver README.md,
#   secao "Depois de uma queda de energia total".
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

# Zona 3 = hub de fans do gabinete + water cooler, encadeados em serie (ver
# TOPOLOGIA ARGB acima). Tamanho redefinido a cada "ligar" por seguranca.
FAN_ZONE_INDEX=3
FAN_ZONE_SIZE=40

# Cor do estado "ligado". Branco estatico escolhido no lugar do Rainbow (2026-07-28,
# comparado lado a lado com o hardware na frente -- decisao do usuario).
LED_COLOR="FFFFFF"

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
#  SLEEP_SECONDS            : intervalo do laco de verificacao (tambem controla
#                            a velocidade do auto-retry do "ligar" no boot).
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-60}"
DEFAULT_REASSERT_SECONDS="${DEFAULT_REASSERT_SECONDS:-120}"
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

leds_ligar() {
  openrgb -d "$MB_DEVICE" -z "$FAN_ZONE_INDEX" -sz "$FAN_ZONE_SIZE" -c "$LED_COLOR" -m static > /dev/null 2>&1
  openrgb -d "$MB_DEVICE" -m static -c "$LED_COLOR" > /dev/null 2>&1
  openrgb -d "$RAM_DEVICE" -m static -c "$LED_COLOR" > /dev/null 2>&1
}

leds_apagar() {
  openrgb -d "$MB_DEVICE" -m off > /dev/null 2>&1
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
    # Blindagem: reaplica a cada ciclo (nao so na 1a transicao) -- estatico nao
    # tem animacao pra reiniciar, entao isso e barato e fecha a corrida de boot
    # em que o 1o "ligar" e disparado antes do dispositivo Aura estar pronto.
    leds_ligar
    if [ "$estado_atual" != "on" ]; then
      estado_atual="on"
      echo "GPU ativa - LEDs ligados (branco estatico)."
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
