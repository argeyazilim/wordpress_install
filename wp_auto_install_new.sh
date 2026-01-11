#!/bin/bash

set -e

### AYARLAR ###
DOMAIN="ahmetertugrul.com"
WP_DIR="/var/www/wordpress"

# GÜNCELLEME: İndirme linki ve geçici kayıt yeri
WP_URL="https://tr.wordpress.org/latest-tr_TR.zip"
WP_ZIP="/tmp/latest-tr_TR.zip"

DB_NAME="wordpress"
DB_USER="wpuser"
DB_PASS="StrongPassword123!"
DB_HOST="localhost"

PHP_VERSION="8.3"
PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

echo "=== Sistem güncelleniyor ==="
apt update -y && apt upgrade -y

echo "=== Gerekli paketler kuruluyor ==="
# Curl paketini indirme işlemi için kullanacağız, listede olduğundan emin oluyoruz.
apt install -y nginx mysql-server unzip curl software-properties-common

echo "=== PHP ${PHP_VERSION} kuruluyor ==="
apt install -y \
php${PHP_VERSION}-fpm \
php${PHP_VERSION}-mysql \
php${PHP_VERSION}-curl \
php${PHP_VERSION}-gd \
php${PHP_VERSION}-mbstring \
php${PHP_VERSION}-xml \
php${PHP_VERSION}-zip \
php${PHP_VERSION}-intl

echo "=== Servisler başlatılıyor ==="
systemctl enable nginx mysql php${PHP_VERSION}-fpm
systemctl start nginx mysql php${PHP_VERSION}-fpm

echo "=== WordPress İndiriliyor ve Kuruluyor ==="
# Önceki kalıntıları temizle
rm -f $WP_ZIP

# WordPress'i indir (-L parametresini yönlendirmeleri takip etmesi için ekledik)
echo "Dosya indiriliyor: $WP_URL..."
curl -L -o $WP_ZIP $WP_URL

mkdir -p $WP_DIR
# Zip'i /tmp dizinine açıyoruz
unzip -o $WP_ZIP -d /tmp

# Dosyaları hedef dizine taşıyoruz
# İndirilen zip genellikle "wordpress" klasörüyle çıkar, içeriğini alıyoruz
cp -r /tmp/wordpress/* $WP_DIR

# Geçici dosyaları temizle
rm -rf /tmp/wordpress $WP_ZIP

echo "=== Yetkiler ayarlanıyor ==="
chown -R www-data:www-data $WP_DIR
chmod -R 755 $WP_DIR

echo "=== MySQL veritabanı oluşturuluyor ==="
mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
EOF

echo "=== wp-config.php oluşturuluyor ==="
cp $WP_DIR/wp-config-sample.php $WP_DIR/wp-config.php

sed -i "s/database_name_here/${DB_NAME}/" $WP_DIR/wp-config.php
sed -i "s/username_here/${DB_USER}/" $WP_DIR/wp-config.php
sed -i "s/password_here/${DB_PASS}/" $WP_DIR/wp-config.php

# Salt anahtarlarını ekleme (Not: Bu yöntem dosyanın en sonuna ekler, wp-config yapısına dikkat edin)
curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> $WP_DIR/wp-config.php

chown www-data:www-data $WP_DIR/wp-config.php

echo "=== Nginx site konfigürasyonu oluşturuluyor ==="
cat > /etc/nginx/sites-available/wordpress <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root ${WP_DIR};
    index index.php index.html;

    access_log /var/log/nginx/wordpress_access.log;
    error_log /var/log/nginx/wordpress_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCK};
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires max;
        log_not_found off;
    }
}
EOF

ln -sf /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo "=== Nginx test & reload ==="
nginx -t
systemctl reload nginx

echo "=== PHP ayarları optimize ediliyor ==="
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"

sed -i "s/memory_limit = .*/memory_limit = 256M/" $PHP_INI
sed -i "s/upload_max_filesize = .*/upload_max_filesize = 64M/" $PHP_INI
sed -i "s/post_max_size = .*/post_max_size = 64M/" $PHP_INI
sed -i "s/max_execution_time = .*/max_execution_time = 300/" $PHP_INI

systemctl restart php${PHP_VERSION}-fpm

echo "=== Kurulum tamamlandı ==="
echo "Site: http://${DOMAIN}"
echo "DB Name: ${DB_NAME}"
echo "DB User: ${DB_USER}"
echo "DB Pass: ${DB_PASS}"
