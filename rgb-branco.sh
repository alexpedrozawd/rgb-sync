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

MB_DEVICE="ASUS PRIME B760M-A D4"
RAM_DEVICE="ENE DRAM"

# Branco do dispositivo Aura (hub das 8 fans + 2 fans do cooler).
#
# 707090 e NAO FFFFFF (2026-08-12) -- isto e mitigacao de PANE, nao estetica:
#   O hub travou 3x (2026-07-29, 07-30 e 08-12), sempre com as fans do gabinete
#   parando de girar. Antes deste projeto existir, o hub rodava o Rainbow
#   autonomo dele e NUNCA travou. O usuario apontou essa correlacao e ela e o
#   melhor indicio que temos.
#
#   A conta: no Rainbow cada LED mostra um tom saturado -- vermelho puro acende 1
#   canal, amarelo 2, e assim por diante; a media ao longo do arco-iris fica em
#   ~48% dos canais ligados. Branco pleno acende os 3 canais em 100%. Ou seja, o
#   projeto praticamente DOBROU a corrente continua pelo hub, e desde 2026-07-30
#   isso virou permanente 24/7. O hub e especificado pra 10 fans rodando OS
#   EFEITOS DELE -- branco pleno em todos os LEDs e um estado que o firmware dele
#   nunca produz sozinho, e nunca foi validado nessa condicao.
#
#   O sintoma de 2026-08-12 fecha o raciocinio: as duas panes anteriores tinham
#   cor PRESA E IMOVEL (MCU morto, retencao passiva de frame WS2812). Desta vez
#   os LEDs estavam PISCANDO -- algo ciclando: liga, atinge um limite, desliga,
#   tenta de novo. Assinatura de protecao de alimentacao em modo hiccup, nao de
#   firmware travado.
#
#   707090 = 48% de duty medio, calibrado pra bater exatamente com a corrente do
#   Rainbow que rodou meses sem uma unica pane. Nao e chute: e voltar ao ponto
#   empiricamente comprovado como seguro, mantendo branco. O azul vai mais alto
#   que R/G (0x90 vs 0x70) porque em duty reduzido o die azul do WS2812 perde
#   eficiencia antes dos outros e o branco puxa pro amarelado -- mesma
#   compensacao ja validada nas RAMs.
#
#   SE VOLTAR A TRAVAR mesmo assim: a hipotese de corrente cai, sobra o modo M/B
#   Sync em si, e o caminho passa a ser tirar o hub do header (modo autonomo pelo
#   controle IR) ou trocar o hardware. Ver docs/DIAGNOSTICO-HUB.md secao 7.
LED_COLOR="${LED_COLOR:-707090}"

# Branco das RAMs, CALIBRADO SEPARADO -- nao e capricho.
#   `FFFFFF` significa "R, G e B no duty maximo", e isso NAO produz branco neutro
#   num LED RGB: os tres dies tem eficiencias diferentes e o azul e tipicamente o
#   mais fraco. Nas RAMs (controlador ENE DRAM) o resultado foi visivelmente
#   AMARELADO -- R+G dominando. Reportado pelo usuario olhando o hardware em
#   2026-07-30.
#
#   A correcao e subir o azul em relacao a R e G. Em 2026-07-30, com o conjunto
#   em brilho alto, D0D0FF resolveu -- proporcao B/R = 1.23.
#
#   ATENCAO -- A COMPENSACAO NAO ESCALA LINEARMENTE COM O BRILHO. Em 2026-08-12,
#   ao acompanhar o escurecimento do Aura pra 48% de duty, a primeira tentativa
#   foi 72728B, que preserva exatamente a mesma proporcao B/R = 1.22. Ficou
#   VISIVELMENTE AMARELADO. Motivo: em duty reduzido o die azul do WS2812 perde
#   eficiencia MAIS RAPIDO que os outros dois, entao quanto mais escuro, MAIS
#   compensacao e preciso -- nao a mesma.
#
#   7272C0 = B/R 1.68, calibrado visualmente a 48% de duty em tres rodadas:
#     72728B (B/R 1.22) -> bem amarelado
#     7272AC (B/R 1.51) -> ainda um pouco amarelado
#     7272C0 (B/R 1.68) -> neutro, aprovado com o hardware a vista
#   Se um dia mudar o brilho, RECALIBRE: nao reaproveite a proporcao do brilho
#   anterior. Amarelado ainda -> suba o azul. Azulado/frio -> desca.
#
#   As RAMs NAO fazem parte do problema de corrente do hub (sao alimentadas pelos
#   slots DIMM, nao pelo Molex do hub). O escurecimento aqui e puramente pra
#   manter o conjunto visualmente uniforme com as fans.
RAM_COLOR="${RAM_COLOR:-7272C0}"

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
  openrgb -d "$RAM_DEVICE" -m static -c "$RAM_COLOR" > /dev/null 2>&1
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
