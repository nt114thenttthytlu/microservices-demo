def imageTag = ''
def servicesToProcess = [] 

pipeline {
    agent any

    environment {
        DOCKER_BUILDKIT     = '0'
        BUILDKIT_PROGRESS   = 'plain'
        HARBOR_PROJECT      = 'microservices-demo'
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
                    echo "Target Image tag: ${imageTag}"

                    // Tối ưu: Chỉ build những service có code thay đổi (nếu chọn 'auto')
                    servicesToProcess = getBuildServices()
                    if (servicesToProcess.isEmpty()) {
                        currentBuild.result = 'SUCCESS'
                        echo "Không có thay đổi nào trong thư mục services. Bỏ qua Build."
                    } else {
                        echo "Các services sẽ được xử lý: ${servicesToProcess.join(', ')}"
                    }
                }
            }
        }

        stage('Parallel: Sonar, Build & Push') {
            when { expression { !servicesToProcess.isEmpty() } }
            steps {
                script {
                    stash name: 'source', includes: 'src/**'

                    withCredentials([
                        usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS'),
                        string(credentialsId: 'HARBOR_REGISTRY_URL', variable: 'SECRET_REGISTRY_URL'),
                        string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')
                    ]) {
                        def batchSize = 3
                        
                        // Chia danh sách các dịch vụ thành từng nhóm (batch) để tránh quá tải tài nguyên node
                        servicesToProcess.collate(batchSize).each { batch ->
                            def batchStages = [:]
                            
                            batch.each { service ->
                                def svc = service
                                batchStages[svc] = {
                                    node {
                                        unstash 'source'
                                        def dockerfilePath = resolveDockerfilePath(svc)
                                        def buildContext   = (svc == 'cartservice') ? 'src/cartservice/src' : "src/${svc}"
    
                                        // --- 1. SONARQUBE CHẶN LỖI ---
                                        if (params.RUN_SONAR) {
                                            stage("${svc}: SonarQube") {
                                                withSonarQubeEnv('sonarqube') {
                                                    def scannerHome = tool 'sonar-scanner'
                                                    sh """
                                                        ${scannerHome}/bin/sonar-scanner \
                                                            -Dsonar.projectKey=${svc} \
                                                            -Dsonar.sources=${buildContext} \
                                                            -Dsonar.java.binaries=${buildContext} \
                                                            -Dsonar.host.url=\$SONAR_HOST_URL \
                                                            -Dsonar.token=\$SONAR_AUTH_TOKEN
                                                    """
                                                }
    
                                                timeout(time: 25, unit: 'MINUTES') {
                                                    def qg = waitForQualityGate()
                                                    if (qg.status != 'OK') {
                                                        error "✗ ${svc} fail SonarQube: ${qg.status}"
                                                    }
                                                }
                                            }
                                        }
    
                                        // --- 2. BUILD DOCKER ---
                                        stage("${svc}: Build Image") {
                                            sh """
                                                docker build \
                                                    -f ${dockerfilePath} \
                                                    -t \${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:${imageTag} \
                                                    -t \top\${SECRET_REGISTRY_URL}/${HARBOR_PROJECT}/${svc}:latest \
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
                            // Chạy song song các service thuộc batch hiện tại
                            parallel batchStages
                        } 
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
                    echo "Đang cập nhật Helm values.yaml trên GitOps repo..."
                    
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
        success { echo '✓ Pipeline hoàn thành' }
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

    def allServices = getServiceList()

    try {
        sh 'git fetch origin +refs/heads/*:refs/remotes/origin/*'

        def diffCmd = ""

        // Kiểm tra nếu đang chạy trên nhánh main (dành cho Multibranch Pipeline)
        if (env.BRANCH_NAME == 'main' || env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main') {
            // Lấy danh sách các file bị thay đổi trong chính commit vừa được push/merge
            diffCmd = "git diff-tree --no-commit-id --name-only -r HEAD"
        } else {
            // Nếu đang ở nhánh khác (Feature, Hotfix...), so sánh nhánh hiện tại với main
            diffCmd = "git diff --name-only origin/main...HEAD"
        }

        def changedServices = []

        changedFiles.split('\n').each { file ->
            allServices.each { svc ->
                if (file.startsWith("src/${svc}/") && !changedServices.contains(svc)) {
                    changedServices.add(svc)
                }
            }
        }

        if (changedServices.isEmpty()) {
            echo "⚠ Không detect service change -> fallback ALL"
            return allServices
        }

        return changedServices

    } catch (Exception e) {
        echo "⚠ Git diff fail (${e.message}) -> BUILD ALL"
        return allServices
    }
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

        echo "🔍 Checking Harbor repo for ${service}..."

        # Lấy HTTP code riêng
        HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" -u "\${HARBOR_USER}:\${HARBOR_PASS}" "\${API}?page_size=1&with_tag=true")

        # Nếu repo chưa tồn tại (404) => bỏ qua cleanup
        if [ "\$HTTP_CODE" = "404" ]; then
            echo "✓ ${service} chưa có image trong Harbor (first build). Skip cleanup."
            exit 0
        fi

        # Nếu lỗi khác => cũng bỏ qua để không fail pipeline
        if [ "\$HTTP_CODE" != "200" ]; then
            echo "⚠ Không truy cập được Harbor API (${service}), HTTP=\$HTTP_CODE. Skip cleanup."
            exit 0
        fi

        JSON_BODY=\$(curl -s -k -u "\${HARBOR_USER}:\${HARBOR_PASS}" "\${API}?page_size=100&page=1&with_tag=true&sort=-push_time")

        ALL_DIGESTS=\$(echo "\$JSON_BODY" | grep -o '"digest":"[^"]*' | awk -F'"' '{print \$4}')

        TOTAL_IMAGES=\$(echo "\$ALL_DIGESTS" | wc -l)

        if [ -z "\$ALL_DIGESTS" ] || [ "\$TOTAL_IMAGES" -le ${keepN} ]; then
            echo "✓ Không cần cleanup (${service}) - total=\$TOTAL_IMAGES"
            exit 0
        fi

        DIGESTS_TO_DELETE=\$(echo "\$ALL_DIGESTS" | tail -n +\$(( ${keepN} + 1 )))

        for digest in \$DIGESTS_TO_DELETE; do
            echo "🗑 Deleting old image: \$digest"
            curl -sf -k -X DELETE -u "\${HARBOR_USER}:\${HARBOR_PASS}" "\${API}/\${digest}" || true
        done

        echo "✓ Cleanup done for ${service}"
    """
}
