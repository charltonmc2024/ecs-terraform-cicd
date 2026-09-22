# Product

## Product Overview

Erudition Solution is a cloud-native SaaS platform for school districts
that provides adaptive test preparation for state standardized
assessments.

The platform is intended to provide personalized practice to students
and progress visibility to teachers.

## Primary Users

-   Students
-   Teachers
-   District and administrative staff

## Core Product Capabilities

The backend supports:

-   Student operations
-   Testing operations
-   Test management
-   Class management
-   Test availability
-   Role management
-   Question management
-   Reading and writing application data
-   Business logic
-   API validation
-   Authentication and authorization checks

## Core Testing Workflow

The initial product should focus on the core testing workflow and
interactions between teachers and students.

Student-facing capabilities include:

-   Register and log in
-   View tests
-   Search tests by subject
-   View test availability
-   Book test sessions
-   View upcoming sessions

## Product Principles

-   Keep the initial implementation focused on the MVP.
-   Add services and features when they solve an actual application
    requirement.
-   Prefer a scalable, secure, and cost-conscious production
    architecture.
-   Keep the browser separated from the database; application data
    access must go through the backend API.

## Detailed Product and Architecture Reference

See `docs/AWS-Production-Deployment.md`.

Legacy/current QA environment details belong in
`docs/QA-Environment-Specifications.md`, not in this steering file.
