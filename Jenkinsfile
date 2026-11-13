
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
        stage('Build Docker Image') {
            steps {
                dir('ecs-application') {
                    sh '''
                set -eu

                echo "=== Building Next.js Docker Image ==="

                GIT_SHA=$(git rev-parse --short=7 HEAD)
                IMAGE_NAME="erudition-nextjs:$GIT_SHA"

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

                GIT_SHA=$(git rev-parse --short=7 HEAD)
                IMAGE_NAME="erudition-nextjs:$GIT_SHA"
                CONTAINER_NAME="erudition-pipeline-test"

                # Remove any leftover test container
                docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

                # Always clean up when the script exits
                trap 'docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true' EXIT

                echo "Testing image: $IMAGE_NAME"

                # Start the container
                docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME"

                # Give Next.js time to start
                sleep 10

                # Verify the application responds successfully
                docker exec "$CONTAINER_NAME" node -e '
                    fetch("http://127.0.0.1:3000")
                        .then(response => {
                            console.log("HTTP status:", response.status);
                            if (!response.ok) process.exit(1);
                        })
                        .catch(error => {
                            console.error(error);
                            process.exit(1);
                        });
                '

                echo "=== Docker smoke test passed ==="
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

                GIT_SHA=$(git rev-parse --short=7 HEAD)
                LOCAL_IMAGE="erudition-nextjs:$GIT_SHA"
                ECR_IMAGE="$ECR_REGISTRY/$ECR_REPOSITORY:sha-$GIT_SHA"

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
