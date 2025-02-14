#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar

# ---------------------------
# CONFIGURATION MASTER
# ---------------------------
export CONFIG_ROOT="/opt/vpn_stack"
export VPN_TYPES=("wireguard" "openvpn" "v2ray" "trojan")
export MAIN_DOMAIN="vpn.example.com"
export ADMIN_EMAIL="admin@example.com"
export DATA_DIR="$CONFIG_ROOT/data"
export LOG_DIR="/var/log/vpn_stack"

# Création de l'arborescence
mkdir -p "$CONFIG_ROOT"/{configs,scripts,templates,certs,backups}
mkdir -p "$DATA_DIR"/{users,stats,profiles}
mkdir -p "$LOG_DIR"
mkdir -p /etc/{fail2ban,supervisor/conf.d}

# ---------------------------
# FONCTIONS PRINCIPALES
# ---------------------------
install_dependencies() {
  apt-get update && apt-get install -y \
    docker.io docker-compose jq python3-pip \
    certbot nginx fail2ban wireguard-tools \
    qrencode build-essential libssl-dev
  
  pip3 install flask requests cryptography
  snap install --classic certbot
}

configure_firewall() {
  ufw reset --force
  ufw default deny incoming
  ufw allow 22,80,443,51820,1194/tcp
  ufw allow 51820,1194/udp
  ufw enable

  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  iptables -A FORWARD -i eth0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
}

setup_automatic_configs() {
  # Génération des templates de configuration
  for vpn_type in "${VPN_TYPES[@]}"; do
    envsubst < "$CONFIG_ROOT/templates/${vpn_type}.conf.tpl" > "$CONFIG_ROOT/configs/${vpn_type}_server.conf"
  done

  # Configuration auto-certificats
  certbot certonly --standalone -d "$MAIN_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL"
  ln -s "/etc/letsencrypt/live/$MAIN_DOMAIN" "$CONFIG_ROOT/certs/live"
}

deploy_vpn_services() {
  # Déploiement Docker-compose
  envsubst < "$CONFIG_ROOT/templates/docker-compose.yml.tpl" > "$CONFIG_ROOT/docker-compose.yml"
  docker-compose -f "$CONFIG_ROOT/docker-compose.yml" up -d

  # Synchronisation des configurations
  rsync -avz "$CONFIG_ROOT/configs/" /etc/ > /dev/null 2>&1
  systemctl restart supervisor.service
}

setup_automation() {
  # Création des services systemd
  cat > /etc/systemd/system/vpn-automation.service <<EOF
[Unit]
Description=VPN Automation Service
After=network.target

[Service]
ExecStart=$CONFIG_ROOT/scripts/auto_update.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  # Script d'auto-maintenance
  cat > "$CONFIG_ROOT/scripts/auto_update.sh" <<'EOF'
#!/bin/bash
while true; do
  certbot renew --quiet
  docker-compose -f $CONFIG_ROOT/docker-compose.yml pull
  rsync -av --delete $CONFIG_ROOT/backups/ backup-server:/vpn-backups/
  sleep 86400
done
EOF

  systemctl daemon-reload
  systemctl enable --now vpn-automation.service
}

# ---------------------------
# DÉPLOIEMENT INTELLIGENT
# ---------------------------
main() {
  echo "🛠  Démarrage de l'installation automatisée..."
  
  # Vérification des prérequis
  command -v git || install_dependencies

  # Configuration réseau
  configure_firewall
  setup_automatic_configs

  # Déploiement des services
  deploy_vpn_services

  # Automatisation et monitoring
  setup_automation
  deploy_monitoring_stack

  echo "✅ Installation terminée! Accès admin: https://$MAIN_DOMAIN/admin"
}

# ---------------------------
# FONCTIONS AVANCÉES
# ---------------------------
deploy_monitoring_stack() {
  docker run -d --name prometheus \
    -v "$CONFIG_ROOT/configs/prometheus.yml":/etc/prometheus/prometheus.yml \
    -p 9090:9090 prom/prometheus

  docker run -d --name grafana \
    -v "$DATA_DIR/stats":/var/lib/grafana \
    -p 3000:3000 grafana/grafana

  curl -X POST -H "Content-Type: application/json" \
    -d @"$CONFIG_ROOT/templates/grafana-dashboard.json" \
    http://admin:admin@localhost:3000/api/dashboards/db
}

generate_client_config() {
  local vpn_type=$1
  local user_id=$2
  
  case $vpn_type in
    wireguard)
      wg genkey | tee "$DATA_DIR/users/$user_id.priv" | wg pubkey > "$DATA_DIR/users/$user_id.pub"
      envsubst < "$CONFIG_ROOT/templates/wg-client.conf.tpl" > "$DATA_DIR/profiles/$user_id.conf"
      qrencode -t ansiutf8 < "$DATA_DIR/profiles/$user_id.conf"
      ;;
    openvpn)
      easyrsa build-client-full "$user_id" nopass
      ovpn_getclient "$user_id" > "$DATA_DIR/profiles/$user_id.ovpn"
      ;;
  esac
}

# ---------------------------
# EXÉCUTION PRINCIPALE
# ---------------------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ Exécuter en tant que root!" 
  exit 1
fi

# Détection automatique de l'environnement
[[ -f /.dockerenv ]] && export IS_CONTAINERIZED=true || export IS_CONTAINERIZED=false

main "$@"
