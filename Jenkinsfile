def imageTag = ''

pipeline {
    agent any

    environment {
        DOCKER_BUILDKIT   = '1'
        BUILDKIT_PROGRESS = 'plain'
        HARBOR_PROJECT    = 'sample-microservice'
        SONAR_PROJECT_KEY = 'microservices-demo'
        SONAR_HOST_URL    = 'http://3.0.195.225:9000'
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
        booleanParam(name: 'CLEANUP_LOCAL', defaultValue: true)

        string(name: 'HARBOR_REGISTRY', defaultValue: '3.0.195.225:80')
        string(name: 'GITOPS_REPO', defaultValue: 'git@github.com:your-org/gitops-microservices-demo.git')
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
                    echo "Image tag: ${imageTag}"
                }
            }
        }


        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh 'mvn clean verify sonar:sonar'
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 2, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }


        stage('Login to Harbor') {
            when {
                expression { params.PUSH_IMAGES }
            }
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'harbor-creds',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASS'
                    )]) {
                        sh '''
                            echo "$HARBOR_PASS" | docker login 3.0.195.225:80 \
                            -u "$HARBOR_USER" --password-stdin
                        '''
                    }
                }
            }
        }


        stage('Build Images') {
            steps {
                script {
                    getBuildServices().each { svc ->

                        def dockerfilePath = resolveDockerfilePath(svc)
                        def buildContext = (svc == 'cartservice')
                            ? 'src/cartservice/src'
                            : "src/${svc}"

                        sh """
                            docker build \
                                -f ${dockerfilePath} \
                                -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                ${buildContext}
                        """
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
                        sh """
                            docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag}
                        """
                    }
                }
            }
        }


        stage('Update GitOps Repo') {
            when {
                expression { params.PUSH_IMAGES }
            }

            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: 'git-ssh-key',
                    keyFileVariable: 'SSH_KEY'
                )]) {

                    sh '''
                        eval $(ssh-agent -s)
                        ssh-add $SSH_KEY

                        rm -rf gitops
                        git clone ${params.GITOPS_REPO} gitops
                    '''

                    script {
                        getBuildServices().each { svc ->
                            sh """
                                cd gitops
                                yq e '.image.tag = "${imageTag}"' -i helm/${svc}/values.yaml
                            """
                        }
                    }

                    sh '''
                        cd gitops
                        git config user.email "jenkins@local"
                        git config user.name "jenkins"

                        git add .
                        git commit -m "update images ${imageTag}" || echo "No changes"
                        git push
                    '''
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
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} || true
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            sh "docker logout 3.0.195.225:80 || true"
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

    def path = sh(script: """
        if [ -f src/${service}/Dockerfile ]; then
            echo src/${service}/Dockerfile
        elif [ -f src/${service}/src/Dockerfile ]; then
            echo src/${service}/src/Dockerfile
        else
            find src/${service} -name Dockerfile | head -1
        fi
    """, returnStdout: true).trim()

    if (!path) {
        error "No Dockerfile found for ${service}"
    }

    return path
}