#!/usr/bin/env bash

set -euo pipefail

gpg_private_key="${CIPHERGUARD_GPG_SERVER_KEY_PRIVATE:-/var/www/cipherguard/config/gpg/serverkey_private.asc}"
gpg_public_key="${CIPHERGUARD_GPG_SERVER_KEY_PUBLIC:-/var/www/cipherguard/config/gpg/serverkey.asc}"

ssl_key='/etc/ssl/certs/certificate.key'
ssl_cert='/etc/ssl/certs/certificate.crt'

subscription_key_file_paths=("/etc/cipherguard/subscription_key.txt" "/etc/cipherguard/license")

export GNUPGHOME="/home/www-data/.gnupg"

entropy_check() {
  local entropy_avail

  entropy_avail=$(cat /proc/sys/kernel/random/entropy_avail)

  if [ "$entropy_avail" -lt 2000 ]; then

    cat <<EOF
==================================================================================
  Your entropy pool is low. This situation could lead GnuPG to not
  be able to create the gpg serverkey so the container start process will hang
  until enough entropy is obtained.
  Please consider installing rng-tools and/or virtio-rng on your host as the
  preferred method to generate random numbers using a TRNG.
  If rngd (rng-tools) does not provide enough or fast enough randomness you could
  consider installing haveged as a helper to speed up this process.
  Using haveged as a replacement for rngd is not recommended. You can read more
  about this topic here: https://lwn.net/Articles/525459/
==================================================================================
EOF
  fi
}

gpg_gen_key() {
  key_email="${CIPHERGUARD_KEY_EMAIL:-cipherguard@yourdomain.com}"
  key_name="${CIPHERGUARD_KEY_NAME:-Cipherguard default user}"
  key_length="${CIPHERGUARD_KEY_LENGTH:-3072}"
  subkey_length="${CIPHERGUARD_SUBKEY_LENGTH:-3072}"
  expiration="${CIPHERGUARD_KEY_EXPIRATION:-0}"

  entropy_check

  su -c "gpg --batch --no-tty --gen-key <<EOF
    Key-Type: default
		Key-Length: $key_length
		Subkey-Type: default
		Subkey-Length: $subkey_length
    Name-Real: $key_name
    Name-Email: $key_email
    Expire-Date: $expiration
    %no-protection
		%commit
EOF" -ls /bin/bash www-data

  su -c "gpg --armor --export-secret-keys $key_email > $gpg_private_key" -ls /bin/bash www-data
  su -c "gpg --armor --export $key_email > $gpg_public_key" -ls /bin/bash www-data
}

gpg_import_key() {
  su -c "gpg --batch --import $gpg_public_key" -ls /bin/bash www-data
  su -c "gpg --batch --import $gpg_private_key" -ls /bin/bash www-data
}

gen_ssl_cert() {
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj '/C=FR/ST=Denial/L=Springfield/O=Dis/CN=www.cipherguard.local' \
    -keyout $ssl_key -out $ssl_cert
}

get_subscription_file() {
  if [ "${CIPHERGUARD_FLAVOUR}" == 'ce' ]; then
    return 1
  fi
  
  # Look for subscription key on possible paths
  for path in "${subscription_key_file_paths[@]}";
  do
    if [ -f "${path}" ]; then
      SUBSCRIPTION_FILE="${path}"
      return 0
    fi
  done

  return 1
}

check_subscription() {
  if get_subscription_file; then
    echo "Subscription file found: $SUBSCRIPTION_FILE"
    su -c "/usr/share/php/cipherguard/bin/cake cipherguard subscription_import --file $SUBSCRIPTION_FILE" -s /bin/bash www-data
  fi
}

install_command() {
  echo "Installing cipherguard"
  su -c './bin/cake cipherguard install --no-admin' -s /bin/bash www-data 
}

migrate_command() {
  echo "Running migrations"
  su -c './bin/cake cipherguard migrate' -s /bin/bash www-data 
}

install() {
  local app_config="/var/www/cipherguard/config/app.php"

  if [ ! -f "$app_config" ]; then
    su -c 'cp /var/www/cipherguard/config/app.default.php /var/www/cipherguard/config/app.php' -s /bin/bash www-data
  fi

  if [ -z "${CIPHERGUARD_GPG_SERVER_KEY_FINGERPRINT+xxx}" ] && [ ! -f  '/var/www/cipherguard/config/cipherguard.php' ]; then
    gpg_auto_fingerprint="$(su -c "gpg --list-keys --with-colons ${CIPHERGUARD_KEY_EMAIL:-cipherguard@yourdomain.com} |grep fpr |head -1| cut -f10 -d:" -ls /bin/bash www-data)"
    export CIPHERGUARD_GPG_SERVER_KEY_FINGERPRINT=$gpg_auto_fingerprint
  fi

  check_subscription || true
  
  install_command || migrate_command
}

if [ ! -f "$gpg_private_key" ] && [ ! -L "$gpg_private_key" ] || \
   [ ! -f "$gpg_public_key" ] && [ ! -L "$gpg_public_key" ]; then
  gpg_gen_key
  gpg_import_key
else
  gpg_import_key
fi

if [ ! -f "$ssl_key" ] && [ ! -L "$ssl_key" ] && \
   [ ! -f "$ssl_cert" ] && [ ! -L "$ssl_cert" ]; then
  gen_ssl_cert
fi

install

exec /usr/bin/supervisord -n
