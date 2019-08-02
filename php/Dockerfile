FROM fedora:22

# NOTE: This is not a production build: for sandbox/CI use only

# Pass the version of PHP to use as a build arg - must have corresponding config file
ARG version=7.2

# Items excluded from config comparison (known deltas due to IDs, extension defaults etc)
ENV CONFIG_EXCLUDE ^apm\.|^extension_dir|^sendmail_path|auto_prepend_file|^ic24.sec.initial_cache_all

# PECL packages - we need to list these explicitly as we can't identify these automatically
ENV PECL_PACKAGES apcu|apm|imagick|oauth|pdo_sqlsrv|redis|sqlsrv

# Build dependencies - removed after build is complete
ENV BUILDDEPS aspell-devel \
        ImageMagick-devel \
        bzip2-devel \
        curl-devel \
        db4-devel \
        freetds-devel \
        freetype-devel \
        gmp-devel \
        icu \
        krb5-devel \
        libXpm-devel \
        libc-client-devel \
        libcurl-devel \
        libicu-devel \
        libjpeg-devel \
        libmcrypt-devel \
        libpng-devel \
        libtidy-devel \
        libxml2-devel \
        libxslt-devel \
        mhash-devel \
        mysql-devel \
        ncurses-devel \
        net-snmp-devel \
        openldap-devel \
        openssl-devel \
        pcre-devel \
        postgresql-devel \
        readline-devel \
        recode-devel \
        sqlite-devel \
        systemd-devel \
        t1lib-devel \
        unixODBC-devel \
        zlib-devel

# We use bash process substitution to simplify the validation diff commands
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set the path to include the build PHP bin directory
ENV PATH=$PATH:/opt/php/bin

# Copy in the config file specified by the "version" build arg
COPY "${version}"-config /usr/src/config

# Install prerequisites, build PHP & extensions, validate the build then clean up
# Ignore some linting rules that interfere with build/validation (cd, php vars etc)
# hadolint ignore=SC1091,SC2016,SC2046,SC2086,DL3003,DL3008
RUN . /usr/src/config && \
        touch /var/lib/rpm/* \
        && dnf -y upgrade --setopt=deltarpm=false \
        && dnf -y group install "C Development Tools and Libraries" \
        && dnf -y install \
        ${BUILDDEPS} \
        # Permanently installed dependencies
        file \
        wget \
        xz && \
        # Reqs for sqlsrv extension
        curl --silent --location --output /etc/yum.repos.d/mssql-release.repo https://packages.microsoft.com/config/rhel/7/prod.repo && \
        ACCEPT_EULA=Y dnf install -y msodbcsql && \
        \
        # Download and build php
        cd /usr/src && \
        curl --silent --location --output php.tar.xz "http://us1.php.net/get/php-${EXACT_VERSION}.tar.xz/from/this/mirror" && \
        tar xf php.tar.xz && \
        cd /usr/src/php-* && \
        # Build CLI and FPM (single build step, CLI and FPM use identical configure options)
        # Variable not quoted as it contains arguments that are separate words
        ./configure ${CLI_CONFIGURE_OPTIONS} && \
        make -j "$(nproc)" && \
        make install && \
        \
        # Copy the etc configuration into place - CLI and FPM use identical configs
        echo "${CLI_INI}" > "/opt/php/etc/php.ini" && \
        # Workaround for APM PHP extension
        ln -s /usr/lib64/mysql/libmysqlclient* /usr/lib/ && \
        # Install PHP extensions - we use the versions from EXTENSIONS_VERSIONS since Pantheon doesn't list the pecl packages
        pear config-set php_ini /opt/php/etc/php.ini && \
        # Variable not quoted as it contains arguments that are separate words
        yes '' | pecl install --force $(echo "${EXTENSIONS_VERSIONS}" | grep -Eio "(${PECL_PACKAGES})-[0-9]\\.[0-9]\\.[0-9]") && \
        # Move the extensions from the extension API version directory to the /opt/php/lib directory to simplify configuration (PECL ext_dir does not work)
        mv /opt/php/lib/[0-9]*/* /opt/php/lib && \
        # Install ionCube if present
        if [[ ${EXTENSIONS} == *"ionCube Loader"* ]]; then \
        mkdir -p /opt/pantheon/ioncube/10.0.3/ && \
        curl --silent --location http://downloads3.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz | tar xvz --directory /opt/pantheon/ioncube/10.0.3/ --strip-components=1; \
        fi && \
        # Ensure each extension is only listed once in php.ini
        EXT=$(grep '^extension=' /opt/php/etc/php.ini | tr -d '"' | sort -u); \
        sed -i'' /opt/php/etc/php.ini -e 's/^extension=.*//g' && \
        echo "${EXT}" >> /opt/php/etc/php.ini && \
        \
        # Clean up
        rm -rf /usr/src/* && \
        dnf -y group remove "C Development Tools and Libraries" && \
        dnf clean all && \
        \
        # Validate that distro, loaded extensions and config match
        if ! diff -uw /etc/redhat-release <(echo "${DISTRO}"); then echo "Distro does not match expected"; exit 1; fi && \
        if ! diff -uw <(php -r '$e = get_loaded_extensions() && sort($e) && print(implode(PHP_EOL, $e));') <(echo "${EXTENSIONS}"); then echo "PHP extensions do not match expected"; exit 2; fi && \
        if ! diff -uw \
        <(php -r 'foreach (ini_get_all() as $k => $v) { print "$k: $v['global_value']\n"; }' | grep -Ev "($CONFIG_EXCLUDE)") \
        <(echo "${CONFIG}" | grep -Ev "($CONFIG_EXCLUDE)"); \
        then echo "PHP config does not match expected"; exit 3; fi

WORKDIR /opt/php/etc
# Configure php-fpm for Docker: the below is sourced from https://github.com/docker-library/php/blob/master/7.1/stretch/fpm/Dockerfile#L198
RUN if [ -d php-fpm.d ]; then \
        # for some reason, upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
        sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
        cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
        else \
        # PHP 5.x doesn't use "include=" by default, so we'll create our own simple config that mimics PHP 7+ for consistency
        mkdir php-fpm.d; \
        cp php-fpm.conf.default php-fpm.d/www.conf; \
        { \
        echo '[global]'; \
        echo 'include=etc/php-fpm.d/*.conf'; \
        } | tee php-fpm.conf; \
        fi \
        && { \
        echo '[global]'; \
        echo 'error_log = /proc/self/fd/2'; \
        echo; \
        echo '[www]'; \
        echo '; if we send this to /proc/self/fd/1, it never appears'; \
        echo 'access.log = /proc/self/fd/2'; \
        echo; \
        echo 'clear_env = no'; \
        echo; \
        echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
        echo 'catch_workers_output = yes'; \
        } | tee php-fpm.d/docker.conf \
        && { \
        echo '[global]'; \
        echo 'daemonize = no'; \
        echo; \
        echo '[www]'; \
        echo 'listen = 9000'; \
        } | tee php-fpm.d/zz-docker.conf

CMD ["/opt/php/sbin/php-fpm"]