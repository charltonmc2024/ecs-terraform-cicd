
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

                        docker build --provenance=false -t "$IMAGE_NAME" .

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
                        set +x

                        echo "=== Preparing temporary Docker credentials ==="

                        export DOCKER_CONFIG="$(mktemp -d)"
                        chmod 700 "$DOCKER_CONFIG"
                        trap 'rm -rf "$DOCKER_CONFIG"' EXIT

                        ECR_REGISTRY="691778449106.dkr.ecr.us-east-1.amazonaws.com"
                        ECR_REPOSITORY="eruditiontx-app-ecs-dev-app"

                        echo "=== Checking whether image tag exists in ECR ==="

                        IMAGE_LOOKUP=$(aws ecr batch-get-image \
                            --repository-name "$ECR_REPOSITORY" \
                            --image-ids imageTag="$IMAGE_TAG" \
                            --region "$AWS_REGION" \
                            --output json)

IMAGE_STATUS=$(printf '%s' "$IMAGE_LOOKUP" | python3 -c '
import json, sys
result = json.load(sys.stdin)

if result.get("images"):
    print("EXISTS")
elif (
    len(result.get("failures", [])) == 1
    and result["failures"][0].get("failureCode") == "ImageNotFound"
):
    print("MISSING")
else:
    print("ERROR")
')

                        echo "ECR image status: $IMAGE_STATUS"

                        if [ "$IMAGE_STATUS" = "ERROR" ]; then
                            echo "ERROR: Unexpected ECR image lookup response"
                            exit 1
                        fi


                        LOCAL_IMAGE="erudition-nextjs:$IMAGE_TAG"
                        ECR_IMAGE="$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

                        if [ "$IMAGE_STATUS" = "EXISTS" ]; then
                            echo "=== Image tag already exists in ECR ==="
                            echo "Skipping duplicate push: $ECR_IMAGE"

                        elif [ "$IMAGE_STATUS" = "MISSING" ]; then
                            echo "=== Logging in to Amazon ECR ==="

                            ECR_PASSWORD=$(aws ecr get-login-password --region "$AWS_REGION")

                            if [ -z "$ECR_PASSWORD" ]; then
                                echo "ERROR: AWS returned an empty ECR login password"
                                exit 1
                            fi

                            printf '%s' "$ECR_PASSWORD" |
                                docker login --username AWS --password-stdin "$ECR_REGISTRY"

                            unset ECR_PASSWORD

                            echo "=== Tagging Docker Image ==="

                            docker image inspect "$LOCAL_IMAGE" >/dev/null
                            docker tag "$LOCAL_IMAGE" "$ECR_IMAGE"

                            echo "=== Pushing new image to ECR ==="

                            PUSH_ATTEMPT=1
                            MAX_PUSH_ATTEMPTS=3

                            while ! docker push "$ECR_IMAGE"; do
                                echo "=== Checking ECR after failed push ==="

                                RETRY_LOOKUP=$(aws ecr batch-get-image \
                                    --repository-name "$ECR_REPOSITORY" \
                                    --image-ids imageTag="$IMAGE_TAG" \
                                    --region "$AWS_REGION" \
                                    --output json)

                                RETRY_STATUS=$(printf '%s' "$RETRY_LOOKUP" | python3 -c '
import json, sys
result = json.load(sys.stdin)

if result.get("images"):
    print("EXISTS")
elif (
    len(result.get("failures", [])) == 1
    and result["failures"][0].get("failureCode") == "ImageNotFound"
):
    print("MISSING")
else:
    print("ERROR")
')

                                if [ "$RETRY_STATUS" = "EXISTS" ]; then
                                    echo "ERROR: ECR tag exists after failed push; identity unverified"
                                    exit 1
                                elif [ "$RETRY_STATUS" != "MISSING" ]; then
                                    echo "ERROR: Unexpected ECR lookup result after failed push"
                                    exit 1
                                fi

                                if [ "$PUSH_ATTEMPT" -ge "$MAX_PUSH_ATTEMPTS" ]; then
                                    echo "ERROR: Docker push failed after $MAX_PUSH_ATTEMPTS attempts"
                                    exit 1
                                fi

                                echo "Docker push failed (attempt $PUSH_ATTEMPT). Retrying in 5 seconds..."
                                sleep 5
                                PUSH_ATTEMPT=$((PUSH_ATTEMPT + 1))
                            done

                            echo "=== ECR push successful ==="
                        else
                            echo "ERROR: Unexpected image status: $IMAGE_STATUS"
                            exit 1
                        fi

                        echo "=== Verifying image digest in ECR ==="

                        IMAGE_DIGEST=$(aws ecr describe-images \
                            --repository-name "$ECR_REPOSITORY" \
                            --image-ids imageTag="$IMAGE_TAG" \
                            --region "$AWS_REGION" \
                            --query 'imageDetails[0].imageDigest' \
                            --output text)

                        if ! printf '%s' "$IMAGE_DIGEST" |
                            grep -Eq '^sha256:[0-9a-fA-F]{64}$'; then
                            echo "ERROR: ECR returned an invalid SHA-256 digest"
                            exit 1
                        fi

                        echo "Verified ECR image digest: $IMAGE_DIGEST"
                    '''
                }
            }
        }

        stage('Prepare Terraform Image Tag') {
            steps {
                script {
                    if (!(env.IMAGE_TAG ==~ /^sha-[0-9a-fA-F]{7}$/)) {
                        error("Invalid Docker image tag: ${env.IMAGE_TAG}")
                    }

                    env.TF_VAR_image_tag = env.IMAGE_TAG

                    echo "=== Terraform Image Tag Prepared ==="
                    echo "IMAGE_TAG: ${env.IMAGE_TAG}"
                    echo "TF_VAR_image_tag: ${env.TF_VAR_image_tag}"
                }
            }
        }

    }
}
