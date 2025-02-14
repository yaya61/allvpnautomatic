# Dockerfile
FROM ubuntu:latest

# Variables d'environnement
ENV DEBIAN_FRONTEND=noninteractive

# Installation des dépendances
RUN apt-get update && apt-get install -y \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    curl \
    git \
    build-essential \
    iptables \
    ufw \
    supervisor \
    fail2ban \
    asterisk \
    python3 \
    net-tools \
    iproute2 \
    wireguard \
    openvpn \
    resolvconf \
    libsodium-dev \
    && rm -rf /var/lib/apt/lists/*

# Installation des outils VPN
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @v2fly/v2ray-core \
    && go install github.com/shadowsocks/v2ray-plugin@latest \
    && go install github.com/p4gefau1t/trojan-go@latest

# Configuration de l'optimisation réseau
COPY sysctl.conf /etc/sysctl.conf
RUN sysctl -p

# Configuration de Supervisord
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Configuration des VPN
RUN mkdir -p /etc/wireguard /etc/openvpn /etc/v2ray /etc/trojan-go

# Scripts de configuration automatique
COPY configure-vpns.sh /usr/local/bin/
COPY generate-client-configs.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Configuration Fail2Ban
COPY jail.local /etc/fail2ban/jail.local
COPY filter-vpn.conf /etc/fail2ban/filter.d/vpn.conf

# Configuration Asterisk
COPY asterisk.conf /etc/asterisk/asterisk.conf
COPY sip.conf /etc/asterisk/sip.conf

# Ports exposés
EXPOSE 51820/udp 1194/udp 443/tcp 80/tcp 5060/udp 5061/tcp

# Démarrage des services
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
