#!/bin/bash
# install.sh -- deixa o rgb-branco funcionando do zero (Bazzite/Fedora ostree).
# Idempotente: pode rodar de novo a qualquer momento so pra conferir/corrigir o
# estado atual. Pensado pro cenario "formatei o PC, so quero rodar isso e
# funcionar igual antes".
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$PROJECT_DIR/rgb-branco.sh"
USER_UNIT_SRC="$PROJECT_DIR/systemd/rgb-branco.service"
USER_UNIT_DST="$HOME/.config/systemd/user/rgb-branco.service"
OPENRGB_OVERRIDE_SRC="$PROJECT_DIR/systemd/openrgb-server-override.conf"
OPENRGB_OVERRIDE_DIR="/etc/systemd/system/openrgb.service.d"
OPENRGB_OVERRIDE_DST="$OPENRGB_OVERRIDE_DIR/override.conf"

# Nome da unidade antiga, de quando o projeto sincronizava com a GPU. Removida
# aqui pra nao ficarem os dois servicos disputando os mesmos LEDs.
UNIT_ANTIGA="gpu-rgb-sync.service"
UNIT_ANTIGA_DST="$HOME/.config/systemd/user/$UNIT_ANTIGA"

echo "== rgb-branco: instalador =="
echo

# --- 0. Migracao: remove o servico antigo (gpu-rgb-sync) se ainda existir ------
if systemctl --user cat "$UNIT_ANTIGA" >/dev/null 2>&1 || [ -f "$UNIT_ANTIGA_DST" ]; then
  echo "Encontrado o servico antigo '$UNIT_ANTIGA' -- removendo."
  echo "  (o projeto mudou: nao ha mais sincronia com a GPU, e os dois brigariam"
  echo "   pelos mesmos LEDs se ficassem ativos ao mesmo tempo)"
  systemctl --user disable --now "$UNIT_ANTIGA" >/dev/null 2>&1 || true
  rm -f "$UNIT_ANTIGA_DST"
  systemctl --user daemon-reload
  echo "[ok] $UNIT_ANTIGA desabilitado e removido"
else
  echo "[ok] nenhum servico antigo pra migrar"
fi

# --- 1. OpenRGB precisa estar instalado no sistema (pacote via rpm-ostree) ---
if ! command -v openrgb >/dev/null 2>&1; then
  echo "OpenRGB nao encontrado no sistema."
  echo "Isso e uma mudanca de sistema (rpm-ostree layer) -- so prossiga se voce"
  echo "entende o impacto: cria uma camada na imagem ostree e exige reboot."
  read -r -p "Instalar 'openrgb' via 'sudo rpm-ostree install openrgb' agora? [s/N] " resp
  if [[ "$resp" =~ ^[sS]$ ]]; then
    sudo rpm-ostree install openrgb
    echo
    echo ">>> Pacote na fila. REINICIE o sistema e rode este instalador de novo"
    echo ">>> (o binario so aparece na proxima imagem apos o boot)."
    exit 0
  else
    echo "Abortando -- o OpenRGB e obrigatorio para o resto do instalador."
    exit 1
  fi
fi
echo "[ok] openrgb instalado: $(command -v openrgb)"

# --- 2. Servidor OpenRGB restrito a localhost (seguranca: default do pacote e 0.0.0.0) ---
if [ ! -f "$OPENRGB_OVERRIDE_DST" ] || ! cmp -s "$OPENRGB_OVERRIDE_SRC" "$OPENRGB_OVERRIDE_DST"; then
  echo "Aplicando override de seguranca em openrgb.service (bind 127.0.0.1)..."
  sudo mkdir -p "$OPENRGB_OVERRIDE_DIR"
  sudo cp "$OPENRGB_OVERRIDE_SRC" "$OPENRGB_OVERRIDE_DST"
  sudo systemctl daemon-reload
else
  echo "[ok] override de seguranca do openrgb.service ja aplicado"
fi

if systemctl is-active --quiet openrgb.service && systemctl is-enabled --quiet openrgb.service; then
  echo "[ok] openrgb.service ja ativo e habilitado"
else
  sudo systemctl enable --now openrgb.service
  echo "[ok] openrgb.service ativo"
fi

# --- 3. Servico do usuario (aplica branco e reafirma) --------------------------
mkdir -p "$(dirname "$USER_UNIT_DST")"
sed "s#{{SCRIPT_PATH}}#$SCRIPT_PATH#" "$USER_UNIT_SRC" > "$USER_UNIT_DST"
systemctl --user daemon-reload
systemctl --user reenable rgb-branco.service >/dev/null
systemctl --user restart rgb-branco.service
echo "[ok] rgb-branco.service (usuario) ativo, apontando para $SCRIPT_PATH"

echo
echo "== Instalacao concluida =="
echo "Em ate ~30s tudo deve estar em BRANCO e ficar assim permanentemente:"
echo "  8 fans do gabinete + 2 fans do water cooler + 2 RAMs."
echo
echo "Se as 8 fans do gabinete NAO acenderem em branco, o hub Rise Mode esta fora"
echo "do modo 'M/B Sync' -- ele ignora o header da placa-mae e roda o Rainbow"
echo "autonomo dele. Pra voltar, aperte 'ON M/B' no controle IR do hub. Faca isso"
echo "SO depois de confirmar que as fans do cooler ja estao em branco (ou seja,"
echo "que existe sinal valido no header): apertar o botao com a zona sem sinal"
echo "travou o PC inteiro uma vez, em 2026-07-27."
echo
echo "Com este desenho o header carrega branco valido o tempo todo, inclusive"
echo "durante o boot -- o que da a melhor chance de o sync sobreviver a reboots."
echo "Ver README.md e docs/DIAGNOSTICO-HUB.md."
