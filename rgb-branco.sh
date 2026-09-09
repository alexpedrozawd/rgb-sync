#!/bin/bash
# rgb-branco -- mantem TODOS os LEDs ARGB da maquina em BRANCO ESTATICO,
# permanentemente. Sem logica de GPU, sem apagar em ocioso, sem RGB: o estado
# desejado e UM SO, branco, o tempo todo.
#
# Cobre: 8 fans do gabinete (hub Rise Mode), 2 fans do radiador do water cooler
# (Pichau Aqua 240X) e as 2 RAMs.
#
# POR QUE ISSO SUBSTITUIU O gpu-rgb-sync.sh (2026-07-30, decisao do usuario):
#   O projeto original acendia em branco sob carga de GPU e apagava em ocioso.
#   Na pratica o usuario preferiu branco permanente -- menos chamativo de dia,
#   ilumina de noite. Alem de ser o que ele quer, e MUITO mais simples e mais
#   seguro: sai a maquina de estados, saem os limiares, sai a deteccao
#   NVIDIA/AMD, e sobretudo saem as TRANSICOES.
#
#   Ganho de seguranca concreto, nao cosmetico:
#     - O header nunca mais fica mudo. Isso elimina por construcao o cenario que
#       travou o PC inteiro em 2026-07-27 (apertar ON M/B com a zona sem sinal).
#     - Sem transicoes, o trafego no header cai pra 2 escritas por hora. O
#       travamento do hub em 2026-07-29 aconteceu sob ~6 escritas por MINUTO
#       sustentadas por 19 min. E ~180x menos trafego.
#
#   Contrapartida que se confirmou custosa: branco PLENO e o estado de CORRENTE
#   MAXIMA do array, e o desenho o tornou permanente 24/7 em vez de so sob carga.
#   O hub travou de novo em 2026-08-12, terceira vez -- e o sintoma novo (LEDs
#   PISCANDO em vez de cor presa) apontou pra protecao de alimentacao em modo
#   hiccup. Ver LED_COLOR abaixo pra conta completa e pra mitigacao aplicada.
#
#   Uma tentativa anterior de escurecer (A0A0A0, 2026-07-29) foi revertida porque
#   saiu AMARELADA -- mas o problema era falta de compensacao de azul, nao o
#   escurecimento em si. Com compensacao, da pra escurecer mantendo branco
#   neutro; foi o que se fez em 2026-08-12.
#
# TOPOLOGIA ARGB -- o que esta MEDIDO:
#   A placa expoe 4 zonas no dispositivo Aura ("Aura Mainboard" + "Aura
#   Addressable 1/2/3"). So a zona 3 tem algo conectado; 1 e 2 estao vazias. Na
#   zona 3 respondem as 2 fans do radiador do cooler (sempre obedecem) e o hub
#   Rise Mode com as 8 fans do gabinete (obedece so enquanto estiver em "M/B
#   Sync"). O cooler NAO esta a jusante do hub.
#
#   FAN_ZONE_SIZE=40 NAO e uma contagem fisica -- ver comentario nele abaixo.
#
# LIMITE FISICO (nenhum software resolve): quando o hub Rise Mode sai do modo
#   "M/B Sync" ele ignora o header e roda o Rainbow autonomo dele, e so volta
#   pelo botao "ON M/B" do controle IR. Isso acontece em eventos de
#   reboot/energia e NAO e por falta de dado no header (testado e refutado: 55
#   min de header em "Off" e o hub continuou obedecendo). Ver
#   docs/DIAGNOSTICO-HUB.md.
#
#   MAS este design e a melhor chance de o sync sobreviver, e nunca foi testado
#   antes: no desenho antigo a primeira acao de todo boot era APAGAR, deixando o
#   header mudo pelos primeiros ~30s. Agora ele carrega branco valido desde o
#   POST. Se o hub decide o modo no proprio power-on conforme haja sinal valido
#   na linha -- design comum nessa classe de hub -- o resultado muda.
#
# PERFORMANCE: fala com o openrgb.service (servidor persistente) como cliente.
#   Standalone cada chamada leva ~8,7s, porque a RX 9070 registra ~13 barramentos
#   I2C que sao re-sondados do zero. Como cliente, uma leitura custa ~0,04s.

# TOPOLOGIA ARGB MEDIDA E CONFIRMADA (2026-09-05):
#   - Header 1 (ADD_GEN2_1 / Zona 1): Hub ativo Rise Mode (8 fans do gabinete)
#   - Header 3 (ADD_GEN2_3 / Zona 3): Water Cooler Pichau Aqua 240X (bomba + 2 fans)
#   - Header 2 (ADD_GEN2_2 / Zona 2): Vazio
#   - RAMs: 2 pentes DDR4 controlador ENE DRAM (SMBus 0x71 e 0x73)

MB_DEVICE="ASUS PRIME B760M-A D4"
RAM_DEVICE="ENE DRAM"

# --- 1. Hub Rise Mode (8 fans do gabinete, Zona 1 / ADD_GEN2_1) ---
# 707090 = 48% de duty medio (calibrado em 2026-08-12 para protecao contra panes de
# sobrecorrente/hiccup no regulador do hub).
HUB_ZONE_INDEX=1
HUB_ZONE_SIZE=40
HUB_COLOR="${HUB_COLOR:-707090}"

# --- 2. Water Cooler Pichau Aqua 240X (bomba + 2 fans, Zona 3 / ADD_GEN2_3) ---
# 243330 = Branco suave com nuance esverdeada, brilho calibrado para maior presença visual
# (calibrado visualmente e aprovado pelo usuario em 2026-09-05).
COOLER_ZONE_INDEX=3
COOLER_ZONE_SIZE=40
COOLER_COLOR="${COOLER_COLOR:-243330}"

# --- 3. Memórias RAM (2 pentes ENE DRAM) ---
# 7272C0 = B/R 1.68, compensado com azul para manter o branco neutro sem amarelar.
RAM_COLOR="${RAM_COLOR:-7272C0}"

# Intervalo da reafirmacao em regime (43200s = 12h). Alongado de 30min pra 12h em
# 2026-09-09: a cada reenvio de "-m static" (mesmo sem mudanca), o controlador
# reprocessa o frame e isso causava uma piscada discreta e incomoda nas fans a
# cada 30min. 12h ainda cobre drift de firmware/sobrescrita externa, so que com
# a piscada ~24x mais rara.
REASSERT_SECONDS="${REASSERT_SECONDS:-43200}"

# Le o tamanho atual de uma zona especifica no Aura. Custa ~0,04s e nao escreve nada.
zona_tamanho_atual() {
  local idx="$1"
  openrgb --list-devices 2>/dev/null \
    | grep -o "'Aura Addressable ${idx}, LED [0-9]*'" \
    | wc -l
}

aplicar_branco() {
  # Zona 1: Hub Rise Mode (8 fans do gabinete)
  if [ "$(zona_tamanho_atual "$HUB_ZONE_INDEX")" != "$HUB_ZONE_SIZE" ]; then
    openrgb -d "$MB_DEVICE" -z "$HUB_ZONE_INDEX" -sz "$HUB_ZONE_SIZE" -c "$HUB_COLOR" -m static > /dev/null 2>&1
  else
    openrgb -d "$MB_DEVICE" -z "$HUB_ZONE_INDEX" -c "$HUB_COLOR" -m static > /dev/null 2>&1
  fi

  # Zona 3: Water Cooler Pichau Aqua 240X (bomba + 2 fans do radiador)
  if [ "$(zona_tamanho_atual "$COOLER_ZONE_INDEX")" != "$COOLER_ZONE_SIZE" ]; then
    openrgb -d "$MB_DEVICE" -z "$COOLER_ZONE_INDEX" -sz "$COOLER_ZONE_SIZE" -c "$COOLER_COLOR" -m static > /dev/null 2>&1
  else
    openrgb -d "$MB_DEVICE" -z "$COOLER_ZONE_INDEX" -c "$COOLER_COLOR" -m static > /dev/null 2>&1
  fi

  # Memórias RAM
  openrgb -d "$RAM_DEVICE" -m static -c "$RAM_COLOR" > /dev/null 2>&1
}

# ARRANQUE -- espera o servidor responder ANTES de escrever, em vez de disparar
# as cegas (substitui a "rajada de 4 aplicacoes", 2026-08-13).
#
#   POR QUE O UNIT NAO RESOLVE: `After=openrgb.service` num unit de USUARIO e
#   NO-OP. O gerenciador `systemd --user` nao enxerga unidades de SISTEMA, e o
#   openrgb.service e de sistema. Medido em 2026-08-13:
#   `systemctl --user list-unit-files openrgb.service` responde "0 unit files
#   listed". A ordenacao declarada NUNCA funcionou -- o que fechava a corrida de
#   boot de 2026-07-28 era a rajada cega, nao a dependencia.
#
#   A sonda e READ-ONLY (nao escreve no header) e confirma o que importa: o
#   servidor esta no ar E ja detectou o dispositivo Aura. Depois disso escreve
#   UMA vez em vez de quatro -- menos trafego no header, que e o objetivo de
#   seguranca deste projeto inteiro.
ARRANQUE_TENTATIVAS="${ARRANQUE_TENTATIVAS:-30}"
ARRANQUE_INTERVALO="${ARRANQUE_INTERVALO:-2}"

# Conta o dispositivo Aura no inventario. NAO usa o tamanho da zona pra isso: uma
# queda de energia pode zerar o tamanho, e ai a sonda esperaria pra sempre por uma
# condicao que so o proprio `aplicar_branco` conserta.
aura_detectado() {
  openrgb --list-devices 2>/dev/null | grep -c "^[0-9]*: ${MB_DEVICE}"
}

modo_do_aura() {
  openrgb --list-devices 2>/dev/null \
    | awk -v dev="$MB_DEVICE" '$0 ~ "^[0-9]+: " dev {f=1} f && /Modes:/ {print; exit}' \
    | grep -oE "\[[A-Za-z]+\]"
}

aguardar_openrgb() {
  local i
  for i in $(seq 1 "$ARRANQUE_TENTATIVAS"); do
    if [ "$(aura_detectado)" -gt 0 ]; then
      echo "rgb-branco: servidor OpenRGB pronto e Aura detectado (tentativa ${i})."
      return 0
    fi
    sleep "$ARRANQUE_INTERVALO"
  done
  echo "rgb-branco: AVISO -- Aura nao apareceu em $((ARRANQUE_TENTATIVAS * ARRANQUE_INTERVALO))s. Aplicando assim mesmo." >&2
  return 1
}

aguardar_openrgb
aplicar_branco

# Verificacao explicita. O --list-devices NAO imprime cor, entao isto confirma que
# o comando CHEGOU ao controlador (modo mudou pra Static), nao que a cor esta
# exata -- e o maximo verificavel por software. Antes disso, toda escrita deste
# script era cega: saida jogada em /dev/null, codigo de retorno ignorado, e uma
# falha do servidor ficaria invisivel pra sempre.
if [ "$(modo_do_aura)" = "[Static]" ]; then
  echo "rgb-branco: branco aplicado e confirmado (Aura em Static)."
else
  echo "rgb-branco: AVISO -- Aura nao confirmou modo Static apos aplicar. Sera reafirmado em ${REASSERT_SECONDS}s." >&2
fi
echo "rgb-branco: reafirmando a cada ${REASSERT_SECONDS}s."

while true; do
  sleep "$REASSERT_SECONDS"
  aplicar_branco
done
