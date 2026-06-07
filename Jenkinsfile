def imageTag = ''
def servicesToProcess = [] 

pipeline {
    agent any

    environment {
        DOCKER_BUILDKIT     = '1'
        BUILDKIT_PROGRESS   = 'plain'
        HARBOR_PROJECT      = 'sample-microservice'
        DOTNET_ROOT         = '/root/.dotnet'
        PATH                = "/root/.dotnet:/root/.dotnet/tools:${env.PATH}"
    }

    parameters {
        choice(
            name: 'BUILD_TARGET',
            choices: ['auto', 'all', 'adservice', 'cartservice', 'checkoutservice', 'currencyservice',
                      'emailservice', 'frontend', 'paymentservice', 'productcatalogservice',
                      'recommendationservice', 'shippingservice', 'shoppingassistantservice'],
            description: 'Select which service(s) to build. "auto" uses Git diff.'
        )
        booleanParam(name: 'PUSH_IMAGES',   defaultValue: true,  description: 'Push Docker images to Harbor?')
        booleanParam(name: 'RUN_SONAR',     defaultValue: true,  description: 'Run SonarQube Analysis & Quality Gate?')
        booleanParam(name: 'UPDATE_GITOPS', defaultValue: true,  description: 'Update tags in GitOps repo?')
        booleanParam(name: 'CLEANUP_LOCAL', defaultValue: true,  description: 'Remove local Docker images after push?')
        string(name: 'KEEP_TAGS',           defaultValue: '5',   description: 'Number of recent tags to keep in Harbor (0 = skip)')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Prepare Target & Tag') {
            steps {
                script {
                    def gitShort = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    imageTag = "${BUILD_NUMBER}-${gitShort}"
                    echo "✓ Target Image tag: ${imageTag}"

                    // Tối ưu: Chỉ build những service có code thay đổi (nếu chọn 'auto')
                    servicesToProcess = getBuildServices()
                    if (servicesToProcess.isEmpty()) {
                        currentBuild.result = 'SUCCESS'
                        echo "✓ Không có thay đổi nào trong thư mục services. Bỏ qua Build."
                    } else {
                        echo "✓ Các services sẽ được xử lý: ${servicesToProcess.join(', ')}"
                    }
                }
            }
        }

        stage('Parallel: Sonar, Build & Push') {
            when { expression { !servicesToProcess.isEmpty() } }
            steps {
                script {
                    stash name: 'source', includes: 'src/**'
                    def parallelStages = [:]

                    // Gọi tất cả Credentials cần thiết (Harbor Account + Secret Registry URL)
                    withCredentials([
                        usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS'),
                        string(credentialsId: 'HARBOR_REGISTRY_URL', variable: 'SECRET_REGISTRY_URL'),
                        string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')
                    ]) {
                        servicesToProcess.each { service ->
                            def svc = service 

                            parallelStages[svc] = {
                                node {
                                    unstash 'source'
                                    def dockerfilePath = resolveDockerfilePath(svc)
                                    def buildContext   = (svc == 'cartservice') ? 'src/cartservice/src' : "src/${svc}"

                                    // --- 1. SONARQUBE CHẶN LỖI (FAIL-FAST) ---
                                    if (params.RUN_SONAR) {
                                        stage("${svc}: SonarQube") {
                                            withSonarQubeEnv('sonarqube') {
                                                // Xử lý riêng biệt cho .NET (cartservice) và các ngôn ngữ khác
                                                if (svc == 'cartservice') {
                                                    sh """
                                                        cd src/${svc}
                                                        dotnet tool install --global dotnet-sonarscanner || true
                                                        dotnet restore
                                                        dotnet sonarscanner begin /k:${svc} /d:sonar.host.url=\$SONAR_HOST_URL /d:sonar.login=\$SONAR_TOKEN /d:sonar.exclusions="**/Dockerfile*"
                                                        dotnet build
                                                        dotnet sonarscanner end /d:sonar.login=\$SONAR_TOKEN
                                                    """
                                                } else {
                                                    def scannerHome = tool 'sonar-scanner'
                                                    sh """
                                                        ${scannerHome}/bin/sonar-scanner \
                                                            -Dsonar.projectKey=${svc} \
                                                            -Dsonar.sources=${buildContext} \
                                                            -Dsonar.login=\$SONAR_TOKEN
                                                    """
                                                }
                                            }
                                            timeout(time: 5, unit: 'MINUTES') {
                                                def qg = waitForQualityGate()
                                                if (qg.status != 'OK') {
                                                    error "✗ CHẶN LẠI: ${svc} trượt SonarQube (Trạng thái: ${qg.status}). Hủy Build!"
                                                }
                                            }
                                        }
                                    }

                                    // --- 2. BUILD DOCKER (DÙNG CACHE) ---
                                    stage("${svc}: Build Image") {
                                        sh """
                                            docker build \
                                                --build-arg BUILDKIT_INLINE_CACHE=1 \
                                                --cache-from \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:latest \
                                                -f ${dockerfilePath} \
                                                -t \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                                -t \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:latest \
                                                ${buildContext}
                                        """
                                    }

                                    // --- 3. PUSH LUÔN SAU KHI BUILD ---
                                    if (params.PUSH_IMAGES) {
                                        stage("${svc}: Push Image") {
                                            sh """
                                                echo "\$HARBOR_PASS" | docker login \${SECRET_REGISTRY_URL} -u "\$HARBOR_USER" --password-stdin
                                                docker push \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:${imageTag}
                                                docker push \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:latest
                                            """
                                        }
                                    }
                                }
                            }
                        }
                        parallel parallelStages
                    }
                }
            }
        }

        // --- 4. GITOPS UPDATE (HELM VALUES.YAML) ---
        stage('Update GitOps Repo (Helm)') {
            when {
                allOf {
                    expression { !servicesToProcess.isEmpty() }
                    expression { params.UPDATE_GITOPS }
                    expression { params.PUSH_IMAGES }
                    branch 'main'
                }
            }
            steps {
                script {
                    echo "✓ Đang cập nhật Helm values.yaml trên GitOps repo..."
                    
                    withCredentials([
                        usernamePassword(credentialsId: 'git-credentials-id', usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN'),
                        string(credentialsId: 'HARBOR_REGISTRY_URL', variable: 'SECRET_REGISTRY_URL')
                    ]) {
                        sh """
                            rm -rf gitops
                            git clone https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/nt114thenttthytlu/gitops-for-microservices-demo.git gitops
                            cd gitops

                            git config user.email "jenkins-bot@yourdomain.com"
                            git config user.name "Jenkins CI Bot"

                            for svc in ${servicesToProcess.join(' ')}; do
                                VALUES_FILE="\${svc}/values.yaml"

                                if [ -f "\$VALUES_FILE" ]; then
                                    echo "  Cập nhật \${VALUES_FILE}..."
                                    
                                    # Cập nhật repository bằng Secret URL và cập nhật Tag
                                    sed -i "s|repository:.*|repository: \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/\${svc}|g" \$VALUES_FILE
                                    sed -i "s|tag:.*|tag: ${imageTag}|g" \$VALUES_FILE
                                    
                                    echo "  ✓ Đã cập nhật xong \${svc}"
                                else
                                    echo "  ⚠ Bỏ qua \${svc} - Không tìm thấy file values.yaml"
                                fi
                            done

                            git add .
                            git diff --cached --quiet || git commit -m "ci: auto-update helm values for images to tag ${imageTag} [ci skip]"
                            git push origin main
                        """
                    }
                }
            }
        }

        stage('Cleanup Local & Harbor') {
            when { expression { !servicesToProcess.isEmpty() && params.PUSH_IMAGES } }
            steps {
                script {
                    withCredentials([
                        usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS'),
                        string(credentialsId: 'HARBOR_REGISTRY_URL', variable: 'SECRET_REGISTRY_URL')
                    ]) {
                        // Dọn Local
                        if (params.CLEANUP_LOCAL) {
                            servicesToProcess.each { svc ->
                                sh """
                                    docker rmi \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:${imageTag} || true
                                    docker rmi \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:latest || true
                                """
                            }
                            sh 'docker image prune -f'
                        }
                        
                        // Dọn Harbor
                        def keepN = params.KEEP_TAGS.toInteger()
                        if (keepN > 0) {
                            servicesToProcess.each { svc ->
                                cleanupHarborOldTags(svc, keepN)
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            withCredentials([string(credentialsId: 'HARBOR_REGISTRY_URL', variable: 'SECRET_REGISTRY_URL')]) {
                sh "docker logout \${SECRET_REGISTRY_URL} || true"
            }
        }
        success { echo '✓ Pipeline hoàn thành xuất sắc!' }
        failure { echo '✗ Pipeline thất bại! Vui lòng kiểm tra lại log.' }
    }
}

// ==================== Helper Functions ====================

def getServiceList() {
    return ['adservice','cartservice','checkoutservice','currencyservice',
            'emailservice','frontend','paymentservice',
            'productcatalogservice','recommendationservice',
            'shippingservice','shoppingassistantservice']
}

def getBuildServices() {
    if (params.BUILD_TARGET == 'all') return getServiceList()
    if (params.BUILD_TARGET != 'auto') return [params.BUILD_TARGET]

    def changedServices = []
    try {
        def prevCommit = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT
        def diffCmd = prevCommit ? "git diff --name-only ${prevCommit} ${env.GIT_COMMIT}" : "git show --name-only --format="
        
        def changedFiles = sh(script: diffCmd, returnStdout: true).trim().split('\n')
        def allServices = getServiceList()
        
        for (file in changedFiles) {
            for (svc in allServices) {
                if (file.startsWith("src/${svc}/") && !changedServices.contains(svc)) {
                    changedServices.add(svc)
                }
            }
        }
    } catch (Exception e) {
        echo "⚠ Không thể xác định file thay đổi. Build ALL."
        return getServiceList()
    }
    return changedServices
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

    if (!path) error "No Dockerfile found for ${service}"
    return path
}

def cleanupHarborOldTags(String service, int keepN) {
    sh """
        set -euo pipefail
        API="https://\${SECRET_REGISTRY_URL}/api/v2.0/projects/${HARBOR_PROJECT}/repositories/${service}/artifacts"
        ARTIFACTS=\$(curl -sf -k -u "\${HARBOR_USER}:\${HARBOR_PASS}" "\${API}?page_size=100&page=1&with_tag=true&sort=-push_time" || echo "")

        if [ -z "\${ARTIFACTS}" ]; then exit 0; fi

        DIGESTS_TO_DELETE=\$(echo "\${ARTIFACTS}" | python3 -c "
import sys, json
try:
    data, kept, result = json.load(sys.stdin), 0, []
    for artifact in data:
        tags = [t['name'] for t in (artifact.get('tags') or [])]
        if 'latest' in tags: continue
        if kept < int('\${KEEP}'):
            kept += 1; continue
        result.append(artifact['digest'])
    print('\\n'.join(result))
except: pass
")
        echo "\${DIGESTS_TO_DELETE}" | while IFS= read -r digest; do
            if [ -n "\$digest" ]; then
                curl -sf -k -X DELETE -u "\${HARBOR_USER}:\${HARBOR_PASS}" "\${API}/\${digest}" || true
            fi
        done
    """
}