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

        string(name: 'HARBOR_REGISTRY', defaultValue: 'harbor.thenttthytlu.io.vn')
        string(name: 'GITOPS_REPO', defaultValue: 'https://github.com/nt114thenttthytlu/gitops-for-microservices-demo.git')
    }

    stages {

        stage('Checkout') {
            steps {
                script {
                    checkout scm
                    echo "Checked out — commit: ${env.GIT_COMMIT}"
                }
            }
        }

        stage('Prepare Image Tag') {
            steps {
                script {
                    def gitShort    = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    def buildNumber = env.BUILD_NUMBER
                    imageTag = "${buildNumber}-${gitShort}"
                    echo "Image tag: ${imageTag}"
                }
            }
        }

        stage('.NET + SonarQube') {
            when { expression { params.RUN_SONAR } }

            steps {
                script {
                    echo 'Validating service Dockerfiles...'
                    getBuildServices().each { service ->
                        def path = resolveDockerfilePath(service)
                        echo "${service} → ${path}"
                    }
                }
            }
        }

        stage('Build & Analyze Services') {
            steps {
                script {
                    stash name: 'source', includes: 'src/**'

                    def parallelStages = [:]

                    getBuildServices().each { service ->
                        def svc = service

                        parallelStages[svc] = {
                            node {
                                unstash 'source'

                                def dockerfilePath = resolveDockerfilePath(svc)
                                def buildContext   = (svc == 'cartservice') ? 'src/cartservice/src' : "src/${svc}"

                                stage("${svc}: SonarQube Scan") {
                                    try {
                                        dir("src/${svc}") {
                                            def scannerHome = tool 'Sonarqube'
                                            withSonarQubeEnv() {
                                                sh """
                                                    ${scannerHome}/bin/sonar-scanner \
                                                        -Dsonar.projectKey=${svc} \
                                                        -Dsonar.sources=.
                                                """
                                            }
                                        }
                                        echo "${svc} scan completed"
                                    } catch (e) {
                                        echo "${svc} scan failed — ${e.message}"
                                    }
                                }

                                stage("${svc}: Build Docker Image") {
                                    sh """
                                        docker build \
                                            -f ${dockerfilePath} \
                                            -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                            -t ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest \
                                            ${buildContext}
                                    """
                                    echo "${svc} image built"
                                }
                            }
                        }
                    }

            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Login Harbor') {
            when { expression { params.PUSH_IMAGES } }

            steps {
                echo 'Security scan placeholder'
            }
        }

        stage('Build Images') {
            steps {
                script {
                    echo "Pushing images (tag: ${imageTag})..."

                    sh '''
                        curl -sf -k https://${HARBOR_REGISTRY}/api/v2.0/health \
                            && echo "Harbor reachable" \
                            || echo "Harbor may not be reachable"
                    '''

                            def dockerfilePath = resolveDockerfilePath(svc)

                            def buildContext = (svc == 'cartservice')
                                ? 'src/cartservice/src'
                                : "src/${svc}"

                            sh """
                                if docker image inspect ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} >/dev/null 2>&1; then
                                    docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag}
                                    docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest
                                    echo " ${svc} pushed"
                                else
                                    echo "Image not found for ${svc}, skipping push"
                                fi
                            """
                        }
                    }
                }
            }
        }

        stage('Cleanup Local Images') {
            when {
                expression { params.PUSH_IMAGES }
            }

            steps {
                script {
                    echo "Removing local images (tag: ${imageTag})..."
                    getBuildServices().each { svc ->
                        sh """
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} || true
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest       || true
                        """
                    }
                    sh 'docker image prune -f'
                    echo "Local cleanup done"
                }
            }
        }
        
        stage('Update GitOps Repo') {

        stage('Cleanup Harbor Old Tags') {
            when {
                expression { params.UPDATE_GITOPS }
            }

            steps {
                script {
                    def keepN = params.KEEP_TAGS.toInteger()
                    echo "Cleaning up Harbor — keeping ${keepN} most recent tags per service..."

                withCredentials([
                    usernamePassword(
                        credentialsId: 'github-token',
                        usernameVariable: 'GITHUB_USER',
                        passwordVariable: 'GITHUB_TOKEN'
                    )
                ]) {

                    script {

                        sh """
                            rm -rf gitops

                            git clone \
                            https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/nt114thenttthytlu/gitops-for-microservices-demo.git \
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

                                    grep -A2 image: \$VALUES_FILE || true

                                else
                                    echo "Skip ${svc} - values.yaml not found"
                                fi
                            """
                        }

                        sh """
                            cd gitops

                            git add .

                            git remote -v
                            git config --get remote.origin.url

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
                    echo "Harbor cleanup done"
                }
            }
        }
    }

    post {
        always  { sh 'docker logout || true' }
        success { echo 'Pipeline succeeded!' }
        failure { echo 'Pipeline failed!'   }
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


def cleanupHarborOldTags(String service, int keepN) {
    sh """
        set -euo pipefail

        REGISTRY="${params.HARBOR_REGISTRY}"
        PROJECT="${HARBOR_PROJECT}"
        SVC="${service}"
        KEEP=${keepN}

        API="https://\${REGISTRY}/api/v2.0/projects/\${PROJECT}/repositories/\${SVC}/artifacts"

        # Fetch artifacts sorted by push_time desc, page size 100 (adjust if you have more)
        ARTIFACTS=\$(curl -sf -k -u "\${HARBOR_USER}:\${HARBOR_PASS}" \
            "\${API}?page_size=100&page=1&with_tag=true&sort=-push_time")

        # Extract digests to delete: skip the first KEEP entries, skip anything tagged "latest"
        DIGESTS_TO_DELETE=\$(echo "\${ARTIFACTS}" | \
            python3 -c "
import sys, json

data   = json.load(sys.stdin)
kept   = 0
result = []

for artifact in data:
    tags = [t['name'] for t in (artifact.get('tags') or [])]
    # Always preserve the 'latest' tag
    if 'latest' in tags:
        continue
    if kept < int('${keepN}'):
        kept += 1
        continue
    result.append(artifact['digest'])

print('\n'.join(result))
")

        if [ -z "\${DIGESTS_TO_DELETE}" ]; then
            echo "  ✓ \${SVC}: nothing to delete (≤ \${KEEP} tags)"
            exit 0
        fi

        echo "\${DIGESTS_TO_DELETE}" | while IFS= read -r digest; do
            echo "  Deleting \${SVC}@\${digest}..."
            curl -sf -k -X DELETE -u "\${HARBOR_USER}:\${HARBOR_PASS}" \
                "\${API}/\${digest}" \
                && echo "  ✓ Deleted \${digest}" \
                || echo "  ⚠ Failed to delete \${digest} — skipping"
        done
    """
}
