# Logs brutos dos incidentes

Extratos do `journalctl` das janelas citadas em
[`../DIAGNOSTICO-HUB.md`](../DIAGNOSTICO-HUB.md). Guardados aqui porque o
journal rotaciona e essa evidência não é reproduzível depois.

| Arquivo | Conteúdo |
|---|---|
| `gpu-rgb-sync-historico-completo.log` | Todo o histórico do serviço, todos os boots |
| `incidente-2026-07-27-travamento-total-fim-do-boot.log` | Fim do boot que travou o PC inteiro ao apertar `ON M/B` com a zona sem sinal. O log simplesmente para, sem panic |
| `incidente-2026-07-29-hub-travado.log` | Janela em que o hub travou e as fans pararam de girar. Note a sessão de GPU ativa 09:46:07 → 10:05:15 (19min contínuos, ~114 comandos ao hub) |
| `incidente-2026-07-29-perda-sync-pos-reboot.log` | Perda de sync após reboot limpo. Evidência central: header em branco por 2h08min, ignorado pelo hub |
| `boots.log` | Lista de boots, para correlacionar |
| `openrgb-list-devices.log` | Inventário de dispositivos, zonas e modos |

## ⚠️ Antes de adicionar novos logs aqui

**Este repositório é público.** Logs do `journalctl` vazam com facilidade:
IP público, prefixo IPv6 da conexão, IPs da tailnet, LAN, MACs, UUID de
partição. Os arquivos atuais foram sanitizados — os endereços aparecem como
`<IP-REDIGIDO>`, `<IPV6-REDIGIDO>` etc.

Ao regenerar, sanitize antes de commitar:

```bash
sed -i -E \
  -e 's/\b100\.([0-9]{1,3}\.){2}[0-9]{1,3}\b/<IP-TAILSCALE-REDIGIDO>/g' \
  -e 's/\b(192\.168|10)\.([0-9]{1,3}\.)+[0-9]{1,3}\b/<IP-LAN-REDIGIDO>/g' \
  -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<IP-REDIGIDO>/g' \
  -e 's/\b([0-9a-fA-F]{1,4}:){3,}[0-9a-fA-F]{1,4}\b/<IPV6-REDIGIDO>/g' \
  -e 's/UUID=[0-9a-fA-F-]{36}/UUID=<REDIGIDO>/g' \
  *.log
```

> A regex de IPv6 exige **3 ou mais** dois-pontos de propósito: um timestamp
> `HH:MM:SS` tem só 2 e precisa ser preservado. Uma versão anterior deste
> comando era mais frouxa e apagou todos os horários dos logs.

Depois, confira: `grep -rE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" .` deve sair vazio.
