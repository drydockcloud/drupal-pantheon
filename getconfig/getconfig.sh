#!/usr/bin/env bash
set -euo pipefail
SUPPORTED_PHP=( 7.1 7.2 )
SITE=${1:-}
if [ -z "$SITE" ]; then
    echo "First argument must be Pantheon site to get configuration for."
    echo "Must have a multidev instance for each supported PHP version (${SUPPORTED_PHP[*]})"
    echo "- PHP versions in each multidev must be configured with pantheon.yml."
    echo "- Multidevs should be named 'PHPx-y' where x and y are the PHP major and minor version."
    echo "- Each multidev must be in sftp mode (not git mode)."
    exit 1
fi
if [ -z "${TOKEN:-}" ]; then
    echo "Environment variable TOKEN must be set to Pantheon machine token."
    echo "See https://pantheon.io/docs/machine-tokens/"
    exit 1
fi
if [ -z "${ID_RSA:-}" ]; then
    echo "Environment variable ID_RSA must be set to base64 encoded SSH private key (cat id_rsa | base64 -w0) that has been added to Pantheon account."
    exit 1
fi
if [[ ! -f php/Dockerfile || ! -f mysql/Dockerfile || ! -f nginx/Dockerfile ]]; then
    echo "This script expects to be run in a directory with php, mysql and nginx subdirectories"
    echo "containing the Dockerfiles where the configuration will be updated."
    exit 1
fi

echo "Logging in with Terminus"
terminus --no-interaction auth:login --machine-token="${TOKEN}"

# Safety in case this is run outside a container
if [[ ! -f ${HOME}/.ssh/id_rsa ]]; then
    echo "Storing SSH key"
    mkdir "${HOME}/.ssh"
    ID_RSA_PATH=${HOME}/.ssh/id_rsa
    echo "${ID_RSA}" > "${ID_RSA_PATH}"
    chmod 700 "${HOME}/.ssh"
    chmod 600 "${ID_RSA_PATH}"
    ssh-keygen -l -f "${ID_RSA_PATH}"
fi

echo "Updating PHP configuration"
for PHP in "${SUPPORTED_PHP[@]}"; do
    MULTIDEV=php${PHP//[.]/-}
    echo "Getting config for $SITE -> $MULTIDEV"
    UUID=$(terminus site:lookup "${SITE}")
    HOST=${MULTIDEV}.${UUID}@appserver.${MULTIDEV}.${UUID}.drush.in
    sftp -i "${ID_RSA_PATH}" -o Port=2222 "${HOST}":code/ <<< $'rm getconfig.php'
    (
        cd "$( dirname "${BASH_SOURCE[0]}" )"
        sftp -i "${ID_RSA_PATH}" -o Port=2222 "${HOST}":code/ <<< $'put getconfig.php'
    )
    terminus remote:drush "${SITE}.${MULTIDEV}" php-script getconfig.php -- pantheon > php/"${PHP}"-config
    sftp -i "${ID_RSA_PATH}" -o Port=2222 "${HOST}":code/ <<< $'rm getconfig.php'
done

echo "Updating MariaDB version"
# Connect to the database and output the version string
RAWVERSION=$(terminus remote:drush "${SITE}.${MULTIDEV}" sqlq 'SHOW VARIABLES LIKE "version"')
# Extract the primary version number from the version string
MYSQLVERSION=$(echo "$RAWVERSION" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
# Update the version number in the Dockerfile with the extracted number
sed -i'' -e "s/FROM mariadb:[0-9.]*$/FROM mariadb:$MYSQLVERSION/" mysql/Dockerfile

echo "Updating Nginx version and config"
# Get Nginx version number
NGINXVERSION=$( (terminus remote:drush "${SITE}.${MULTIDEV}" ev "shell_exec('/usr/sbin/nginx -v')" 2>&1 || true) | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
echo "Ngnix version is $NGINXVERSION"
# Update the version number in the Dockerfile with the extracted number
sed -i'' -e "s/FROM nginx:[0-9.]*$/FROM nginx:$NGINXVERSION/" nginx/Dockerfile
(
    # Fetch a sample nginx.conf
    cd nginx
    sftp -i "${ID_RSA_PATH}" -o Port=2222 "${HOST}":code/ <<< $'get ../nginx.conf'
    # Remove initial proxy_pass (which seems to go to some internal service, perhaps a WAF?
    perl -i -p0e 's@location /.*?proxy_intercept_errors.*?}@@s' nginx.conf
    # Update the config to work in Docker and remove access keys etc
    sed -i'' \
        -e 's@listen \[::\]@#listen [::]@g' \
        -e 's@listen [0-9]* ssl;@listen 80;@g' \
        -e 's@/srv/bindings/[^/]*/code/@/var/www/docroot/@g' \
        -e 's@/srv/bindings/[^/]*/logs/nginx-\(access\|error\).log@/var/log/nginx/\1.log@g' \
        -e 's@/srv/bindings/[^/]*/mime.types@/etc/nginx/mime.types@g' \
        -e 's@/srv/bindings/[^/]*/@/var/@g' \
        -e 's@.*X-Pantheon-.*@@g' \
        -e "s@_access_key != '[^']*'@_access_key != 'docker'@g" \
        -e 's@/srv/includes/fastcgi_params@/etc/nginx/fastcgi_params@g' \
        -e 's@^[ ]*ssl_@# ssl_@g' \
        -e 's@fastcgi_pass [^;]*;@fastcgi_pass php:9000;@g' \
        -e 's|location @backtophp|location /|g' \
        nginx.conf
)

echo "All done!"
