FROM quay.io/pantheon-public/build-tools-ci:6.x

USER root
# Disable host key checks so we can run in CI
RUN echo StrictHostKeyChecking no >> /etc/ssh/ssh_config && \
  # Allow --user="$(id -u)"
  chmod -R o+rwx /build-tools-ci /home/tester
USER tester

COPY getconfig.sh scripts/
RUN curl -Lso scripts/getconfig.php https://raw.githubusercontent.com/drydockcloud/tools-php-getconfig/master/getconfig.php

ENTRYPOINT [ "scripts/getconfig.sh" ]