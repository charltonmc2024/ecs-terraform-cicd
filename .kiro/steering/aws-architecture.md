# AWS Architecture

## 1. Purpose

This document defines the target AWS architecture for the **Online Tutoring Platform (eruditionsys.com)**.

The architecture is designed to provide:

* Secure application access
* Separation between frontend and backend
* Scalable backend compute
* Managed NoSQL database
* HTTPS communication
* CDN-based frontend delivery
* Containerized backend deployment
* Infrastructure as Code
* Automated CI/CD
* Cost-conscious MVP implementation

---

## 2. Architecture Overview

The application consists of two primary application layers:

### Frontend

### **React**

Hosted in:

### **Amazon S3**

Delivered through:

### **Amazon CloudFront**

### Backend

### **Python API**

Containerized with Docker and deployed to:

### **Amazon ECS Fargate**

Backend traffic is distributed through:

### **Application Load Balancer (ALB)**

Application data is stored in:

### **Amazon DynamoDB**

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
                         │              │
                         │ ACM Certificate
                         └──────┬───────┘
                                │
                  ┌─────────────┴─────────────┐
                  │                           │
               /* │                        /api/*
                  │                           │
                  ▼                           ▼
           ┌─────────────┐             ┌─────────────┐
           │     S3      │             │     ALB     │
           │             │             │    HTTPS    │
           │ React App   │             │ ACM Cert    │
           └─────────────┘             └──────┬──────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │ ECS Fargate  │
                                       │              │
                                       │ Python API   │
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


                         ┌──────────────┐
                         │     ECR      │
                         │              │
                         │ Python API   │
                         │ Docker Image │
                         └──────┬───────┘
                                │
                                ▼
                           ECS Fargate
```

---

## 4. AWS Services

| Layer          | AWS Service  | Purpose                   |
| -------------- | ------------ | ------------------------- |
| DNS            | Route 53     | Domain name resolution    |
| CDN            | CloudFront   | Global content delivery   |
| Certificate    | ACM          | TLS/HTTPS certificates    |
| Frontend       | S3           | React static files        |
| Load Balancing | ALB          | Backend API traffic       |
| Compute        | ECS Fargate  | Python backend containers |
| Registry       | ECR          | Docker image storage      |
| Database       | DynamoDB     | Application data          |
| Networking     | VPC          | Network isolation         |
| Security       | IAM          | Access control            |
| Monitoring     | CloudWatch   | Logs and metrics          |
| IaC            | Terraform    | Infrastructure management |
| CI/CD          | CodePipeline | Deployment orchestration  |
| CI/CD          | CodeBuild    | Build and test            |

Additional services should only be introduced when required by the application.

---

## 5. Request Flow

## 5.1 Frontend Request

When a user accesses the tutoring platform:

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
 ▼
S3
 │
 ▼
React Application
```

The React application is downloaded from CloudFront.

The S3 bucket should remain private.

CloudFront is the public entry point for the frontend.

---

## 6. Backend API Request

When React needs application data:

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
 ▼
ECS Fargate
 │
 ▼
DynamoDB
```

The backend response follows the reverse path:

```text
DynamoDB
   │
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
User
```

The frontend must not connect directly to DynamoDB.

---

## 7. Frontend Architecture

The frontend is implemented using **React**.

```text
React Source Code
       │
       ▼
    Build
       │
       ▼
   Static Files
       │
       ▼
      S3
       │
       ▼
 CloudFront
       │
       ▼
     Users
```

Typical frontend files include:

```text
index.html
JavaScript bundles
CSS
Images
Fonts
Other static assets
```

S3 is used only for frontend/static assets unless another requirement is explicitly introduced.

---

## 8. Backend Architecture

The backend is implemented using **Python**.

The backend is packaged as a Docker image.

```text
Python Application
       │
       ▼
     Docker
       │
       ▼
      ECR
       │
       ▼
ECS Fargate
       │
       ▼
      ALB
```

The Python API is responsible for:

* API endpoints
* Application business logic
* Request validation
* Authentication/authorization checks
* Student operations
* Tutor operations
* Course operations
* Class operations
* Booking operations
* DynamoDB access

---

## 9. ECS Fargate

The backend runs as an ECS service.

```text
ECS Cluster
│
└── Tutoring API Service
    │
    ├── Fargate Task
    │     └── Python Container
    │
    └── Fargate Task
          └── Python Container
```

The number of tasks can be increased as application traffic increases.

The backend should be stateless.

Persistent application data should not be stored inside the container filesystem.

Persistent data belongs in:

* DynamoDB
* S3
* Other appropriate managed services

---

## 10. ECR

Amazon ECR stores the Docker images used by ECS.

```text
Python Source
     │
     ▼
CodeBuild
     │
     ▼
Docker Build
     │
     ▼
ECR
     │
     ▼
ECS Fargate
```

Container images should use identifiable version tags.

Preferred examples:

```text
v1.0.0
commit-abc123
build-123
```

Avoid relying exclusively on the `latest` tag.

---

## 11. Application Load Balancer

The ALB is the entry point for backend traffic.

```text
CloudFront
     │
     ▼
    ALB
     │
     ▼
ECS Target Group
     │
     ├── Task 1
     ├── Task 2
     └── Task 3
```

The ALB should:

* Use HTTPS
* Use an ACM certificate
* Perform health checks
* Forward traffic to ECS
* Support multiple ECS tasks
* Avoid exposing ECS task IP addresses directly

---

## 12. ACM and HTTPS

AWS Certificate Manager provides TLS certificates.

There are two important certificate requirements.

## CloudFront Certificate

The ACM certificate used by CloudFront must be created in:

```text
us-east-1
```

Example:

```text
ACM
 │
 └── CloudFront Certificate
        │
        ▼
    CloudFront
```

## ALB Certificate

The certificate used by the ALB must be located in the same AWS region as the ALB.

Example:

```text
Application Region
 │
 └── ACM
      │
      └── ALB Certificate
```

Therefore, the architecture may contain two ACM certificates:

```text
ACM
│
├── CloudFront Certificate
│      └── us-east-1
│
└── ALB Certificate
       └── ALB's region
```

---

## 13. Route 53

Route 53 provides DNS resolution.

Example:

```text
tutoringapp.com
       │
       ▼
    Route 53
       │
       ▼
  CloudFront
```

The public application should use a custom domain.

Example:

```text
https://tutoringapp.com
```

or:

```text
https://www.tutoringapp.com
```

Route 53 should use alias records where appropriate.

---

## 14. CloudFront

CloudFront provides:

* CDN delivery
* Frontend caching
* HTTPS
* Custom domain support
* Multiple origins
* Request routing

The recommended CloudFront design uses two origins:

```text
CloudFront
│
├── Default Origin
│      │
│      ▼
│      S3
│      │
│      └── React Frontend
│
└── API Origin
       │
       ▼
      ALB
       │
       ▼
      ECS
```

Recommended routing:

```text
/*       → S3
/api/*   → ALB
```

This allows the entire application to use a single public domain.

Example:

```text
https://tutoringapp.com/
```

Frontend:

```text
https://tutoringapp.com/dashboard
```

Backend:

```text
https://tutoringapp.com/api/classes
```

---

## 15. S3 Security

The React S3 bucket should be private.

Do not expose the bucket directly to the public internet.

Preferred:

```text
User
 │
 ▼
CloudFront
 │
 ▼
Private S3 Bucket
```

Use CloudFront's origin access mechanism to authorize access to S3.

The S3 bucket should also use:

* Block Public Access
* Encryption
* Appropriate bucket policy
* Versioning when appropriate

---

## 16. VPC Architecture

The backend infrastructure should run inside an Amazon VPC.

Recommended architecture:

```text
                              VPC
                               │
                 ┌─────────────┴─────────────┐
                 │                           │
          Public Subnets              Private Subnets
                 │                           │
                 ▼                           ▼
             ┌───────┐                 ┌───────────┐
             │  ALB  │────────────────►│ ECS Tasks │
             └───────┘                 └─────┬─────┘
                                             │
                                             ▼
                                        DynamoDB
```

The ALB should be deployed in public subnets.

ECS tasks should be deployed in private subnets.

---

## 17. Availability Zones

Production infrastructure should use multiple Availability Zones.

Example:

```text
                     VPC
                      │
          ┌───────────┴───────────┐
          │                       │
        AZ-A                    AZ-B
          │                       │
     ┌────┴────┐             ┌────┴────┐
     │ Public  │             │ Public  │
     │   ALB   │             │   ALB   │
     └────┬────┘             └────┬────┘
          │                       │
     ┌────┴────┐             ┌────┴────┐
     │ Private │             │ Private │
     │   ECS   │             │   ECS   │
     └─────────┘             └─────────┘
```

This allows the ECS service to continue operating if one Availability Zone becomes unavailable.

For the MVP development environment, the architecture may use fewer resources when cost is more important than high availability.

---

## 18. NAT Gateway

Private ECS tasks may require outbound internet access.

Example:

```text
ECS Private Subnet
        │
        ▼
   NAT Gateway
        │
        ▼
Internet Gateway
        │
        ▼
    Internet
```

A NAT Gateway may be required for:

* External API calls
* Package downloads
* External services
* Container startup dependencies

For development, a single NAT Gateway may be used to reduce cost.

For production, multi-AZ NAT architecture should be considered when high availability is required.

---

## 19. DynamoDB

DynamoDB is the primary application database.

Potential application data:

```text
DynamoDB
│
├── Students
├── Tutors
├── Courses
├── Classes
├── Enrollments
├── Bookings
└── Messages
```

The final table design should be based on application access patterns.

A DynamoDB single-table design may be considered when the application's access patterns are well understood.

The MVP should prioritize simplicity and correct access patterns over premature optimization.

---

## 20. DynamoDB Access

DynamoDB should only be accessed by the backend.

```text
React
 │
 X
 │
 └── No direct DynamoDB access
     
ECS
 │
 ▼
DynamoDB
```

The ECS task IAM role should provide the required DynamoDB permissions.

AWS credentials must never be embedded in the React application.

---

## 21. Security Group Architecture

Security groups should restrict communication between application layers.

Recommended:

```text
Internet
   │
   ▼
CloudFront
   │
   ▼
ALB Security Group
   │
   ▼
ECS Security Group
   │
   ▼
AWS Services
```

ECS should accept inbound traffic only from the ALB security group.

Avoid unrestricted inbound access such as:

```text
0.0.0.0/0
```

for internal application traffic.

---

## 22. IAM Architecture

Use separate IAM roles for different workloads.

```text
IAM
│
├── Terraform Role
│
├── CodePipeline Role
│
├── CodeBuild Role
│
├── ECS Task Execution Role
│
└── ECS Task Role
```

The ECS task role should provide application permissions such as DynamoDB access.

The ECS task execution role provides permissions required for ECS to run the container, such as pulling images and writing logs.

---

## 23. CI/CD Architecture

The application should use automated CI/CD.

```text
                         GitHub
                            │
                            ▼
                      CodePipeline
                            │
                 ┌──────────┴──────────┐
                 │                     │
                 ▼                     ▼
           Frontend Build         Backend Build
                 │                     │
                 ▼                     ▼
             CodeBuild             CodeBuild
                 │                     │
                 ▼                     ▼
                S3                    ECR
                 │                     │
                 ▼                     ▼
            CloudFront             ECS
                                      │
                                      ▼
                                     ALB
```

---

## 24. Frontend Deployment

Frontend deployment flow:

```text
GitHub
   │
   ▼
CodePipeline
   │
   ▼
CodeBuild
   │
   ├── Install dependencies
   ├── Run tests
   ├── Build React application
   │
   ▼
S3
   │
   ▼
CloudFront
```

CloudFront cache invalidation should be performed when necessary after deployment.

---

## 25. Backend Deployment

Backend deployment flow:

```text
GitHub
   │
   ▼
CodePipeline
   │
   ▼
CodeBuild
   │
   ├── Run tests
   ├── Build Docker image
   ├── Tag image
   └── Push image
           │
           ▼
          ECR
           │
           ▼
       ECS Service
           │
           ▼
       New Task
```

ECS should deploy the new container image using the desired deployment strategy.

---

## 26. Terraform Architecture

Terraform manages the infrastructure.

```text
Terraform
│
├── Networking
│   ├── VPC
│   ├── Public Subnets
│   ├── Private Subnets
│   ├── Route Tables
│   ├── Internet Gateway
│   └── NAT Gateway
│
├── Frontend
│   └── S3
│
├── CDN
│   └── CloudFront
│
├── HTTPS
│   └── ACM
│
├── DNS
│   └── Route 53
│
├── Backend
│   ├── ALB
│   ├── ECS
│   └── ECR
│
├── Database
│   └── DynamoDB
│
└── Security
    ├── IAM
    └── Security Groups
```

---

## 27. Monitoring

Amazon CloudWatch should be used for operational visibility.

Monitor:

### ECS

* CPU utilization
* Memory utilization
* Running task count
* Failed tasks
* Container logs

### ALB

* Request count
* Target response time
* HTTP errors
* Unhealthy targets

### CloudFront

* Requests
* Error rates
* Cache behavior

### DynamoDB

* Read/write activity
* Throttling
* Errors
* Capacity usage

---

## 28. Logging

Application logs should be sent to CloudWatch Logs.

Recommended flow:

```text
Python Container
       │
       ▼
CloudWatch Logs
       │
       ▼
Log Group
```

Logs should not contain:

* Passwords
* AWS credentials
* API secrets
* Authentication tokens
* Sensitive user information

---

## 29. Data Storage Strategy

Use each storage service for its intended purpose.

```text
S3
│
└── Static frontend files
    User-uploaded files
    Documents
    Media


DynamoDB
│
└── Application data
    Users
    Tutors
    Students
    Classes
    Bookings
    Messages


ECR
│
└── Docker images
```

Do not use ECS container storage for persistent application data.

---

## 30. Application Example

## Student Views Classes

```text
Student
   │
   ▼
React
   │
   │ GET /api/classes
   ▼
CloudFront
   │
   ▼
ALB
   │
   ▼
Python API on ECS
   │
   ▼
DynamoDB
   │
   │ Classes
   ▼
Python API
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

## 31. Application Example: Booking

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
Python API
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
Python API
   │
   ▼
React
   │
   ▼
Booking Confirmation
```

---

## 32. Environment Architecture

The project should eventually support:

```text
Development
    │
    ▼
Staging
    │
    ▼
Production
```

Each environment should have appropriately isolated infrastructure.

Example:

```text
tutoring-dev
tutoring-staging
tutoring-prod
```

Development environments should prioritize cost efficiency.

Production should prioritize availability, security, monitoring, and reliability.

---

## 33. MVP Architecture

The initial MVP should use only the services necessary to operate the tutoring platform:

```text
Route 53
    │
    ▼
CloudFront + ACM
    │
    ├──────────────► S3
    │                 │
    │                 └── React
    │
    └──────────────► ALB + ACM
                      │
                      ▼
                  ECS Fargate
                      │
                      ▼
                  DynamoDB

ECR ────────────────► ECS

Terraform ──────────► AWS Infrastructure

CodePipeline
      │
      ├──► S3 / CloudFront
      │
      └──► ECR / ECS
```

---

## 34. Future Services

Additional AWS services may be introduced as the application grows.

Potential services include:

* Amazon Cognito
* AWS WAF
* Amazon SES
* Amazon SNS
* Amazon SQS
* Amazon EventBridge
* Amazon S3 for user files
* CloudWatch alarms
* AWS X-Ray
* ECS Auto Scaling
* AWS Backup

These services should not be added solely for architectural complexity.

Each additional service should have a clear application requirement.

---

## 35. Architecture Principles

The architecture should follow these principles:

1. **Security by default**
2. **Least privilege**
3. **Private backend**
4. **Private S3 frontend bucket**
5. **HTTPS everywhere**
6. **Managed AWS services where practical**
7. **Stateless ECS application**
8. **Persistent data in DynamoDB/S3**
9. **Infrastructure managed through Terraform**
10. **Automated CI/CD**
11. **Horizontal scalability**
12. **Cost-conscious MVP design**
13. **Multi-AZ production architecture**
14. **Minimal unnecessary AWS services**
15. **Clear separation between frontend and backend**

---

## 36. Kiro Agent Architecture Rules

When working on this project, the agent should follow these architectural rules:

1. React is the **frontend**.
2. Python is the **backend/API**.
3. S3 hosts the React static frontend.
4. CloudFront delivers the frontend.
5. CloudFront routes `/api/*` to the backend ALB when using the single-domain architecture.
6. ALB distributes API traffic to ECS Fargate.
7. ECS Fargate runs the Python backend.
8. ECR stores backend Docker images.
9. DynamoDB stores persistent application data.
10. The frontend must not directly access DynamoDB.
11. ECS tasks should run in private subnets where practical.
12. ALB should be the public entry point for backend traffic.
13. HTTPS should be used for public traffic.
14. ACM should provide TLS certificates.
15. CloudFront ACM certificates must be created in `us-east-1`.
16. ALB ACM certificates must be created in the ALB's region.
17. Route 53 should manage the application's DNS.
18. S3 should remain private.
19. IAM should follow least privilege.
20. Do not introduce additional AWS services without a clear requirement.
21. Prefer simple architecture for the MVP.
22. Preserve existing resources unless a requested change requires modification or destruction.
23. Check the existing Terraform configuration before creating new resources.
24. Keep the architecture consistent with `project-overview.md` and `terraform-standards.md`.

---

## 37. Target Architecture

The target architecture is:

```text
                              INTERNET
                                  │
                                  ▼
                              Route 53
                                  │
                                  ▼
                         ┌────────────────┐
                         │   CloudFront   │
                         │                │
                         │ ACM Certificate│
                         └───────┬────────┘
                                 │
                   ┌─────────────┴─────────────┐
                   │                           │
                /* │                        /api/*
                   │                           │
                   ▼                           ▼
              ┌─────────┐                 ┌─────────┐
              │   S3    │                 │   ALB   │
              │         │                 │   HTTPS │
              │ React   │                 │ ACM Cert│
              └─────────┘                 └────┬────┘
                                                │
                                                ▼
                                         ┌────────────┐
                                         │    ECS     │
                                         │  Fargate   │
                                         │            │
                                         │ Python API │
                                         └─────┬──────┘
                                               │
                                               ▼
                                         ┌────────────┐
                                         │  DynamoDB  │
                                         │            │
                                         │ Students   │
                                         │ Tutors     │
                                         │ Classes    │
                                         │ Bookings   │
                                         └────────────┘


                       ┌──────────────┐
                       │     ECR      │
                       │ Python API   │
                       │ Docker Image │
                       └──────┬───────┘
                              │
                              ▼
                         ECS Fargate


                       ┌──────────────┐
                       │  Terraform   │
                       │              │
                       │ VPC          │
                       │ S3           │
                       │ CloudFront   │
                       │ ACM          │
                       │ Route 53     │
                       │ ALB          │
                       │ ECS          │
                       │ ECR          │
                       │ DynamoDB     │
                       │ IAM          │
                       └──────────────┘
```

## Final Architecture Flow

### **User → Route 53 → CloudFront → S3 → React**

### **User → Route 53 → CloudFront → ALB → ECS Fargate → DynamoDB**

### **ECR → ECS Fargate**

### **ACM → CloudFront + ALB**

### **Terraform → AWS Infrastructure**

### **CodePipeline + CodeBuild → Application Deployment**
