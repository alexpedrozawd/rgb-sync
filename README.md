# rgb-sync

Mantém toda a iluminação ARGB do PC em **branco estático permanente**: sem
efeitos, sem transições, um estado só, 24/7.

Cobre: 8 fans do gabinete (hub Rise Mode), 2 fans do radiador do water cooler
(Pichau Aqua 240X) e 2 pentes de RAM. Não controla velocidade/RPM de fan nem o
display de temperatura do water cooler — só a luz, via [OpenRGB](https://openrgb.org/).

Ver também: [`pichau-aqua-240x-linux-driver`](../pichau-aqua-240x-linux-driver)
— driver separado, do display de temperatura do pump (LCD), não da luz ARGB.

## Histórico do projeto

Até 2026-07-29 o script sincronizava com a GPU (branco sob carga, apagado em
idle). Removido por preferência do dono: branco permanente é mais simples,
mais seguro (header nunca fica mudo, tráfego cai de ~360/h para 2/h) e
incomoda menos de dia. A sincronia com GPU, detecção NVIDIA/AMD e limiares de
atividade saíram do projeto — seguem no histórico do git se precisar.

### ✅ Travamentos do hub — RESOLVIDO, era defeito de hardware

Entre 2026-07-29 e 2026-08-12 o hub Rise Mode (8 fans do gabinete) travou 3
vezes: controle remoto sem resposta, cor presa ou piscando, e ao menos uma vez
as fans pararam de girar (risco térmico). RAMs e water cooler nunca falharam.

Foram investigadas várias hipóteses de software (excesso de comandos,
corrente sustentada em branco pleno, backfeed de 5V entre header e hub — ver
[`docs/DIAGNOSTICO-HUB.md`](docs/DIAGNOSTICO-HUB.md) para o diagnóstico
completo). **Nenhuma era a causa real: a controladora do hub estava com
defeito.** Trocada a controladora, o hub voltou a funcionar normalmente. A cor
a 48% de duty (`HUB_COLOR=707090`) foi mantida por preferência visual, não por
necessidade de segurança.

**RPM e rotação das 8 fans do gabinete** são controladas pela própria
controladora do hub Rise Mode, fora do sistema operacional — este projeto não
monitora nem controla velocidade de fan, só cor.

## Hardware e topologia

| Componente | Modelo | Conexão / Zona |
|---|---|---|
| Placa-mãe | ASUS PRIME B760M-A D4 | Controlador Aura USB HID (`0B05:19AF`) |
| Hub de fans (8x, gabinete) | Rise Mode Galaxy Glass Standard V2 | Header 1 (`ADD_GEN2_1` / Zona 1) |
| Water cooler | Pichau Aqua 240X (bomba + 2 fans) | Header 3 (`ADD_GEN2_3` / Zona 3) |
| RAM | 2 pentes "ENE DRAM" | SMBus I801 (`0x71` e `0x73`) |

Topologia medida e confirmada em 2026-09-05. Header 2 (Zona 2) está vazio.

> **Por que a separação de headers importa:** antes, a Zona 1 ficava com
> tamanho 0 (sem sinal) e o MCU do hub travava ao ler o header sem dados via
> `ON M/B`. Hoje ambas Zonas 1 e 3 recebem sinal válido contínuo desde o boot
> (tamanho 40), o que previne esse travamento.

## Instalação

Requisitos: Fedora/Bazzite (ou qualquer systemd + `rpm-ostree`), a mesma placa
ASUS PRIME B760M-A D4, sudo.

```bash
cd ~/Projetos/rgb-sync
./install.sh
```

Idempotente — rodar de novo só confere/corrige o que falta. O instalador:

1. Remove o serviço antigo `gpu-rgb-sync.service`, se existir.
2. Confere/instala `openrgb` (pergunta antes de `rpm-ostree install
   "openrgb-1.0*"` — camada ostree, exige reboot).
3. Restringe o servidor OpenRGB a `127.0.0.1` (padrão do pacote é `0.0.0.0`).
4. Garante `/etc/openrgb` para o daemon.
5. Habilita `openrgb.service` (sistema, root, fala com o hardware).
6. Instala e habilita `rgb-branco.service` (usuário) e a regra de limpeza de
   logs em `~/.config/user-tmpfiles.d/openrgb-logs.conf`.

Em até ~30s tudo deve estar branco e calibrado.

## Como funciona

O script [`rgb-branco.sh`](rgb-branco.sh) roda em segundo plano:

1. **Sonda de arranque** — aguarda o servidor OpenRGB responder e confirmar o
   controlador Aura antes de escrever (até 30x2s). Elimina corrida de boot.
2. **Aplicação com proteção de canal** — lê o tamanho das Zonas 1 e 3 antes de
   escrever; se zerado (ex.: corte de energia), reconfigura para 40 LEDs;
   senão só atualiza a cor, sem reconfiguração invasiva de canal.
3. **Regime** — reafirma o estado a cada `REASSERT_SECONDS` (12h) contra drift
   de firmware ou sobrescrita externa. Alongado de 30min para 12h em
   2026-09-09: cada reenvio de `-m static` causava uma piscada discreta nas
   fans; em 12h a proteção contra drift continua, só que bem mais rara.

### Cores calibradas por dispositivo

| Dispositivo | Zona | Cor | Motivo |
|---|---|---|---|
| Hub Rise Mode (8 fans) | 1 (`ADD_GEN2_1`) | `HUB_COLOR=707090` | 48% de duty — brilho reduzido por preferência visual |
| Water Cooler (bomba + 2 fans) | 3 (`ADD_GEN2_3`) | `COOLER_COLOR=243330` | Branco suave esverdeado, calibrado visualmente |
| RAM (2x ENE DRAM) | — | `RAM_COLOR=7272C0` | Compensação de azul (B/R 1.68) — evita tom amarelado por perda de eficiência do die azul em duty reduzido |

Todas sobrescrevíveis por variável de ambiente no `rgb-branco.service` ou no
ambiente do script.

## Se as 8 fans do gabinete não estiverem brancas

O hub saiu do modo "M/B Sync" e está no Rainbow autônomo dele, ignorando o
header.

1. Confirme sinal válido no header: as 2 fans do cooler devem estar brancas.
   Se não estiverem, rode `./install.sh` de novo.
2. Aperte `ON M/B` no controle IR do hub.

> ⚠️ Apertar o botão com a zona **sem** sinal (tamanho 0) já travou o sistema
> inteiro uma vez (2026-07-27). Com o desenho atual o header sempre tem sinal,
> então essa condição só ocorre se o serviço estiver parado.

## Como remapear zonas (se trocar hub/cooler/placa)

1. `systemctl --user stop rgb-branco.service`
2. `openrgb --list-devices`
3. Teste cor por zona:
   ```bash
   openrgb -d "ASUS" -z 1 -sz 8 -c FF0000 -m static   # zona 1 = vermelho
   openrgb -d "ASUS" -z 2 -sz 8 -c 00FF00 -m static   # zona 2 = verde
   openrgb -d "ASUS" -z 3 -sz 8 -c 0000FF -m static   # zona 3 = azul
   ```
4. **Não** meça o total de LEDs subindo `-sz` até "acender uniforme" — com cor
   única esse teste não pode falhar (foi assim que o "40" entrou sem base).
   `-c` com lista de cores só funciona sem efeito, e `-m direct` apaga o
   header neste hardware. Na prática: qualquer tamanho ≥1 funciona.
5. Atualize `FAN_ZONE_INDEX`/`FAN_ZONE_SIZE` em `rgb-branco.sh`.
6. `systemctl --user restart rgb-branco.service`

## Arquivos

- `rgb-branco.sh` — o script (aplica branco e reafirma).
- `install.sh` — instalador idempotente, com migração do serviço antigo.
- `systemd/rgb-branco.service` — unidade de usuário (template; o instalador
  substitui `{{SCRIPT_PATH}}`).
- `systemd/openrgb-server-override.conf` — restringe `openrgb.service` a
  `127.0.0.1`.

## Não óbvio, vale saber antes de mexer

- **Cinza neutro (R=G=B, ex. `A0A0A0`) dá branco amarelado** neste hardware, não
  mais suave — o die azul do WS2812 perde eficiência primeiro em duty
  reduzido. Por isso `HUB_COLOR` e `RAM_COLOR` compensam com mais azul em vez
  de simplesmente escurecer igual nos 3 canais.
- Corrida de boot é mitigada pela sonda de arranque (`aguardar_openrgb`), não
  por dependência de systemd — `After=openrgb.service` num unit de **usuário**
  é no-op, porque `systemd --user` não enxerga units de **sistema**.

## Desinstalar

```bash
systemctl --user disable --now rgb-branco.service
rm ~/.config/systemd/user/rgb-branco.service
systemctl --user daemon-reload
```

`openrgb.service` e o pacote `openrgb` podem ficar parados sem problema; para
remover: `sudo systemctl disable --now openrgb.service` e
`sudo rpm-ostree uninstall openrgb` (exige reboot).
