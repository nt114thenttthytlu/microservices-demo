def imageTag = ''

pipeline {
    agent any

    environment {
        DOCKER_BUILDKIT   = '1'
        BUILDKIT_PROGRESS = 'plain'

        HARBOR_PROJECT    = 'sample-microservice'
        REGISTRY          = "${params.HARBOR_REGISTRY}"
        SONAR_PROJECT_KEY = "microservices-demo"

        GITOPS_REPO = "https://github.com/nt114thenttthytlu/gitops-for-microservices-demo.git"
    }

    parameters {

        choice(
            name: 'BUILD_TARGET',
            choices: [
                'all',
                'adservice',
                'cartservice',
                'checkoutservice',
                'currencyservice',
                'emailservice',
                'frontend',
                'paymentservice',
                'productcatalogservice',
                'recommendationservice',
                'shippingservice',
                'shoppingassistantservice'
            ]
        )

        booleanParam(name: 'RUN_SONAR', defaultValue: true)
        booleanParam(name: 'RUN_GITOPS', defaultValue: true)
        booleanParam(name: 'PUSH_IMAGES', defaultValue: true)
        booleanParam(name: 'CLEANUP_LOCAL', defaultValue: true)

        string(name: 'HARBOR_REGISTRY', defaultValue: '3.0.195.225:80')
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
                    imageTag = "${env.BUILD_NUMBER}-${gitShort}"
                }
            }
        }

        stage('.NET & SonarQube Analysis') {
            when {
                expression { params.RUN_SONAR }
            }

            steps {
                script {

                    sh '''
                        set -e

                        apt-get update || true
                        apt-get install -y wget ca-certificates libicu-dev

                        wget -q https://dot.net/v1/dotnet-install.sh
                        chmod +x dotnet-install.sh
                        ./dotnet-install.sh --channel 8.0 --install-dir /root/.dotnet

                        export DOTNET_ROOT=/root/.dotnet
                        export PATH=$PATH:/root/.dotnet:/root/.dotnet/tools
                    '''

                    withSonarQubeEnv('sonarqube') {
                        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {

                            sh '''
                                set -e
                                cd src/cartservice

                                dotnet tool install --global dotnet-sonarscanner || true
                                export PATH=$PATH:/root/.dotnet/tools

                                dotnet restore

                                dotnet sonarscanner begin \
                                    /k:$SONAR_PROJECT_KEY \
                                    /d:sonar.host.url=$SONAR_HOST_URL \
                                    /d:sonar.login=$SONAR_TOKEN \
                                    /d:sonar.exclusions="**/Dockerfile*"

                                dotnet build

                                dotnet sonarscanner end /d:sonar.login=$SONAR_TOKEN
                            '''
                        }
                    }
                }
            }
        }

        stage('Quality Gate') {
            when {
                expression { params.RUN_SONAR }
            }

            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Login to Harbor') {
            when {
                expression { params.PUSH_IMAGES }
            }

            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'harbor-creds',
                    usernameVariable: 'HARBOR_USER',
                    passwordVariable: 'HARBOR_PASS'
                )]) {
                    sh '''
                        set -e
                        echo "$HARBOR_PASS" | docker login $REGISTRY \
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
                                set -e

                                docker build \
                                    -f ${dockerfilePath} \
                                    -t $REGISTRY/$HARBOR_PROJECT/${svc}:${imageTag} \
                                    -t $REGISTRY/$HARBOR_PROJECT/${svc}:latest \
                                    ${buildContext}
                            """
                        }
                    }
                }
            }
        }

        stage('Push Images') {
            when {
                expression { params.PUSH_IMAGES }
            }

            steps {
                script {
                    getBuildServices().each { svc ->

                        stage("Push ${svc}") {
                            sh """
                                docker push $REGISTRY/$HARBOR_PROJECT/${svc}:${imageTag}
                                docker push $REGISTRY/$HARBOR_PROJECT/${svc}:latest
                            """
                        }
                    }
                }
            }
        }

        stage('Update GitOps Repo') {
            when {
                expression { params.RUN_GITOPS }
            }

            steps {
                script {

                    def gitopsDir = "gitops-repo"

                    sh """
                        rm -rf ${gitopsDir}
                        git clone ${GITOPS_REPO} ${gitopsDir}
                    """

                    getBuildServices().each { svc ->

                        sh """
                            set -e

                            FILE=${gitopsDir}/apps/${svc}/values.yaml

                            if [ ! -f \$FILE ]; then
                                echo "❌ GitOps file not found: \$FILE"
                                exit 1
                            fi

                            # update image tag
                            sed -i 's#tag:.*#tag: ${imageTag}#g' \$FILE
                            sed -i 's#repository:.*#repository: ${REGISTRY}/${HARBOR_PROJECT}/${svc}#g' \$FILE
                        """
                    }

                    sh """
                        cd ${gitopsDir}

                        git config user.email "jenkins@ci.local"
                        git config user.name "jenkins"

                        git add .
                        git commit -m "update images ${imageTag}" || true
                        git push origin main || true
                    """
                }
            }
        }

        stage('Cleanup Local Images') {
            when {
                expression { params.CLEANUP_LOCAL }
            }

            steps {
                script {
                    getBuildServices().each { svc ->
                        sh """
                            docker rmi $REGISTRY/$HARBOR_PROJECT/${svc}:${imageTag} || true
                            docker rmi $REGISTRY/$HARBOR_PROJECT/${svc}:latest || true
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            sh "docker logout $REGISTRY || true"
        }

        success {
            echo "SUCCESS: ImageTag: ${imageTag}"
        }

        failure {
            echo "FAILED: Check logs"
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