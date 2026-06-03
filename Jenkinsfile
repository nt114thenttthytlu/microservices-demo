def imageTag = ''

pipeline {
    agent any

    environment {
        DOCKER_BUILDKIT   = '1'
        BUILDKIT_PROGRESS = 'plain'

        HARBOR_PROJECT    = 'sample-microservice'

        DOTNET_ROOT = '/root/.dotnet'
        PATH = "/root/.dotnet:/root/.dotnet/tools:${env.PATH}"
    }

    parameters {
        choice(
            name: 'BUILD_TARGET',
            choices: [
                'all',
                'adservice','cartservice','checkoutservice','currencyservice',
                'emailservice','frontend','paymentservice',
                'productcatalogservice','recommendationservice',
                'shippingservice','shoppingassistantservice'
            ]
        )

        booleanParam(name: 'PUSH_IMAGES', defaultValue: true)
        booleanParam(name: 'RUN_SONAR', defaultValue: true)
        booleanParam(name: 'UPDATE_GITOPS', defaultValue: true)

        string(name: 'HARBOR_REGISTRY', defaultValue: '3.0.195.225:80')
        string(name: 'GITOPS_REPO', defaultValue: 'https://github.com/nt114thenttthytlu/gitops-repo.git')
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Prepare Image Tag') {
            steps {
                script {
                    def gitShort = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    imageTag = "${BUILD_NUMBER}-${gitShort}"
                    echo "IMAGE TAG = ${imageTag}"
                }
            }
        }

        stage('.NET + SonarQube') {
            when { expression { params.RUN_SONAR } }

            steps {
                withSonarQubeEnv('sonarqube') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {

                        sh '''#!/bin/bash
                        set -e

                        cd src/cartservice

                        echo ">>> Install dotnet-sonarscanner"
                        dotnet tool install --global dotnet-sonarscanner || true

                        echo ">>> Restore"
                        dotnet restore

                        echo ">>> Begin Sonar"
                        dotnet sonarscanner begin \
                          /k:microservices-demo-cartservice \
                          /d:sonar.host.url=$SONAR_HOST_URL \
                          /d:sonar.login=$SONAR_TOKEN \
                          /d:sonar.exclusions="**/Dockerfile*"

                        echo ">>> Build"
                        dotnet build

                        echo ">>> End Sonar"
                        dotnet sonarscanner end /d:sonar.login=$SONAR_TOKEN
                        '''
                    }
                }
            }
        }

        stage('Quality Gate') {
            when { expression { params.RUN_SONAR } }

            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Login Harbor') {
            when { expression { params.PUSH_IMAGES } }

            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'harbor-creds',
                    usernameVariable: 'HARBOR_USER',
                    passwordVariable: 'HARBOR_PASS'
                )]) {
                    sh '''#!/bin/bash
                    set -e
                    echo "$HARBOR_PASS" | docker login $HARBOR_REGISTRY \
                        -u "$HARBOR_USER" --password-stdin
                    '''
                }
            }
        }

        stage('Build Images') {
            steps {
                script {
                    getBuildServices().each { svc ->

                        stage("Build ${svc}") {

                            def dockerfilePath = resolveDockerfilePath(svc)

                            def buildContext = (svc == 'cartservice')
                                ? 'src/cartservice/src'
                                : "src/${svc}"

                            sh """
                                docker build \
                                  -f ${dockerfilePath} \
                                  -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                  -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest \
                                  ${buildContext}
                            """
                        }
                    }
                }
            }
        }

        stage('Push Images') {
            when { expression { params.PUSH_IMAGES } }

            steps {
                script {
                    getBuildServices().each { svc ->
                        stage("Push ${svc}") {
                            sh """
                                docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag}
                                docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest
                            """
                        }
                    }
                }
            }
        }

        stage('Update GitOps Repo') {
            when {
                expression { params.UPDATE_GITOPS }
            }

            steps {

                withCredentials([
                    string(
                        credentialsId: 'github-token',
                        variable: 'GITHUB_TOKEN'
                    )
                ]) {

                    script {

                        sh """
                            rm -rf gitops

                            git clone \
                            https://${GITHUB_TOKEN}@github.com/nt114thenttthytlu/gitops-for-microservices-demo.git \
                            gitops

                            cd gitops

                            git config user.email "jenkins@local"
                            git config user.name "jenkins"
                        """

                        getBuildServices().each { svc ->

                            sh """
                                cd gitops

                                VALUES_FILE="${svc}/values.yaml"

                                if [ -f "\$VALUES_FILE" ]; then

                                    echo "Updating \$VALUES_FILE"

                                    sed -i "s|repository:.*|repository: ${params.HARBOR_REGISTRY}/${env.HARBOR_PROJECT}/${svc}|g" \$VALUES_FILE

                                    sed -i "s|tag:.*|tag: ${imageTag}|g" \$VALUES_FILE

                                    cat \$VALUES_FILE | grep -A2 image:
                                else
                                    echo "Skip ${svc} - values.yaml not found"
                                fi
                            """
                        }

                        sh """
                            cd gitops

                            git add .

                            git diff --cached --quiet || \
                            git commit -m "ci: update images to ${imageTag}"

                            git push origin main
                        """
                    }
                }
            }
        }

        stage('Cleanup Local Images') {
            steps {
                script {
                    getBuildServices().each { svc ->
                        sh """
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} || true
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest || true
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            sh "docker logout ${params.HARBOR_REGISTRY} || true"
        }
    }
}


def getServiceList() {
    return [
        'adservice','cartservice','checkoutservice','currencyservice',
        'emailservice','frontend','paymentservice',
        'productcatalogservice','recommendationservice',
        'shippingservice','shoppingassistantservice'
    ]
}

def getBuildServices() {
    return (params.BUILD_TARGET == 'all')
        ? getServiceList()
        : [params.BUILD_TARGET]
}

def resolveDockerfilePath(String service) {

    def serviceDir = "src/${service}"

    def path = sh(script: """
        for c in \
            "${serviceDir}/Dockerfile" \
            "${serviceDir}/src/Dockerfile" \
            "${serviceDir}/docker/Dockerfile"; do
            [ -f "\$c" ] && echo "\$c" && exit 0
        done
        find "${serviceDir}" -name Dockerfile | head -1
    """, returnStdout: true).trim()

    if (!path) {
        error "No Dockerfile found for ${service}"
    }

    return path
}