
pipeline {
    agent any

    stages {
        stage('Checkout GitHub') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/charltonmc2024/ecs-terraform-cicd.git'
            }
        }

        stage('Verify Checkout') {
            steps {
                sh '''
                    echo "=== Git Repository ==="
                    git remote -v

                    echo "=== Current Commit ==="
                    git rev-parse --short=7 HEAD

                    echo "=== Repository Files ==="
                    ls -la
                '''
            }
        }

        stage('Build Next.js') {
            steps {
                dir('ecs-application') {
                    sh '''
                        set -eu

                        echo "=== Node.js Version ==="
                        node --version

                        echo "=== Installing Dependencies ==="
                        npm ci

                        echo "=== Building Next.js Application ==="
                        npm run build

                        echo "=== Next.js build successful ==="
                    '''
                }
            }
        }

        stage('Prepare Image Tag') {
            steps {
                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = "sha-${env.GIT_SHA}"
                }

                echo "Prepared image tag: ${env.IMAGE_TAG}"
            }
        }
        stage('Build Docker Image') {
            steps {
                dir('ecs-application') {
                    sh '''
                set -eu

                echo "=== Building Next.js Docker Image ==="

                IMAGE_NAME="erudition-nextjs:$IMAGE_TAG"

                docker build -t "$IMAGE_NAME" .

                echo "=== Docker image built successfully ==="
                docker image inspect "$IMAGE_NAME"
            '''
                }
            }
        }

        stage('Docker Smoke Test') {
            steps {
                dir('ecs-application') {
                    sh '''
                        set -eu

                        echo "=== Docker Smoke Test ==="

                        IMAGE_NAME="erudition-nextjs:$IMAGE_TAG"

                        # Unique container name for this Jenkins build
                        CONTAINER_NAME="erudition-test-$BUILD_NUMBER-$$"

                        # Ensure cleanup even when the test fails
                        trap 'docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true' EXIT

                        echo "Testing image: $IMAGE_NAME"

                        docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME"

                        echo "=== Waiting for Next.js to become ready ==="

                        MAX_ATTEMPTS=20
                        ATTEMPT=1

                        while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
                            if docker exec "$CONTAINER_NAME" node -e '
                            fetch("http://127.0.0.1:3000")
                            .then(response => {
                                console.log("HTTP status:", response.status);
                                if (!response.ok) process.exit(1);
                            })
                            .catch(() => process.exit(1));
                            '; then
                            echo "=== Docker smoke test passed ==="
                            exit 0
                            fi

                        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS failed. Retrying..."

                        sleep 3
                        ATTEMPT=$((ATTEMPT + 1))
                        done

                        echo "ERROR: Application failed smoke test."
                        docker logs --tail 100 "$CONTAINER_NAME"
                        exit 1
                    '''
                }
            }
        }

        stage('AWS Authentication') {
            steps {
                withEnv([
            'AWS_PROFILE=jenkins-rolesanywhere',
            'AWS_REGION=us-east-1',
            'AWS_CONFIG_FILE=/var/lib/jenkins/.aws/config'
        ]) {
                    sh '''
                set -eu

                echo "=== Verifying AWS Identity ==="
                aws sts get-caller-identity

                echo "=== AWS Authentication Successful ==="
            '''
                }
            }
        }

        stage('Push Docker Image to ECR') {
            steps {
                withEnv([
            'AWS_PROFILE=jenkins-rolesanywhere',
            'AWS_REGION=us-east-1',
            'AWS_CONFIG_FILE=/var/lib/jenkins/.aws/config'
        ]) {
                    sh '''
                set -eu

                echo "=== Preparing temporary Docker credentials ==="

                export DOCKER_CONFIG="$(mktemp -d)"
                chmod 700 "$DOCKER_CONFIG"
                trap 'rm -rf "$DOCKER_CONFIG"' EXIT

                echo "=== Logging in to Amazon ECR ==="

                ECR_REGISTRY="691778449106.dkr.ecr.us-east-1.amazonaws.com"
                ECR_REPOSITORY="eruditiontx-app-ecs-dev-app"

                aws ecr get-login-password --region "$AWS_REGION" |
                    docker login --username AWS --password-stdin "$ECR_REGISTRY"

                echo "=== Tagging Docker Image ==="

                LOCAL_IMAGE="erudition-nextjs:$IMAGE_TAG"
                ECR_IMAGE="$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

                docker image inspect "$LOCAL_IMAGE" >/dev/null
                docker tag "$LOCAL_IMAGE" "$ECR_IMAGE"

                echo "=== Pushing Image to ECR ==="
                docker push "$ECR_IMAGE"

                echo "=== ECR push successful ==="
            '''
                }
            }
        }
    }
}
