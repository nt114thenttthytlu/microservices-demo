def imageTag = ''
def services = []

pipeline {
    agent any

    environment {
        HARBOR_PROJECT  = 'sample-microservice'
        HARBOR_REGISTRY = '3.0.195.225:80'
        SONAR_HOST_URL  = 'http://52.76.101.147:9000'

        DOTNET_ROOT = '/root/.dotnet'
        PATH = "/root/.dotnet:/root/.dotnet/tools:${env.PATH}"
    }

    parameters {
        choice(name: 'BUILD_TARGET', choices: ['all', 'cartservice', 'frontend'])
        booleanParam(name: 'PUSH_IMAGES', defaultValue: true)
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
                    services = sh(
                        script: "find src -maxdepth 1 -type d -name '*service*' -exec basename {} \\;",
                        returnStdout: true
                    ).trim().split("\n")

                    echo "Detected services: ${services}"
                }
            }
        }

        stage('Prepare Tag') {
            steps {
                script {
                    def gitShort = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    imageTag = "${env.BUILD_NUMBER}-${gitShort}"
                    echo "ImageTag: ${imageTag}"
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh '''
                            dotnet tool install --global dotnet-sonarscanner || true
                            export PATH=$PATH:/root/.dotnet/tools

                            cd src/cartservice
                            dotnet restore

                            dotnet sonarscanner begin \
                                /k:"microservices-demo-cartservice" \
                                /d:sonar.host.url="$SONAR_HOST_URL" \
                                /d:sonar.login="$SONAR_TOKEN"

                            dotnet build

                            dotnet sonarscanner end \
                                /d:sonar.login="$SONAR_TOKEN"
                        '''
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

        stage('Build Images') {
            steps {
                script {

                    def buildList = (params.BUILD_TARGET == 'all')
                        ? services
                        : [params.BUILD_TARGET]

                    for (svc in buildList) {

                        echo "Building service: ${svc}"

                        def dockerfile = "src/${svc}/Dockerfile"
                        def context = "src/${svc}"

                        sh """
                            docker build \
                            -f ${dockerfile} \
                            -t ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                            ${context}
                        """
                    }
                }
            }
        }

        stage('Push Images') {
            when { expression { params.PUSH_IMAGES } }
            steps {
                script {

                    def buildList = (params.BUILD_TARGET == 'all')
                        ? services
                        : [params.BUILD_TARGET]

                    for (svc in buildList) {
                        sh """
                            docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag}
                        """
                    }
                }
            }
        }

        stage('Update GitOps') {
            when { expression { params.PUSH_IMAGES } }
            steps {

                sh '''
                    rm -rf gitops
                    git clone ${GITOPS_REPO} gitops
                '''

                script {

                    def buildList = (params.BUILD_TARGET == 'all')
                        ? services
                        : [params.BUILD_TARGET]

                    for (svc in buildList) {
                        sh """
                            yq e '.image.tag = "${imageTag}"' -i gitops/helm/${svc}/values.yaml
                        """
                    }
                }

                sh '''
                    cd gitops
                    git config user.email "jenkins@local"
                    git config user.name "jenkins"

                    git add .
                    git commit -m "update ${imageTag}" || true
                    git push
                '''
            }
        }

        stage('Cleanup') {
            steps {
                script {

                    def buildList = (params.BUILD_TARGET == 'all')
                        ? services
                        : [params.BUILD_TARGET]

                    for (svc in buildList) {
                        sh """
                            docker rmi ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} || true
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            sh "docker logout ${HARBOR_REGISTRY} || true"
        }
    }
}