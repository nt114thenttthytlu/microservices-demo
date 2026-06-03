def imageTag = ''
def services = []

pipeline {
    agent any

    environment {
        DOCKER_BUILDKIT   = '1'
        BUILDKIT_PROGRESS = 'plain'
        HARBOR_PROJECT    = 'sample-microservice'
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

        booleanParam(name: 'PUSH_IMAGES', defaultValue: true)
        booleanParam(name: 'CLEANUP_LOCAL', defaultValue: true)

        string(name: 'HARBOR_REGISTRY', defaultValue: '3.0.195.225:80')
    }

    stages {

        stage('Checkout') {
            steps {
                cleanWs()
                checkout scm
            }
        }

        stage('Detect Services') {
            steps {
                script {
                    services = getServiceList()
                    echo "All services: ${services}"
                }
            }
        }

        stage('Prepare Image Tag') {
            steps {
                script {
                    def gitShort = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    imageTag = "${env.BUILD_NUMBER}-${gitShort}"
                    echo "ImageTag = ${imageTag}"
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    def svc = (params.BUILD_TARGET == 'all') ? 'cartservice' : params.BUILD_TARGET

                    withSonarQubeEnv('sonarqube') {
                        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {

                            sh """
                                dotnet tool install --global dotnet-sonarscanner || true
                                export PATH=\$PATH:/root/.dotnet/tools

                                cd src/${svc}
                                dotnet restore

                                dotnet sonarscanner begin \
                                    /k:"microservices-demo-${svc}" \
                                    /d:sonar.host.url="$SONAR_HOST_URL" \
                                    /d:sonar.login="$SONAR_TOKEN"

                                dotnet build

                                dotnet sonarscanner end \
                                    /d:sonar.login="$SONAR_TOKEN"
                            """
                        }
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Images (SEQUENTIAL)') {
            steps {
                script {

                    def buildList = (params.BUILD_TARGET == 'all')
                        ? services
                        : [params.BUILD_TARGET]

                    for (svc in buildList) {

                        echo "Building: ${svc}"

                        def dockerfile = resolveDockerfilePath(svc)
                        def context = "src/${svc}"

                        sh """
                            docker build \
                                -f ${dockerfile} \
                                -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest \
                                ${context}
                        """
                    }
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
                    sh """
                        echo $HARBOR_PASS | docker login ${params.HARBOR_REGISTRY} \
                        -u $HARBOR_USER --password-stdin
                    """
                }
            }
        }

        stage('Push Images (SEQUENTIAL)') {
            when { expression { params.PUSH_IMAGES } }

            steps {
                script {

                    def buildList = (params.BUILD_TARGET == 'all')
                        ? services
                        : [params.BUILD_TARGET]

                    for (svc in buildList) {

                        echo "Pushing: ${svc}"

                        sh """
                            docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag}
                            docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest
                        """
                    }
                }
            }
        }

        stage('Cleanup Local Images') {
            when { expression { params.CLEANUP_LOCAL } }

            steps {
                script {

                    def buildList = (params.BUILD_TARGET == 'all')
                        ? services
                        : [params.BUILD_TARGET]

                    for (svc in buildList) {

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