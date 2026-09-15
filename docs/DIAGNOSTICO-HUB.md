# Diagnóstico: hub de fans perdia o modo "M/B Sync" e travava

**Status: RESOLVIDO.** Causa raiz: defeito de hardware na controladora do hub
Rise Mode. Trocada a controladora, nunca mais travou. Documento mantido como
registro do que foi investigado e descartado — útil se um problema parecido
aparecer de novo em outro componente.

Logs brutos das janelas citadas: [`logs/`](logs/).

## Resumo

RAMs e water cooler sempre obedeceram 100% dos comandos. Só o hub Rise Mode (8
fans do gabinete) falhava: perdia o modo "M/B Sync" sozinho em eventos de
energia/reboot (só recuperável pelo botão físico `ON M/B` no controle IR), e
travou por completo 3 vezes em 14 dias (2026-07-29, 2026-07-30, 2026-08-12) —
controle remoto sem resposta, cor presa ou piscando, e ao menos uma vez as
fans pararam de girar (risco térmico real).

**Causa real: defeito na controladora do hub.** Todas as hipóteses de software
abaixo foram investigadas a fundo e descartadas — a correlação com branco
pleno era real, mas não causal.

## Hipóteses investigadas (todas descartadas)

| Hipótese | Por que parecia plausível | Por que caiu |
|---|---|---|
| Firmware afogado em comando repetido | Travamento de 07-29 ocorreu após ~114 comandos em 19min | Tráfego reduzido 180x (2 escritas/hora) e o hub travou mesmo assim (07-30) |
| Corrente sustentada (branco pleno = 100% dos canais vs. ~48% do Rainbow) | Hub nunca travava em Rainbow, só depois do projeto forçar branco 24/7 | Mitigado a 48% de duty (`707090`) em 2026-08-12, após a 3ª pane. Nunca chegou a ser invalidada por nova pane — a causa real (controladora com defeito) só foi identificada depois, por troca de hardware |
| Backfeed de 5V (header da placa + Molex do hub em paralelo) | Padrão documentado na comunidade, explicaria o piscar (proteção de corrente oscilando) | Nunca confirmado por multímetro; controladora trocada resolveu sem tocar na fiação |
| Ausência de sinal no header (hub "perdido" por falta de dado) | Coincidiu com o travamento de 2026-07-27 | **Refutada por medição:** header ficou 54min58s em `Off` e o hub continuou obedecendo depois |
| Falha no host (kernel/USB/I2C/udev) | — | Auditoria completa (2026-08-13): zero eventos USB/I2C anômalos, sem conflito de software, sem regra udev tocando o Aura |

## O que ficou medido e continua válido

- **Topologia real (confirmada 2026-09-05):** Zona 1 (`ADD_GEN2_1`) = hub de
  fans do gabinete; Zona 3 (`ADD_GEN2_3`) = water cooler (bomba + 2 fans do
  radiador); Zona 2 vazia. O cooler **não** está a jusante do hub — continuou
  obedecendo mesmo com o hub em Rainbow autônomo.
- **`FAN_ZONE_SIZE` não tem efeito observável entre 1 e 120** — só `0` importa
  (zona muda, header sem sinal). O valor "40" em uso não é uma contagem física
  real de LEDs, é só um tamanho que funciona.
- **Modo `Direct` do OpenRGB apaga o header** neste hardware — não serve como
  alternativa ao `static`.
- **LED aceso não prova hub vivo.** WS2812 retém a última cor recebida
  indefinidamente sem sinal contínuo — por isso "cor presa" e "travado" podem
  parecer iguais visualmente.
- **Não há telemetria de RPM para as fans do hub** exposta ao SO (sem
  `nct6775`/`it87`; único sensor de fan do sistema é da GPU). Isso nunca foi
  resolvido por software — hoje é responsabilidade da própria controladora do
  hub, que gerencia RPM fora do SO.
- **Orçamento de corrente do header:** `ADD_GEN2` é 5V/3A máx (~50 LEDs em
  branco pleno a 60mA/LED). A alimentação real do hub vem do Molex, não do
  header — um splitter passivo jogaria toda a corrente no header e
  provavelmente estouraria esse orçamento; não foi testado, ficou descartado
  como direção antes da troca da controladora resolver o problema.
