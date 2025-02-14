# 1. Télécharger les templates
git clone https://github.com/yaya61/allvpnautomatic.git $CONFIG_ROOT/templates

# 2. Exécuter le script
chmod +x deploy.sh
./deploy.sh

# 3. Générer un profil client
./deploy.sh generate-client-config wireguard user123
