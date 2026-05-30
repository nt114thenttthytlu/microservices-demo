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

        booleanParam(
            name: 'PUSH_IMAGES',
            defaultValue: true,
            description: 'Push images to Harbor'
        )

        booleanParam(
            name: 'CLEANUP_LOCAL',
            defaultValue: true,
            description: 'Remove local images after push'
        )

        string(
            name: 'HARBOR_REGISTRY',
            defaultValue: '3.0.195.225:80',
            description: 'Harbor registry'
        )

        string(
            name: 'KEEP_TAGS',
            defaultValue: '5',
            description: 'Number of tags to keep'
        )
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                script {
                    echo "✓ Commit: ${env.GIT_COMMIT}"
                }
            }
        }

        stage('Prepare Image Tag') {
            steps {
                script {
                    def gitShort = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    imageTag = "${env.BUILD_NUMBER}-${gitShort}"

                    echo "✓ Image tag: ${imageTag}"
                }
            }
        }

        stage('Validate Dockerfiles') {
            steps {
                script {

                    getBuildServices().each { svc ->

                        def dockerfilePath = resolveDockerfilePath(svc)

                        echo "✓ ${svc} -> ${dockerfilePath}"
                    }
                }
            }
        }

        stage('Build Docker Images') {

            steps {

                script {

                    def builds = [:]

                    getBuildServices().each { service ->

                        def svc = service

                        builds[svc] = {

                            def dockerfilePath = resolveDockerfilePath(svc)

                            def buildContext =
                                (svc == 'cartservice')
                                    ? 'src/cartservice/src'
                                    : "src/${svc}"

                            stage("Build ${svc}") {

                                sh """
                                    docker build \
                                        -f ${dockerfilePath} \
                                        -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                        -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest \
                                        ${buildContext}
                                """

                                echo "✓ ${svc} built"
                            }
                        }
                    }

                    parallel builds
                }
            }
        }

        stage('Docker Login') {

            when {
                expression { params.PUSH_IMAGES == true }
            }

            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'jenkin-cred',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASS'
                    )
                ]) {

                    sh """
                        echo \$HARBOR_PASS | docker login ${params.HARBOR_REGISTRY} \
                        -u \$HARBOR_USER \
                        --password-stdin
                    """
                }
            }
        }

        stage('Push Images') {

            when {
                expression { params.PUSH_IMAGES == true }
            }

            steps {

                script {

                    getBuildServices().each { svc ->

                        sh """
                            docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag}

                            docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest
                        """

                        echo "✓ ${svc} pushed"
                    }
                }
            }
        }

        stage('Cleanup Local Images') {

            when {
                allOf {
                    expression { params.PUSH_IMAGES == true }
                    expression { params.CLEANUP_LOCAL == true }
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

                    sh 'docker image prune -f'

                    echo '✓ Local cleanup done'
                }
            }
        }

        stage('Cleanup Harbor Old Tags') {

            when {
                allOf {
                    expression { params.PUSH_IMAGES == true }
                    expression { params.KEEP_TAGS.toInteger() > 0 }
                }
            }

            steps {

                script {

                    def keepN = params.KEEP_TAGS.toInteger()

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'jenkin-cred',
                            usernameVariable: 'HARBOR_USER',
                            passwordVariable: 'HARBOR_PASS'
                        )
                    ]) {

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
            echo '✓ Pipeline Success'
        }

        failure {
            echo '✗ Pipeline Failed'
        }
    }
}

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

    return (
        params.BUILD_TARGET == 'all'
    )
        ? getServiceList()
        : [params.BUILD_TARGET]
}

def resolveDockerfilePath(String service) {

    def serviceDir = "src/${service}"

    def path = sh(
        script: """
            for candidate in \
                "${serviceDir}/Dockerfile" \
                "${serviceDir}/src/Dockerfile" \
                "${serviceDir}/docker/Dockerfile" \
                "${serviceDir}/build/Dockerfile"; do

                [ -f "\$candidate" ] && echo "\$candidate" && exit 0

            done

            find "${serviceDir}" -name Dockerfile | head -1
        """,
        returnStdout: true
    ).trim()

    if (!path) {
        error "No Dockerfile found for ${service}"
    }

    return path
}

def cleanupHarborOldTags(String service, int keepN) {

    sh """
        set -e

        API="http://${params.HARBOR_REGISTRY}/api/v2.0/projects/${HARBOR_PROJECT}/repositories/${service}/artifacts"

        ARTIFACTS=\$(curl -s -u "\${HARBOR_USER}:\${HARBOR_PASS}" \
            "\${API}?page_size=100&page=1&with_tag=true&sort=-push_time")

        DIGESTS=\$(echo "\${ARTIFACTS}" | python3 -c "
import sys, json

data = json.load(sys.stdin)

keep = ${keepN}
count = 0

for artifact in data:

    tags = artifact.get('tags') or []

    names = [t['name'] for t in tags]

    if 'latest' in names:
        continue

    if count < keep:
        count += 1
        continue

    print(artifact['digest'])
")

        if [ -z "\${DIGESTS}" ]; then
            echo 'Nothing to cleanup'
            exit 0
        fi

        echo "\${DIGESTS}" | while read digest; do

            curl -s -X DELETE \
                -u "\${HARBOR_USER}:\${HARBOR_PASS}" \
                "\${API}/\${digest}"

            echo "Deleted: \${digest}"

        done
    """
}
