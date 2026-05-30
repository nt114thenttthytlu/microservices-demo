def imageTag = ''

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
            ],
            description: 'Select service(s) to build'
        )

        booleanParam(name: 'PUSH_IMAGES', defaultValue: true)
        booleanParam(name: 'CLEANUP_LOCAL', defaultValue: true)

        string(name: 'HARBOR_REGISTRY', defaultValue: '3.0.195.225:80')
        string(name: 'KEEP_TAGS', defaultValue: '5')
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                echo "Commit: ${env.GIT_COMMIT}"
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

        stage('Validate Dockerfiles') {
            steps {
                script {
                    getBuildServices().each { svc ->
                        def path = resolveDockerfilePath(svc)
                        echo "${svc} -> ${path}"
                    }
                }
            }
        }

        stage('Build Docker Images (SEQUENTIAL)') {
            steps {
                script {

                    getBuildServices().each { svc ->

                        stage("Build ${svc}") {

                            def dockerfilePath = resolveDockerfilePath(svc)

                            def buildContext =
                                (svc == 'cartservice')
                                    ? 'src/cartservice/src'
                                    : "src/${svc}"

                            sh """
                                docker build \
                                    -f ${dockerfilePath} \
                                    -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                    -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest \
                                    ${buildContext}
                            """

                            echo "Built: ${svc}"
                        }
                    }
                }
            }
        }

        stage('Docker Login') {
            when {
                expression { params.PUSH_IMAGES }
            }

            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'jenkin-cred',
                    usernameVariable: 'HARBOR_USER',
                    passwordVariable: 'HARBOR_PASS'
                )]) {

                    sh """
                        echo \$HARBOR_PASS | docker login ${params.HARBOR_REGISTRY} \
                        -u \$HARBOR_USER --password-stdin
                    """
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
                            docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest
                        """

                        echo "Pushed: ${svc}"
                    }
                }
            }
        }

        stage('Cleanup Local Images') {
            when {
                allOf {
                    expression { params.PUSH_IMAGES }
                    expression { params.CLEANUP_LOCAL }
                }
            }

            steps {
                script {
                    getBuildServices().each { svc ->
                        sh """
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} || true
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest || true
                        """
                    }

                    sh "docker image prune -f"
                    echo "Cleanup done"
                }
            }
        }

        stage('Cleanup Harbor Old Tags') {
            when {
                expression { params.PUSH_IMAGES && params.KEEP_TAGS.toInteger() > 0 }
            }

            steps {
                script {
                    def keepN = params.KEEP_TAGS.toInteger()

                    withCredentials([usernamePassword(
                        credentialsId: 'jenkin-cred',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASS'
                    )]) {

                        getBuildServices().each { svc ->
                            cleanupHarborOldTags(svc, keepN)
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }

        success {
            echo "Pipeline SUCCESS"
        }

        failure {
            echo "Pipeline FAILED"
        }
    }
}

---

# Helpers

def getServiceList() {
    return [
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
            "${serviceDir}/docker/Dockerfile" \
            "${serviceDir}/build/Dockerfile"; do
            [ -f "\$c" ] && echo "\$c" && exit 0
        done

        find "${serviceDir}" -name Dockerfile | head -1
    """, returnStdout: true).trim()

    if (!path) {
        error "No Dockerfile found for ${service}"
    }

    return path
}

def cleanupHarborOldTags(String service, int keepN) {

    sh """
        set -e

        API="http://${params.HARBOR_REGISTRY}/api/v2.0/projects/${HARBOR_PROJECT}/repositories/${service}/artifacts"

        ARTIFACTS=\$(curl -s -u "\${HARBOR_USER}:\${HARBOR_PASS}" "\${API}?page_size=100&sort=-push_time")

        echo "\$ARTIFACTS" | python3 - <<EOF
import sys, json

data = json.load(sys.stdin)

keep = ${keepN}
count = 0

for a in data:
    tags = a.get('tags') or []
    names = [t['name'] for t in tags]

    if 'latest' in names:
        continue

    if count < keep:
        count += 1
        continue

    print(a['digest'])
EOF
    """
}