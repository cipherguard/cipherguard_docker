#!/usr/bin/env bash

set -eo pipefail

cipherguard_config="/etc/cipherguard"
gpg_private_key="${CIPHERGUARD_GPG_SERVER_KEY_PRIVATE:-$cipherguard_config/gpg/serverkey_private.asc}"
gpg_public_key="${CIPHERGUARD_GPG_SERVER_KEY_PUBLIC:-$cipherguard_config/gpg/serverkey.asc}"

ssl_key='/etc/ssl/certs/certificate.key'
ssl_cert='/etc/ssl/certs/certificate.crt'

deprecation_message=""

subscription_key_file_paths=("/etc/cipherguard/subscription_key.txt" "/etc/cipherguard/license")

source $(dirname $0)/../cipherguard/entrypoint.sh
source $(dirname $0)/../cipherguard/entropy.sh
source $(dirname $0)/../cipherguard/env.sh
source $(dirname $0)/../cipherguard/deprecated_paths.sh

manage_docker_env

check_deprecated_paths

if [ ! -f "$gpg_private_key" ] || \
   [ ! -f "$gpg_public_key" ]; then
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

echo -e "$deprecation_message"

declare -p | grep -Ev 'BASHOPTS|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID' > /etc/environment

exec /usr/bin/supervisord -n
