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
        // Set Git user for commits.
        GIT_COMMITTER_NAME = "Drydock CI"
        GIT_COMMITTER_EMAIL = "ci@drydock.cloud"
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
        // If we are building master, check out the real branch now so we can commit changes later
        // Potentially could switch this to a git {} task
        stage('Checkout master') {
          when { branch 'master' }
          steps {
            script {
             sh 'git fetch origin master'
             sh 'git checkout master'
             sh 'git reset --hard origin/master'
            }
          }
        }
        stage('Update configs') {
          steps {
            script {
              sh 'docker build -t getconfig getconfig'
              sh 'docker run --user=$(id -u) -i -v $(pwd)/php:/build-tools-ci/php -v $(pwd)/mysql:/build-tools-ci/mysql -v $(pwd)/nginx:/build-tools-ci/nginx -e TOKEN -e ID_RSA getconfig:latest dockertest'
              // If we are on master and there are no changes, then pass the build early.
              def result = sh 'if [[ "$(git symbolic-ref HEAD 2>/dev/null)" == "refs/heads/master" ]]; then git diff --exit-code; fi'
              if (result != 0) {
                echo 'No changes on master build, ending early.'
                currentBuild.result = 'SUCCESS'
                return
              }
            }
          }
        }
        stage('Build') {
            parallel {
                stage('PHP 7.1') {
                    steps {
                        script {
                            withEnv(['VERSION=7.1']) {
                                // Retry the build if it fails. DNF can fail on fetching mirrors as the mirror server 503s when the list is rotated.
                                // See: https://bugzilla.redhat.com/show_bug.cgi?id=1593033
                                retry(3) {
                                    sh 'docker build -t "drydockcloud/drupal-pantheon-php-${VERSION}:${TAG}" ./php --build-arg version="${VERSION}"'
                                }
                            }
                        }
                    }
                }
                stage('PHP 7.2') {
                    steps {
                        script {
                            withEnv(['VERSION=7.2']) {
                                retry(3) {
                                    sh 'docker build -t "drydockcloud/drupal-pantheon-php-${VERSION}:${TAG}" ./php --build-arg version="${VERSION}"'
                                }
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
        stage('Commit and push to master') {
          when { branch 'master' }
          steps {
            script {
              sh 'git remote set-url origin git@github.com:drydockcloud/drupal-pantheon.git'
              sh 'git add php nginx mysql'
              try {
                // If there are changes added, this will exit non-zero so we can commit them.
                sh 'git diff --cached --exit-code'
              }
              catch (exc) {
                sh 'git commit -m"Automatic update for $(date --iso-8601=date)"'
                // Cut a tag for the day (if it does not already exist - otherwise just let it roll into tomorrows tag).
                sh 'git tag "$(date \"+v%Y.%m.%d-0\")" || true'
                sh 'rm ssh.sock || true; eval $(ssh-agent -a ssh.sock -s) && echo "$ID_RSA" | base64 -d | ssh-add - && git push origin master && git push origin --tags; ssh-add -D'
              }
            }
          }
        }
    }
}
