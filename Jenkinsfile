pipeline {
    agent { label 'docker' }
    options {
        skipDefaultCheckout()
        disableConcurrentBuilds()
        timestamps()
    }
    triggers { pollSCM('H/5 * * * *') }

    parameters {
        choice(name: 'RELEASE_TARGET', choices: ['docker-hub', 'minikube'],
               description: 'Publish and deploy from Docker Hub, or load images into local Minikube.')
        string(name: 'DOCKERHUB_REPO', defaultValue: '',
               description: 'Public Docker Hub repository in namespace/repository form.')
        string(name: 'ACEEST_CONTEXT', defaultValue: 'aceest-coursework',
               description: 'Name of the only context in the dedicated ACEest kubeconfig.')
    }

    stages {
        stage('Clean checkout') {
            steps {
                deleteDir()
                checkout scm
                script {
                    env.APP_VERSION = readFile('VERSION').trim()
                    def revision = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                    env.CANDIDATE_TAG = "${env.APP_VERSION}-${revision}"
                    env.TEST_IMAGE = "aceest-a2-test:${env.CANDIDATE_TAG}"
                }
            }
        }
        stage('Build test environment and validate') {
            steps {
                sh '''
                    set -eu
                    docker build --target test -t "$TEST_IMAGE" .
                    docker run --rm "$TEST_IMAGE" sh -ec '
                        PYTHONPYCACHEPREFIX=/tmp/pycache python -m compileall -q app.py ACEest_Fitness.py tests
                        ruff check app.py ACEest_Fitness.py tests
                    '
                    bash ci/test-image.sh "$TEST_IMAGE"
                '''
            }
        }
        stage('SonarQube quality gate') {
            steps {
                withCredentials([string(credentialsId: 'aceest-sonarqube-token', variable: 'SONAR_TOKEN')]) {
                    sh '''
                        set -eu
                        : "${SONAR_HOST_URL:?Configure SONAR_HOST_URL on the Jenkins agent}"
                        status=0
                        sonar-scanner "-Dsonar.projectVersion=$APP_VERSION" \
                          -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=180 || status=$?
                        if [ -f .scannerwork/report-task.txt ]; then
                            python3 ci/sonar-report.py || status=1
                        fi
                        exit "$status"
                    '''
                }
            }
        }
        stage('Build and distribute release images') {
            steps {
                withCredentials([file(credentialsId: 'aceest-kubeconfig', variable: 'ACEEST_KUBECONFIG')]) {
                    script {
                        if (params.RELEASE_TARGET == 'docker-hub') {
                            withCredentials([usernamePassword(credentialsId: 'aceest-dockerhub',
                                usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_TOKEN')]) {
                                sh 'bash ci/release-images.sh'
                            }
                        } else {
                            sh 'bash ci/release-images.sh'
                        }
                    }
                }
            }
        }
        stage('Deploy and verify') {
            steps {
                withCredentials([file(credentialsId: 'aceest-kubeconfig', variable: 'ACEEST_KUBECONFIG')]) {
                    sh '''#!/usr/bin/env bash
                        set -euo pipefail
                        stable=$(sed -n 's/^stable=//p' reports/images.txt)
                        candidate=$(sed -n 's/^candidate=//p' reports/images.txt)
                        bash ci/deploy.sh "$stable" 1.0.0 "$candidate" "$APP_VERSION" 2>&1 | tee reports/deploy.log
                    '''
                }
            }
        }
    }

    post {
        always {
            junit testResults: 'reports/junit.xml', allowEmptyResults: true
            archiveArtifacts artifacts: 'reports/*', allowEmptyArchive: true
        }
    }
}
