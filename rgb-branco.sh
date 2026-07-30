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
#   Contrapartida honesta: branco pleno e o estado de CORRENTE MAXIMA do array
#   (~60 mA por LED), e agora ele e permanente, 24/7, em vez de so sob carga. Se
#   a hipotese de que o travamento de 2026-07-29 veio de corrente sustentada
#   estiver certa, essa exposicao aumentou. Nao ha como mitigar por cor sem
#   estragar o branco (cinza neutro da branco AMARELADO nesse hardware -- ver
#   docs/DIAGNOSTICO-HUB.md). O caminho, se precisar, e o botao de brilho do
#   controle IR do hub, que reduz a corrente sem tocar no header.
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

MB_DEVICE="ASUS PRIME B760M-A D4"
RAM_DEVICE="ENE DRAM"

# Unica cor do projeto. Branco pleno.
LED_COLOR="FFFFFF"

# Zona 3 = hub das 8 fans + 2 fans do cooler.
#
# ATENCAO ao FAN_ZONE_SIZE=40: NAO e uma contagem de LEDs. Foi escolhido mandando
#   -sz 40 e observando "acendeu tudo uniforme, sem ponta apagada" -- mas com uma
#   COR UNICA esse teste nao pode falhar, qualquer tamanho parece certo. Medindo
#   depois: com a zona em tamanho 1 as fans do cooler acendem INTEIRAS, o que e
#   impossivel numa cadeia de 40 LEDs enderecaveis. Mantido em 40 porque funciona;
#   nao tratar como medicao. Ver docs/DIAGNOSTICO-HUB.md, secao 3.
FAN_ZONE_INDEX=3
FAN_ZONE_SIZE=40

# Rotulo dos LEDs dessa zona em `openrgb --list-devices`, usado pra LER o tamanho
# antes de reescreve-lo. Nao e derivavel do indice: a zona 0 e a "Aura Mainboard",
# entao indice 3 <-> "Aura Addressable 3" e coincidencia, nao regra.
FAN_ZONE_LED_LABEL="Aura Addressable ${FAN_ZONE_INDEX}, LED "

# Intervalo da reafirmacao em regime. Existe por dois motivos, os dois reais:
#   (1) drift -- o controlador Aura ou as RAMs podem voltar sozinhos pro efeito de
#       fabrica (ja observado no projeto);
#   (2) se alguem mexer nos LEDs por fora (GUI do OpenRGB, outro software), isso
#       reverte sozinho em ate REASSERT_SECONDS.
# 1800s = 2 escritas por hora no header. Ordens de magnitude abaixo do que travou
# o hub. Sobrescrevivel por variavel de ambiente pra teste/afinacao.
REASSERT_SECONDS="${REASSERT_SECONDS:-1800}"

# Le o tamanho atual da zona do hub. Custa ~0,04s como cliente e NAO escreve nada
# no hardware -- barato o bastante pra checar antes de cada aplicacao.
#
# `grep -o | wc -l`, NAO `grep -c`: o --list-devices imprime todos os LEDs numa
# UNICA linha, entao grep -c retornaria 1, o teste nunca casaria e o resize
# dispararia sempre. Falha silenciosa; ja aconteceu ao escrever esta funcao.
zona_tamanho_atual() {
  openrgb --list-devices 2>/dev/null \
    | grep -o "'${FAN_ZONE_LED_LABEL}[0-9]*'" \
    | wc -l
}

aplicar_branco() {
  # O tamanho da zona fica gravado no controlador Aura e sobrevive a reboot, mas
  # uma queda de energia pode zerar. Rede de seguranca: LE antes e so reescreve se
  # estiver errado. Redimensionar reconfigura o canal do header, e mais invasivo
  # que trocar cor -- nao convem fazer de graca em toda reafirmacao.
  if [ "$(zona_tamanho_atual)" != "$FAN_ZONE_SIZE" ]; then
    openrgb -d "$MB_DEVICE" -z "$FAN_ZONE_INDEX" -sz "$FAN_ZONE_SIZE" -c "$LED_COLOR" -m static > /dev/null 2>&1
  fi
  # Um comando por dispositivo. No Aura, o comando no dispositivo INTEIRO ja cobre
  # a zona 3: `-c` com cor unica replica ela em todos os LEDs ("If there are more
  # LEDs than colors given, the last color will be applied to the remaining LEDs"
  # -- openrgb --help). Nao precisa de um segundo comando por zona.
  openrgb -d "$MB_DEVICE" -m static -c "$LED_COLOR" > /dev/null 2>&1
  openrgb -d "$RAM_DEVICE" -m static -c "$LED_COLOR" > /dev/null 2>&1
}

# Rajada de arranque: fecha a corrida de boot em que o dispositivo Aura ainda nao
# esta pronto no OpenRGB quando o servico sobe -- bug real de 2026-07-28, em que as
# RAMs acendiam e o resto ficava apagado porque o unico comando falhou em silencio.
# 4 aplicacoes no 1o minuto e trafego irrisorio; o perigoso era 6 por minuto
# sustentado por 19 minutos.
for espera in 0 10 20 30; do
  sleep "$espera"
  aplicar_branco
done
echo "rgb-branco: branco aplicado (rajada de arranque concluida)."
echo "rgb-branco: reafirmando a cada ${REASSERT_SECONDS}s."

while true; do
  sleep "$REASSERT_SECONDS"
  aplicar_branco
done
