/**
 * Production CI/CD Pipeline for Portfolio Website
 *
 * This Jenkinsfile defines a complete pipeline for building, testing,
 * and deploying the portfolio website to a Kubernetes cluster.
 *
 * Prerequisites:
 *   - Jenkins credentials: 'docker-registry-credentials' (Docker registry auth)
 *   - Jenkins credentials: 'kubeconfig-credentials' (Kubernetes config file)
 *   - Docker and kubectl installed on Jenkins agents
 *   - Nginx Ingress Controller installed on the K8s cluster
 */

pipeline {
    agent any

    environment {
        // Docker configuration
        DOCKER_REGISTRY     = credentials('docker-registry-url')
        DOCKER_CREDENTIALS  = credentials('docker-registry-credentials')
        IMAGE_NAME          = 'portfolio-website'
        IMAGE_TAG           = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'latest'}"

        // Kubernetes configuration
        KUBE_NAMESPACE      = 'portfolio'
        KUBECONFIG_CRED     = credentials('kubeconfig-credentials')

        // Application configuration
        APP_PORT            = '8080'
    }

    options {
        // Discard old builds to save disk space
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Timeout for the entire pipeline
        timeout(time: 30, unit: 'MINUTES')
        // Do not allow concurrent builds
        disableConcurrentBuilds()
        // Add timestamps to console output
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                echo '=== Checking out source code ==='
                checkout scm
                sh 'echo "Build: ${BUILD_NUMBER}, Commit: ${GIT_COMMIT}"'
            }
        }

        stage('Validate') {
            steps {
                echo '=== Validating project files ==='
                sh '''
                    echo "Checking required files..."
                    test -f index.html    && echo "[OK] index.html"    || (echo "[FAIL] index.html missing" && exit 1)
                    test -f style.css     && echo "[OK] style.css"     || (echo "[FAIL] style.css missing" && exit 1)
                    test -f Dockerfile    && echo "[OK] Dockerfile"    || (echo "[FAIL] Dockerfile missing" && exit 1)
                    test -f nginx/nginx.conf   && echo "[OK] nginx.conf"   || (echo "[FAIL] nginx.conf missing" && exit 1)
                    test -f nginx/default.conf && echo "[OK] default.conf" || (echo "[FAIL] default.conf missing" && exit 1)
                    echo "All required files present."
                '''
            }
        }

        stage('Lint HTML') {
            steps {
                echo '=== Linting HTML files ==='
                sh '''
                    # Basic HTML validation
                    if command -v htmlhint > /dev/null 2>&1; then
                        htmlhint index.html || true
                    else
                        echo "htmlhint not installed, performing basic checks..."
                        # Check for DOCTYPE
                        head -1 index.html | grep -qi "doctype" && echo "[OK] DOCTYPE found" || echo "[WARN] DOCTYPE not found"
                        # Check for closing tags
                        grep -c "</html>" index.html > /dev/null && echo "[OK] Closing </html> tag found" || echo "[WARN] No closing </html> tag"
                    fi
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                echo '=== Building Docker image ==='
                sh '''
                    docker build \
                        --no-cache \
                        --tag ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} \
                        --tag ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest \
                        --label "build.number=${BUILD_NUMBER}" \
                        --label "build.commit=${GIT_COMMIT}" \
                        --label "build.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                        .
                '''
            }
        }

        stage('Test Docker Image') {
            steps {
                echo '=== Testing Docker image ==='
                sh '''
                    # Run container in background for testing
                    CONTAINER_ID=$(docker run -d -p ${APP_PORT}:8080 ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG})

                    # Wait for container to be ready
                    echo "Waiting for container to start..."
                    sleep 5

                    # Test health endpoint
                    echo "Testing health endpoint..."
                    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT}/healthz)
                    if [ "$HTTP_STATUS" = "200" ]; then
                        echo "[OK] Health check passed (HTTP ${HTTP_STATUS})"
                    else
                        echo "[FAIL] Health check failed (HTTP ${HTTP_STATUS})"
                        docker logs ${CONTAINER_ID}
                        docker stop ${CONTAINER_ID}
                        docker rm ${CONTAINER_ID}
                        exit 1
                    fi

                    # Test main page
                    echo "Testing main page..."
                    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT}/)
                    if [ "$HTTP_STATUS" = "200" ]; then
                        echo "[OK] Main page accessible (HTTP ${HTTP_STATUS})"
                    else
                        echo "[FAIL] Main page not accessible (HTTP ${HTTP_STATUS})"
                        docker logs ${CONTAINER_ID}
                        docker stop ${CONTAINER_ID}
                        docker rm ${CONTAINER_ID}
                        exit 1
                    fi

                    # Test readiness endpoint
                    echo "Testing readiness endpoint..."
                    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT}/readyz)
                    if [ "$HTTP_STATUS" = "200" ]; then
                        echo "[OK] Readiness check passed (HTTP ${HTTP_STATUS})"
                    else
                        echo "[FAIL] Readiness check failed (HTTP ${HTTP_STATUS})"
                        docker logs ${CONTAINER_ID}
                        docker stop ${CONTAINER_ID}
                        docker rm ${CONTAINER_ID}
                        exit 1
                    fi

                    # Test static assets
                    echo "Testing static assets..."
                    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT}/style.css)
                    if [ "$HTTP_STATUS" = "200" ]; then
                        echo "[OK] CSS accessible (HTTP ${HTTP_STATUS})"
                    else
                        echo "[WARN] CSS not accessible (HTTP ${HTTP_STATUS})"
                    fi

                    # Cleanup
                    docker stop ${CONTAINER_ID}
                    docker rm ${CONTAINER_ID}
                    echo "All tests passed!"
                '''
            }
        }

        stage('Security Scan') {
            steps {
                echo '=== Running security scan ==='
                sh '''
                    # Run Trivy scan if available
                    if command -v trivy > /dev/null 2>&1; then
                        trivy image --severity HIGH,CRITICAL --exit-code 0 ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    else
                        echo "Trivy not installed, skipping security scan."
                        echo "Consider installing Trivy for container vulnerability scanning."
                    fi
                '''
            }
        }

        stage('Push Docker Image') {
            steps {
                echo '=== Pushing Docker image to registry ==='
                sh '''
                    echo "${DOCKER_CREDENTIALS_PSW}" | docker login ${DOCKER_REGISTRY} -u "${DOCKER_CREDENTIALS_USR}" --password-stdin
                    docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo '=== Deploying to Kubernetes ==='
                withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG')]) {
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}

                        # Apply namespace first
                        kubectl apply -f k8s/namespace.yaml

                        # Apply ConfigMap
                        kubectl apply -f k8s/configmap.yaml

                        # Apply Network Policy
                        kubectl apply -f k8s/network-policy.yaml

                        # Apply Pod Disruption Budget
                        kubectl apply -f k8s/pod-disruption-budget.yaml

                        # Substitute image variables and apply deployment
                        sed -e "s|\${DOCKER_REGISTRY}|${DOCKER_REGISTRY}|g" \
                            -e "s|\${IMAGE_TAG}|${IMAGE_TAG}|g" \
                            k8s/deployment.yaml | kubectl apply -f -

                        # Apply Service
                        kubectl apply -f k8s/service.yaml

                        # Apply Ingress
                        kubectl apply -f k8s/ingress.yaml

                        # Apply HPA
                        kubectl apply -f k8s/hpa.yaml

                        # Wait for deployment rollout
                        echo "Waiting for deployment to complete..."
                        kubectl rollout status deployment/portfolio-website \
                            -n ${KUBE_NAMESPACE} \
                            --timeout=120s

                        # Show deployment status
                        echo "=== Deployment Status ==="
                        kubectl get pods -n ${KUBE_NAMESPACE} -l app=portfolio-website
                        kubectl get svc -n ${KUBE_NAMESPACE}
                        kubectl get ingress -n ${KUBE_NAMESPACE}
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                echo '=== Running post-deployment smoke tests ==='
                withCredentials([file(credentialsId: 'kubeconfig-credentials', variable: 'KUBECONFIG')]) {
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}

                        # Get pod name
                        POD_NAME=$(kubectl get pods -n ${KUBE_NAMESPACE} -l app=portfolio-website -o jsonpath='{.items[0].metadata.name}')

                        # Port-forward and test
                        kubectl port-forward -n ${KUBE_NAMESPACE} ${POD_NAME} 9090:8080 &
                        PF_PID=$!
                        sleep 5

                        # Test the health endpoint via port-forward
                        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/healthz)
                        if [ "$HTTP_STATUS" = "200" ]; then
                            echo "[OK] Post-deployment health check passed"
                        else
                            echo "[WARN] Post-deployment health check returned HTTP ${HTTP_STATUS}"
                        fi

                        # Cleanup port-forward
                        kill ${PF_PID} 2>/dev/null || true

                        echo "Smoke tests completed."
                    '''
                }
            }
        }
    }

    post {
        success {
            echo """
            =========================================
            Pipeline completed successfully!
            Image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
            Namespace: ${KUBE_NAMESPACE}
            =========================================
            """
        }
        failure {
            echo """
            =========================================
            Pipeline FAILED!
            Build: ${BUILD_NUMBER}
            Check the logs above for details.
            =========================================
            """
        }
        always {
            // Clean up Docker images from the build agent
            sh '''
                docker rmi ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} || true
                docker rmi ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest || true
                docker logout ${DOCKER_REGISTRY} || true
            '''
        }
    }
}
