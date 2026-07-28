#!/bin/bash
# install.sh -- deixa o gpu-rgb-sync funcionando do zero (Bazzite/Fedora ostree).
# Idempotente: pode rodar de novo a qualquer momento so pra conferir/corrigir o
# estado atual. Pensado pro cenario "formatei o PC, so quero rodar isso e
# funcionar igual antes".
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$PROJECT_DIR/gpu-rgb-sync.sh"
USER_UNIT_SRC="$PROJECT_DIR/systemd/gpu-rgb-sync.service"
USER_UNIT_DST="$HOME/.config/systemd/user/gpu-rgb-sync.service"
OPENRGB_OVERRIDE_SRC="$PROJECT_DIR/systemd/openrgb-server-override.conf"
OPENRGB_OVERRIDE_DIR="/etc/systemd/system/openrgb.service.d"
OPENRGB_OVERRIDE_DST="$OPENRGB_OVERRIDE_DIR/override.conf"

echo "== gpu-rgb-sync: instalador =="
echo

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

# --- 3. Servico do usuario (o loop que decide ligar/apagar) ---
mkdir -p "$(dirname "$USER_UNIT_DST")"
sed "s#{{SCRIPT_PATH}}#$SCRIPT_PATH#" "$USER_UNIT_SRC" > "$USER_UNIT_DST"
systemctl --user daemon-reload
systemctl --user enable --now gpu-rgb-sync.service
echo "[ok] gpu-rgb-sync.service (usuario) ativo, apontando para $SCRIPT_PATH"

echo
echo "== Instalacao concluida =="
echo "Os LEDs devem estar apagados agora (estado padrao ocioso)."
echo "Teste abrindo um jogo, uma carga do ap-ai-studio ou um LLM do ap-tech-team:"
echo "os 8 fans do gabinete + water cooler + RAMs devem acender em branco em"
echo "poucos segundos, e apagar ~60s depois que a GPU ficar ociosa."
echo
echo "IMPORTANTE -- so depois de uma queda de energia TOTAL (nao um reboot normal):"
echo "o hub Rise Mode pode sair do modo 'M/B Sync' e ignorar o header da placa-mae."
echo "Antes de apertar o botao 'ON M/B' no controle do hub pra voltar, rode este"
echo "instalador de novo (ou so abra um jogo) pra garantir que ja existe sinal"
echo "valido no header no momento do aperto -- ver README.md, secao"
echo "'Depois de uma queda de energia total'."
