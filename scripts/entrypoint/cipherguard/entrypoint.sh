
function gpg_gen_key() {
  key_email="${CIPHERGUARD_KEY_EMAIL:-cipherguard@yourdomain.com}"
  key_name="${CIPHERGUARD_KEY_NAME:-Cipherguard default user}"
  key_length="${CIPHERGUARD_KEY_LENGTH:-3072}"
  subkey_length="${CIPHERGUARD_SUBKEY_LENGTH:-3072}"
  expiration="${CIPHERGUARD_KEY_EXPIRATION:-0}"

  entropy_check

  su -c "gpg --homedir $GNUPGHOME --batch --no-tty --gen-key <<EOF
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

  su -c "gpg --homedir $GNUPGHOME --armor --export-secret-keys $key_email > $gpg_private_key" -ls /bin/bash www-data
  su -c "gpg --homedir $GNUPGHOME --armor --export $key_email > $gpg_public_key" -ls /bin/bash www-data
}

function gpg_import_key() {
  su -c "gpg --homedir $GNUPGHOME --batch --import $gpg_public_key" -ls /bin/bash www-data
  su -c "gpg --homedir $GNUPGHOME --batch --import $gpg_private_key" -ls /bin/bash www-data
}

function gen_ssl_cert() {
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj '/C=FR/ST=Denial/L=Springfield/O=Dis/CN=www.cipherguard.local' \
    -addext "subjectAltName = DNS:www.cipherguard.local" \
    -keyout "$ssl_key" -out "$ssl_cert"
}

function get_subscription_file() {
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

function import_subscription() {
  if get_subscription_file; then
    echo "Subscription file found: $SUBSCRIPTION_FILE"
    su -c "/usr/share/php/cipherguard/bin/cake cipherguard subscription_import --file $SUBSCRIPTION_FILE" -s /bin/bash www-data
  fi
}

function install_command() {
  echo "Installing cipherguard"
  su -c '/usr/share/php/cipherguard/bin/cake cipherguard install --no-admin' -s /bin/bash www-data 
}

function clear_cake_cache_engines() {
  echo "Clearing cake caches"
  for engine in "${@}";
  do
    su -c "/usr/share/php/cipherguard/bin/cake cache clear _cake_${engine}_" -s /bin/bash www-data 
  done
}

function migrate_command() {
  echo "Running migrations"
  su -c '/usr/share/php/cipherguard/bin/cake cipherguard migrate --no-clear-cache' -s /bin/bash www-data 
  clear_cake_cache_engines model core
}

function jwt_keys_creation() {
  if [[ $CIPHERGUARD_PLUGINS_JWT_AUTHENTICATION_ENABLED == "true" && ( ! -f $cipherguard_config/jwt/jwt.key || ! -f $cipherguard_config/jwt/jwt.pem ) ]]
  then 
    su -c '/usr/share/php/cipherguard/bin/cake cipherguard create_jwt_keys' -s /bin/bash www-data
    chmod 640 "$cipherguard_config/jwt/jwt.key" && chown root:www-data "$cipherguard_config/jwt/jwt.key" 
    chmod 640 "$cipherguard_config/jwt/jwt.pem" && chown root:www-data "$cipherguard_config/jwt/jwt.pem" 
  fi 
}

function install() {
  if [ ! -f "$cipherguard_config/app.php" ]; then
    su -c "cp $cipherguard_config/app.default.php $cipherguard_config/app.php" -s /bin/bash www-data
  fi

  if [[ ( "${CIPHERGUARD_GPG_SERVER_KEY_FINGERPRINT_FORCE}" == "true" ) || \
      ( -z "${CIPHERGUARD_GPG_SERVER_KEY_FINGERPRINT+xxx}" && \
      ! -f  "$cipherguard_config/cipherguard.php" ) ]]; then
    gpg_auto_fingerprint="$(su -c "gpg --homedir $GNUPGHOME --list-keys --with-colons ${CIPHERGUARD_KEY_EMAIL:-cipherguard@yourdomain.com} |grep fpr |head -1| cut -f10 -d:" -ls /bin/bash www-data)"
    export CIPHERGUARD_GPG_SERVER_KEY_FINGERPRINT=$gpg_auto_fingerprint
  fi

  import_subscription || true

  jwt_keys_creation
  install_command || migrate_command && echo "Enjoy! ☮"
}

