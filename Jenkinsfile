pipeline {
    agent any
    triggers {
        // Update/build master at 9pm PT.
        cron(env.BRANCH_NAME == 'master' ? '0 23 * * *' : '')
    }
    environment { 
        TAG = "${env.BRANCH_NAME}"
        TOKEN = credentials('pantheon-machine-token') 
        ID_RSA = credentials('pantheon-ssh-key')
    }
    stages {
        stage('Code linting') {
            steps {
                script {
                    // Check bash script formatting
                    sh 'find * -name *.sh -print0 | xargs -n1 -I "{}" -0 docker run -i -v "$(pwd)":/workdir -w /workdir unibeautify/beautysh -c "/workdir/{}"'
                    // Lint bash scripts using shellcheck
                    sh 'find * -name *.sh -print0 | xargs -n1 -I "{}" -0 docker run -i --rm -v "$PWD":/src  koalaman/shellcheck "/src/{}"'
                    // Lint Dockerfiles using hadolint
                    sh 'find * -name Dockerfile* -print0 | xargs -n1 -I "{}" -0 docker run -i --rm -v "$PWD":/src hadolint/hadolint hadolint "/src/{}"'
                }
            }
        }
        stage('Update configs') {
          steps {
            script {
              sh 'docker build -t getconfig getconfig'
              sh 'chmod o+w -R php nginx mysql'
              sh 'docker run -i -v $(pwd)/php:/build-tools-ci/php -v $(pwd)/mysql:/build-tools-ci/mysql -v $(pwd)/nginx:/build-tools-ci/nginx -e TOKEN -e ID_RSA getconfig:latest dockertest'
              sh 'chmod o-w -R php nginx mysql'
            }
          }
        }
        stage('Build') {
            parallel {
                stage('PHP 7.1') {
                    steps {
                        script {
                            withEnv(['VERSION=7.1']) {
                                sh 'docker build -t "drydockcloud/drupal-pantheon-php-${VERSION}:${TAG}" ./php --build-arg version="${VERSION}"'
                            }
                        }
                    }
                }
                stage('PHP 7.2') {
                    steps {
                        script {
                            withEnv(['VERSION=7.2']) {
                                sh 'docker build -t "drydockcloud/drupal-pantheon-php-${VERSION}:${TAG}" ./php --build-arg version="${VERSION}"'
                            }
                        }
                    }
                }
                stage('NGINX') {
                    steps {
                        script {
                            sh 'docker build -t "drydockcloud/drupal-pantheon-nginx:${TAG}" ./nginx'
                        }
                    }
                }
                stage('MySQL') {
                    steps {
                        script {
                            sh 'docker build -t "drydockcloud/drupal-pantheon-mysql:${TAG}" ./mysql'
                        }
                    }
                }
            }
        }
        stage('Test') {
            parallel {
                stage('Test PHP 7.1') {
                    steps {
                        script {
                            withEnv(['VERSION=7.1']) {
                                sh 'test/test.sh'
                            }
                        }
                    }
                }
                stage('Test PHP 7.2') {
                    steps {
                        script {
                            withEnv(['VERSION=7.2']) {
                                sh 'test/test.sh'
                            }
                        }
                    }
                }
            }
        }
        stage('Commit and push to master') {
          when { branch 'master' }
          steps {
            script {
              sh 'git commit -a -m"Automatic update for $(date --iso-8601=date)"'
              sh 'git push origin master'
              // Cut a tag for the day (if it does not already exist - otherwise just let it roll into tomorrows tag).
              sh 'git tag "$(date \"+v%Y.%m.%d-0\")" || true'
              sh 'git push origin --tags'
            }
          }
        }
    }
}
