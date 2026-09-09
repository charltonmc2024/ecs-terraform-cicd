# Project Overview

## 1. **Online Tutoring Platform**

A cloud-native online tutoring application that connects students with tutors, allowing students to browse tutors, view classes, schedule tutoring sessions, and manage their learning activities.

---

## 2. Project Goal

The goal of this project is to build a scalable, secure, and cost-conscious online tutoring platform using AWS managed services.

The application will use:

* **Amazon S3** — React frontend hosting
* **Amazon CloudFront** — CDN and HTTPS frontend delivery
* **AWS Certificate Manager (ACM)** — TLS/SSL certificates
* **Amazon Route 53** — DNS
* **Application Load Balancer (ALB)** — backend traffic routing
* **Amazon ECS with Fargate** — backend API containers
* **Amazon ECR** — Docker container image registry
* **Amazon DynamoDB** — application database
* **Amazon VPC** — network isolation
* **AWS IAM** — access control
* **Terraform** — infrastructure as code
* **AWS CodePipeline and CodeBuild** — CI/CD

---

## 3. High-Level Architecture

```text

                              USERS
                                │
                                │ HTTPS
                                ▼
                         ┌──────────────┐
                         │   Route 53   │
                         │     DNS      │
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │  CloudFront  │
                         │     CDN      │
                         └──────┬───────┘
                                │
                         ┌──────┴──────┐
                         │             │
                      /* │          /api/*
                         │             │
                         ▼             ▼
                  ┌─────────────┐ ┌─────────────┐
                  │     S3      │ │     ALB     │
                  │             │ │ Load Balancer│
                  │ React App   │ └──────┬──────┘
                  └─────────────┘        │
                                         │
                                         ▼
                                  ┌──────────────┐
                                  │ ECS Fargate  │
                                  │              │
                                  │ Tutoring API │
                                  └──────┬───────┘
                                         │
                                         ▼
                                  ┌──────────────┐
                                  │   DynamoDB   │
                                  │              │
                                  │ Students     │
                                  │ Tutors       │
                                  │ Courses      │
                                  │ Classes      │
                                  │ Bookings     │
                                  │ Messages     │
                                  └──────────────┘


              ┌───────────────────────┐
              │         ACM           │
              │   TLS/SSL Certificate │
              └───────────┬───────────┘
                          │
             ┌────────────┴────────────┐
             │                         │
             ▼                         ▼
        CloudFront                    ALB
        Certificate              HTTPS Listener
        (us-east-1)              Certificate


              ┌───────────────────────┐
              │         ECR           │
              │  Backend Docker Image │
              └───────────┬───────────┘
                          │
                          ▼
                    ECS Fargate


              ┌───────────────────────┐
              │       Terraform       │
              │                       │
              │ VPC • S3 • CloudFront │
              │ ACM • Route 53 • ALB  │
              │ ECS • ECR • DynamoDB  │
              │ IAM • Security Groups │
              └───────────────────────┘
```

---

## 4. HTTPS and ACM

AWS Certificate Manager provides TLS/SSL certificates for the application.

The application should use HTTPS for all public traffic.

```text
User
 │
 │ HTTPS
 ▼
Route 53
 │
 ▼
CloudFront
 │
 │ ACM Certificate
 ▼
S3 / ALB
```

## CloudFront Certificate

The ACM certificate used by CloudFront **must be created in `us-east-1`**.

Example:

```text
AWS Region: us-east-1

ACM
└── *.eruditionsys.com
```

The certificate can cover:

```text
eruditionsys.com
eruditionsys.com
```

or use an appropriate wildcard certificate.

---

## ALB Certificate

If CloudFront connects to the ALB using HTTPS, the ALB also requires an ACM certificate.

The ALB certificate should be created in the **same AWS region as the ALB**.

For example:

```text
us-east-1
│
├── CloudFront
│    └── ACM Certificate
│
├── ALB
│    └── ACM Certificate
│
├── ECS
├── ECR
└── DynamoDB
```

If the application infrastructure is deployed in another region, the ALB certificate belongs in that region while the CloudFront certificate remains in `us-east-1`.

---

## 5. DNS and HTTPS Flow

The complete request flow is:

```text
                       User
                         │
                         │ HTTPS
                         ▼
                  ┌─────────────┐
                  │  Route 53   │
                  │     DNS     │
                  └──────┬──────┘
                         │
                         ▼
                  ┌─────────────┐
                  │ CloudFront  │
                  │             │
                  │ ACM Cert    │
                  └──────┬──────┘
                         │
              ┌──────────┴──────────┐
              │                     │
              ▼                     ▼
             S3                    ALB
       React Frontend          HTTPS Listener
                                    │
                              ACM Certificate
                                    │
                                    ▼
                              ECS Fargate
                                    │
                                    ▼
                                DynamoDB
```

---

## 6. Frontend Architecture

The frontend is a React application.

```text
React
  │
  │ Build
  ▼
S3
  │
  ▼
CloudFront
  │
  │ HTTPS
  ▼
User
```

The S3 bucket should remain private.

CloudFront should access the S3 bucket through an appropriate origin access mechanism.

Users should access the application through the CloudFront domain/custom domain rather than directly accessing the S3 bucket.

---

## 7. Backend Architecture

The backend provides the tutoring API.

```text
React
 │
 │ HTTPS /api/*
 ▼
CloudFront
 │
 ▼
ALB
 │
 │ HTTPS
 ▼
ECS Fargate
 │
 ▼
DynamoDB
```

The ECS application is responsible for:

* Student operations
* Tutor operations
* Course management
* Class management
* Tutor availability
* Booking management
* Reading and writing DynamoDB data
* Business logic
* API validation
* Authentication/authorization checks

---

## 8. DynamoDB

Amazon DynamoDB is the primary application database.

Potential application data includes:

```text
DynamoDB
│
├── Users
├── Students
├── Tutors
├── Courses
├── Classes
├── Enrollments
├── Bookings
└── Messages
```

The final DynamoDB design should be based on application access patterns.

The browser must **never connect directly to DynamoDB**.

The intended flow is:

```text
React
  │
  ▼
CloudFront
  │
  ▼
ALB
  │
  ▼
ECS
  │
  ▼
DynamoDB
```

---

## 9. Networking

The application should use an Amazon VPC.

Recommended architecture:

```text
                         VPC
                          │
             ┌────────────┴────────────┐
             │                         │
       Public Subnets             Private Subnets
             │                         │
             ▼                         ▼
       ┌───────────┐             ┌───────────┐
       │    ALB    │────────────►│ ECS Tasks │
       └───────────┘             └─────┬─────┘
                                       │
                                       ▼
                                  DynamoDB
```

Recommended approach:

* ALB in public subnets
* ECS Fargate tasks in private subnets
* ECS security group accepts traffic only from the ALB security group
* DynamoDB accessed by the ECS application through AWS APIs
* NAT Gateway can be used when private ECS tasks need outbound internet access

---

## 10. Security

### S3

* Keep the bucket private.
* Do not enable public read access.
* Allow CloudFront to access the bucket.
* Use appropriate bucket policies.

### CloudFront

* Redirect HTTP to HTTPS.
* Use the ACM certificate.
* Serve the React application through the CloudFront custom domain.

### ALB

* Use an HTTPS listener.
* Use an ACM certificate.
* Redirect HTTP to HTTPS where appropriate.
* Allow inbound traffic only from the intended source.

### ECS

* Run tasks in private subnets.
* Do not expose ECS task IPs directly to the internet.
* Use IAM task roles.
* Store secrets outside the container image.

### DynamoDB

* Do not expose database credentials to the frontend.
* Access DynamoDB using the ECS task IAM role.
* Grant only required DynamoDB permissions.

### IAM

Use separate IAM roles for:

* ECS task execution
* ECS application/task access
* CodeBuild
* CodePipeline
* Terraform deployment

Follow least-privilege permissions.

---

## 11. Container Architecture

The backend is packaged as a Docker image.

```text
Backend Source Code
        │
        ▼
      Docker
        │
        ▼
 Docker Image
        │
        ▼
       ECR
        │
        ▼
 ECS Fargate
```

ECR stores the backend Docker image.

ECS pulls the image from ECR when starting a task.

---

## 12. CI/CD

The application should use automated CI/CD.

```text
                         GitHub
                            │
                            ▼
                      CodePipeline
                            │
               ┌────────────┴────────────┐
               │                         │
               ▼                         ▼
          Frontend Build            Backend Build
               │                         │
               ▼                         ▼
           CodeBuild                 CodeBuild
               │                         │
               ▼                         ▼
               S3                        ECR
               │                         │
               ▼                         ▼
          CloudFront                 ECS Fargate
```

Terraform manages the AWS infrastructure separately.

---

## 13. Terraform Infrastructure

Terraform should manage the AWS resources.

```text
Terraform
│
├── VPC
│   ├── Subnets
│   ├── Route Tables
│   ├── Internet Gateway
│   └── NAT Gateway
│
├── S3
│   └── React Frontend Bucket
│
├── CloudFront
│   └── Distribution
│
├── ACM
│   ├── CloudFront Certificate
│   └── ALB Certificate
│
├── Route 53
│   └── DNS Records
│
├── ALB
│   ├── Load Balancer
│   ├── Target Group
│   └── HTTPS Listener
│
├── ECS
│   ├── Cluster
│   ├── Task Definition
│   └── Service
│
├── ECR
│   └── Repository
│
├── DynamoDB
│   └── Application Data
│
├── IAM
│   └── Roles and Policies
│
└── Security Groups
```

---

## 14. Terraform Project Structure

```text
tutoring-project/
│
├── frontend/
│   └── React application
│
├── backend/
│   ├── application source
│   ├── Dockerfile
│   └── dependencies
│
├── terraform/
│   │
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   │
│   ├── vpc.tf
│   ├── subnets.tf
│   ├── nat.tf
│   │
│   ├── s3.tf
│   ├── cloudfront.tf
│   │
│   ├── acm.tf
│   ├── route53.tf
│   │
│   ├── alb.tf
│   ├── ecs.tf
│   ├── ecr.tf
│   │
│   ├── dynamodb.tf
│   ├── iam.tf
│   └── security-groups.tf
│
├── buildspec-frontend.yml
├── buildspec-backend.yml
├── buildspec-test.yml
│
└── README.md
```

---

## 15. Example User Request

A student views their classes:

```text
Student
   │
   │ HTTPS
   ▼
Route 53
   │
   ▼
CloudFront
   │
   │ /api/classes
   ▼
ALB
   │
   │ HTTPS
   ▼
ECS Fargate
   │
   │ Query
   ▼
DynamoDB
   │
   │ Results
   ▼
ECS Fargate
   │
   ▼
ALB
   │
   ▼
CloudFront
   │
   ▼
React
   │
   ▼
Student
```

---

## 16. Example Booking Flow

```text
Student
   │
   ▼
React
   │
   │ POST /api/bookings
   ▼
CloudFront
   │
   ▼
ALB
   │
   ▼
ECS Fargate
   │
   ├── Validate request
   ├── Validate student
   ├── Validate tutor
   ├── Check availability
   │
   ▼
DynamoDB
   │
   └── Save booking
   │
   ▼
ECS Fargate
   │
   ▼
React
   │
   ▼
Booking Confirmation
```

---

## 17. MVP Scope

The initial version should focus on the core tutoring workflow.

## Student

* Register/login
* View tutors
* Search tutors by subject
* View tutor availability
* Book tutoring sessions
* View upcoming sessions

## Tutor

* Register/login
* Create tutor profile
* Define subjects
* Define availability
* View bookings
* Manage tutoring sessions

## Platform

* React frontend
* REST API
* ECS/Fargate backend
* DynamoDB database
* S3 frontend hosting
* CloudFront CDN
* Route 53 DNS
* ACM HTTPS certificates
* CI/CD deployment
* Terraform infrastructure

---

## 18. Future Enhancements

Potential future features include:

* Amazon Cognito authentication
* AWS WAF
* Email notifications
* SMS notifications
* Payment processing
* Tutor ratings/reviews
* Video tutoring
* Chat/messaging
* Homework/file uploads
* S3 file storage
* CloudWatch monitoring
* X-Ray tracing
* ECS Auto Scaling
* Backup and disaster recovery

These services should be added when they solve an actual application requirement.

---

## 19. Target Architecture Summary

```text
                              USERS
                                │
                                │ HTTPS
                                ▼
                         ┌──────────────┐
                         │   Route 53   │
                         │     DNS      │
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │  CloudFront  │
                         │     CDN      │
                         │              │
                         │ ACM Cert     │
                         └──────┬───────┘
                                │
                   ┌────────────┴────────────┐
                   │                         │
                /* │                      /api/*
                   │                         │
                   ▼                         ▼
            ┌─────────────┐           ┌─────────────┐
            │     S3      │           │     ALB     │
            │ React App   │           │    HTTPS    │
            └─────────────┘           │ ACM Cert    │
                                      └──────┬──────┘
                                             │
                                             ▼
                                      ┌─────────────┐
                                      │ ECS Fargate │
                                      │             │
                                      │ Tutoring API│
                                      └──────┬──────┘
                                             │
                                             ▼
                                      ┌─────────────┐
                                      │  DynamoDB   │
                                      │             │
                                      │ Students    │
                                      │ Tutors      │
                                      │ Classes     │
                                      │ Bookings    │
                                      └─────────────┘


                    ┌─────────────┐
                    │     ECR     │
                    │ Docker Image│
                    └──────┬──────┘
                           │
                           ▼
                      ECS Fargate


                    ┌──────────────────┐
                    │    Terraform     │
                    │                  │
                    │ VPC              │
                    │ S3               │
                    │ CloudFront       │
                    │ ACM              │
                    │ Route 53         │
                    │ ALB              │
                    │ ECS              │
                    │ ECR              │
                    │ DynamoDB         │
                    │ IAM              │
                    └──────────────────┘
```

## Core Architecture

### Users → Route 53 → CloudFront → S3

### Users → Route 53 → CloudFront → ALB → ECS Fargate → DynamoDB

### ACM → CloudFront + ALB

### ECR → ECS Fargate

### Terraform → AWS Infrastructure

### CodePipeline/CodeBuild → Application Deployment
