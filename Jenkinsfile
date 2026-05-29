def imageTag = ''

pipeline {
    agent any

    environment {
        DOCKER_BUILDKIT     = '1'
        BUILDKIT_PROGRESS   = 'plain'
        HARBOR_PROJECT      = 'sample-microservice'
    }

    parameters {
        choice(
            name: 'BUILD_TARGET',
            choices: ['all', 'adservice', 'cartservice', 'checkoutservice', 'currencyservice',
                      'emailservice', 'frontend', 'paymentservice', 'productcatalogservice',
                      'recommendationservice', 'shippingservice', 'shoppingassistantservice'],
            description: 'Select which service(s) to build'
        )
        booleanParam(name: 'PUSH_IMAGES',        defaultValue: true,                  description: 'Push Docker images to Harbor?')
        booleanParam(name: 'CLEANUP_LOCAL',       defaultValue: true,                  description: 'Remove local Docker images after push?')
        string(name: 'HARBOR_REGISTRY',          defaultValue: '13.212.31.75:80',            description: 'Harbor registry URL (e.g., 192.168.1.100)')
        string(name: 'SONARQUBE_URL',            defaultValue: 'http://sonarqube:9000',description: 'SonarQube server URL')
        string(name: 'KEEP_TAGS',                defaultValue: '5',                    description: 'Number of recent tags to keep in Harbor per service (0 = skip Harbor cleanup)')
    }

    stages {

        stage('Checkout') {
            steps {
                script {
                    checkout scm
                    echo "✓ Checked out — commit: ${env.GIT_COMMIT}"
                }
            }
        }

        stage('Prepare Image Tag') {
            steps {
                script {
                    def gitShort    = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    def buildNumber = env.BUILD_NUMBER
                    imageTag = "${buildNumber}-${gitShort}"
                    echo "✓ Image tag: ${imageTag}"
                }
            }
        }

        stage('Validate Services') {
            steps {
                script {
                    echo '✓ Validating service Dockerfiles...'
                    getBuildServices().each { service ->
                        def path = resolveDockerfilePath(service)
                        echo "  ✓ ${service} → ${path}"
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
                                        echo "  ✓ ${svc} scan completed"
                                    } catch (e) {
                                        echo "  ⚠ ${svc} scan failed — ${e.message}"
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
                                    echo "  ✓ ${svc} image built"
                                }
                            }
                        }
                    }

                    parallel parallelStages
                }
            }
        }

        stage('Security Scan') {
            when { branch 'main' }
            steps {
                echo '✓ Security scan placeholder'
            }
        }

        stage('Push Docker Images') {
            when {
                expression { params.PUSH_IMAGES == true }
            }
            steps {
                script {
                    echo "✓ Pushing images (tag: ${imageTag})..."

                    sh '''
                        curl -sf https://${HARBOR_REGISTRY}/api/v2.0/health \
                            && echo "  ✓ Harbor reachable" \
                            || echo "  ⚠ Harbor may not be reachable"
                    '''

                    withCredentials([usernamePassword(
                            credentialsId: 'jenkin-cred',
                            usernameVariable: 'HARBOR_USER',
                            passwordVariable: 'HARBOR_PASS')]) {

                        sh 'echo $HARBOR_PASS | docker login -u $HARBOR_USER --password-stdin ${HARBOR_REGISTRY}'

                        getBuildServices().each { svc ->
                            sh """
                                if docker image inspect ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} >/dev/null 2>&1; then
                                    docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag}
                                    docker push ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest
                                    echo "  ✓ ${svc} pushed"
                                else
                                    echo "  ⚠ Image not found for ${svc}, skipping push"
                                fi
                            """
                        }

                        sh 'docker logout || true'
                    }
                }
            }
        }

        // ── NEW: Cleanup local Docker images ──────────────────────────────────
        stage('Cleanup Local Images') {
            when {
                allOf {
                    expression { params.PUSH_IMAGES == true }
                    expression { params.CLEANUP_LOCAL == true }
                }
            }
            steps {
                script {
                    echo "✓ Removing local images (tag: ${imageTag})..."
                    getBuildServices().each { svc ->
                        sh """
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:${imageTag} || true
                            docker rmi ${params.HARBOR_REGISTRY}/${HARBOR_PROJECT}/${svc}:latest       || true
                        """
                    }
                    // Remove dangling layers left over from multi-stage builds
                    sh 'docker image prune -f'
                    echo "  ✓ Local cleanup done"
                }
            }
        }

        // ── NEW: Cleanup old tags in Harbor ───────────────────────────────────
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
                    echo "✓ Cleaning up Harbor — keeping ${keepN} most recent tags per service..."

                    withCredentials([usernamePassword(
                            credentialsId: 'jenkin-cred',
                            usernameVariable: 'HARBOR_USER',
                            passwordVariable: 'HARBOR_PASS')]) {

                        getBuildServices().each { svc ->
                            cleanupHarborOldTags(svc, keepN)
                        }
                    }
                    echo "  ✓ Harbor cleanup done"
                }
            }
        }
    }

    post {
        always  { sh 'docker logout || true' }
        success { echo '✓ Pipeline succeeded!' }
        failure { echo '✗ Pipeline failed!'   }
    }
}

// ==================== Helper Functions ====================

def getServiceList() {
    return ['adservice', 'cartservice', 'checkoutservice', 'currencyservice',
            'emailservice', 'frontend', 'paymentservice', 'productcatalogservice',
            'recommendationservice', 'shippingservice', 'shoppingassistantservice']
}

def getBuildServices() {
    return (params.BUILD_TARGET == 'all') ? getServiceList() : [params.BUILD_TARGET]
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
            find "${serviceDir}" -name 'Dockerfile' -type f | sort | head -1
        """,
        returnStdout: true
    ).trim()

    if (!path) {
        error "✗ No Dockerfile found anywhere under ${serviceDir} — aborting."
    }

    return path
}

// ── NEW helper: delete tags older than the N most recent in Harbor ────────────
//
// Logic:
//   1. Fetch all tags for the repository via Harbor API v2
//   2. Sort by push_time descending (newest first)
//   3. Skip the first keepN tags + always skip "latest"
//   4. DELETE the rest via the artifact digest — safer than tag name deletion
//      because one digest can carry multiple tags; deleting by digest removes all
//      of them at once without accidentally leaving orphaned layers.
//
def cleanupHarborOldTags(String service, int keepN) {
    // HARBOR_USER / HARBOR_PASS injected by the caller's withCredentials block
    sh """
        set -euo pipefail

        REGISTRY="${params.HARBOR_REGISTRY}"
        PROJECT="${HARBOR_PROJECT}"
        SVC="${service}"
        KEEP=${keepN}

        API="http://\${REGISTRY}/api/v2.0/projects/\${PROJECT}/repositories/\${SVC}/artifacts"

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
