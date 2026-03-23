#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Eir Sandbox Initialization Script (OpenEMR Multi-Site)      ║
# ╚══════════════════════════════════════════════════════════════╝

echo "🏥 Initializing Eir (OpenEMR) Sandbox Environment..."

# 1. Verification of the Database Container
if ! docker ps | grep -q asgard_mariadb; then
    echo "❌ ERROR: asgard_mariadb is not running! Start the Asgard core profile first."
    exit 1
fi

# 2. Verification of the Eir Container 
if ! docker ps | grep -q asgard_eir; then
    echo "❌ ERROR: asgard_eir is not running! Execute 'docker compose --profile full up -d' first."
    exit 1
fi

echo "✅ Dependent containers strictly isolated. Generating multi-site schema hooks..."

# 3. Create sandbox database
echo "🗄️ Creating 'openemr_sandbox' database schema internally..."
docker exec asgard_mariadb mysql -u root -proot -e \
"CREATE DATABASE IF NOT EXISTS openemr_sandbox CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
GRANT ALL PRIVILEGES ON openemr_sandbox.* TO 'openemr'@'%'; \
FLUSH PRIVILEGES;"

# 4. Clone OpenEMR default site context mapping
echo "📂 Provisioning Eir site directories..."
docker exec asgard_eir sh -c '
  # Ensure the target sandbox directory is clear 
  rm -rf /var/www/localhost/htdocs/openemr/sites/sandbox

  # Standard multisite duplication protocol
  cp -R /var/www/localhost/htdocs/openemr/sites/default /var/www/localhost/htdocs/openemr/sites/sandbox

  # Fix the primary database target variable 
  sed -i "s/\$dbase = \x27openemr\x27;/\$dbase = \x27openemr_sandbox\x27;/g" /var/www/localhost/htdocs/openemr/sites/sandbox/sqlconf.php

  # Recursively configure apache group ownership for caching/documents
  chown -R apache:apache /var/www/localhost/htdocs/openemr/sites/sandbox
'

echo "🎉 Eir Sandbox provisioning sequence complete!"
echo "➡️  Sandbox API Route: https://localhost/apis/sandbox/"
echo "➡️  Dashboard Portal:  https://localhost/interface/login/login.php?site=sandbox"
echo "Note: The sandbox datastore is currently empty. Run the Eir setup protocol via the dashboard to populate the schema."
