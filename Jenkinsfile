pipeline {
    agent { label 'docker' }
    options {
        skipDefaultCheckout()
        disableConcurrentBuilds()
        timestamps()
    }
    triggers { pollSCM('H/5 * * * *') }

    stages {
        stage('Clean checkout') {
            steps {
                deleteDir()
                checkout scm
            }
        }
        stage('BUILD') {
            steps {
                sh '''
                    set -eu
                    docker build --target test -t aceest-a1:test .
                    docker run --rm aceest-a1:test sh -ec '
                        PYTHONPYCACHEPREFIX=/tmp/pycache python -m compileall -q app.py ACEest_Fitness.py tests
                        ruff check app.py ACEest_Fitness.py tests
                    '
                    docker build --target runtime -t aceest-a1:build .
                    mkdir -p reports
                    docker image inspect --format '{{.Id}}' aceest-a1:build > reports/image.txt
                '''
            }
        }
        stage('Quality gate') {
            steps {
                sh 'bash ci/test-image.sh aceest-a1:test'
            }
        }
    }
    post {
        always {
            junit testResults: 'reports/junit.xml', allowEmptyResults: true
            archiveArtifacts artifacts: 'reports/*.xml,reports/image.txt', allowEmptyArchive: true
        }
    }
}
