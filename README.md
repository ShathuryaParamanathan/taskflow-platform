# TaskFlow Platform Engineering

TaskFlow is a containerized task-management API backed by PostgreSQL.
This repository demonstrates application testing, container image
creation, infrastructure-as-code validation, configuration management,
and a GitLab CI/CD workflow that publishes the API image to Amazon
Elastic Container Registry (ECR).

> **Deployment note:** The CI pipeline builds and pushes the image to
> ECR. A successful image push does not, by itself, deploy the
> application to a running AWS service. Complete the Terraform/Ansible
> deployment steps below only after reviewing the configuration and
> confirming the target AWS account, region, permissions, and expected
> costs.

## 1. DevOps vs. Platform Engineering

DevOps is a set of practices and a cultural approach that brings
software development and IT/operations closer together. Its goal is to
deliver reliable software faster by improving collaboration, automating
build and release workflows, monitoring applications, and using feedback
to improve the system. DevOps is not simply a tool or a separate team;
it is a shared responsibility across the software lifecycle.

Platform Engineering builds on these principles by providing an internal
platform that makes common engineering tasks easier, safer, and more
repeatable. A platform team creates reusable capabilities such as
deployment templates, infrastructure modules, CI/CD workflows,
observability, security guardrails, and self-service environments.
Product teams can then focus more on application features instead of
repeatedly solving infrastructure problems.

The main difference is emphasis: DevOps encourages shared ownership and
continuous delivery practices, while Platform Engineering packages
proven practices into reusable, supported platform capabilities. They
are complementary rather than competing approaches. A well-designed
platform helps teams apply DevOps consistently without removing their
responsibility for the applications they build and operate.

## 2. The shift toward DevSecOps and why it matters

DevSecOps integrates security into the full software delivery lifecycle
rather than leaving it until the end. As applications depend on
open-source packages, containers, cloud identities, infrastructure code,
and automated deployment pipelines, a vulnerability or misconfiguration
can enter production through many different paths.

A DevSecOps approach makes security continuous and collaborative.
Examples include dependency vulnerability checks, secret protection,
least-privilege IAM, container and infrastructure review, secure
defaults, automated tests, and audit-friendly deployment workflows.
Finding problems earlier usually makes them easier and less expensive to
fix, and it reduces the chance that an insecure release reaches users.

This repository includes an automated dependency audit
(`npm audit --omit=dev`) as part of its GitLab pipeline, alongside
testing and Terraform validation. These checks are useful safeguards,
but they are not a complete security programme. Before production use,
also review secrets and CI variables, IAM trust and permissions,
container image vulnerabilities, network exposure, logging, backups, and
runtime monitoring.

## 3. Repository overview

The repository includes the following main areas (file names may vary as
the implementation evolves):

-   `app/` --- Node.js TaskFlow API, tests, database setup/migrations,
    and Docker build context.
-   `terraform/` --- Terraform infrastructure configuration and modules.
-   Ansible playbooks and related configuration --- host
    configuration/automation where required by the deployment design.
-   `.gitlab-ci.yml` --- GitLab CI/CD stages for linting, tests,
    security checks, Terraform validation, and publishing the API image
    to ECR.
-   `terraform/modules/compute/vertical_scaler.py` --- scaling
    automation code used by the infrastructure configuration.

## 4. Prerequisites

Install and configure the tools needed for the part of the workflow you
intend to run:

-   Git
-   Node.js and npm (the project CI uses Node.js 24)
-   Docker Desktop or Docker Engine
-   PostgreSQL, or Docker to run PostgreSQL locally
-   Terraform (the project CI uses Terraform 1.16.6)
-   AWS CLI v2 for AWS operations
-   Ansible for playbook-based host configuration
-   A GitLab project with CI/CD enabled for the pipeline

For AWS deployment, use an AWS account with appropriately scoped IAM
permissions. Do not commit access keys, passwords, `.env` files, state
files, or other secrets to Git.

## 5. Run the API locally

Run commands from the repository root unless a command says otherwise.

### 5.1 Start PostgreSQL

If you do not already have a local PostgreSQL instance, start one with
Docker:

``` powershell
docker run -d --name taskflow-postgres `
  -e POSTGRES_DB=taskflow `
  -e POSTGRES_USER=taskflow_user `
  -e POSTGRES_PASSWORD=replace_with_a_local_password `
  -p 127.0.0.1:5433:5432 `
  postgres:17
```

If a container named `taskflow-postgres` already exists, start it
instead:

``` powershell
docker start taskflow-postgres
```

### 5.2 Install dependencies and configure the database

``` powershell
npm ci --prefix app
```

Configure the database variables expected by the application. The exact
values must match your PostgreSQL setup. For the example container
above:

``` powershell
$env:DB_HOST = "127.0.0.1"
$env:DB_PORT = "5433"
$env:DB_NAME = "taskflow"
$env:DB_USER = "taskflow_user"
$env:DB_PASSWORD = "replace_with_a_local_password"
```

The repository contains `app/ci-db-setup.cjs` and SQL migration files
for preparing the database. Run the setup script from the app directory
if it is the intended setup path for your current version:

``` powershell
Set-Location app
node ci-db-setup.cjs
```

Check the scripts defined in `app/package.json` before starting the API:

``` powershell
npm run
```

Then run the start script listed by the project (commonly `npm start` if
a `start` script is defined):

``` powershell
npm start
```

Keep this terminal open. In a second PowerShell terminal, from the
repository root, check the health endpoint:

``` powershell
Invoke-RestMethod http://localhost:3000/health
```

A healthy response should indicate that the TaskFlow API is running.
This health check verifies that the API responds; also test a
database-backed task endpoint to verify database connectivity and CRUD
behavior.

### 5.3 Run tests and local checks

From the repository root:

``` powershell
npm --prefix app test
npm --prefix app audit --omit=dev
node --check app/src/server.js
docker build -t taskflow-api:local ./app
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

The Terraform commands may require initialization first, depending on
the local setup. Use `terraform -chdir=terraform init -backend=false`
for validation-only initialization when appropriate; use the configured
remote backend only when you intend to work with the real shared state.

## 6. CI/CD workflow

The GitLab pipeline is designed to run these stages:

1.  **Lint** --- checks the Node.js server syntax.
2.  **Test** --- prepares a PostgreSQL service and runs the application
    tests.
3.  **Security scan** --- audits production npm dependencies.
4.  **Terraform validation** --- initializes without a backend,
    validates configuration, and checks formatting.
5.  **Build and push** --- builds the container image and pushes it to
    Amazon ECR for commits to `main`.

### Configure GitLab-to-AWS access

The build job is configured to use GitLab OIDC to assume an AWS IAM role
rather than storing long-lived AWS access keys in the repository. To
reproduce this in another AWS account:

1.  Create an ECR repository for the API image.
2.  Configure an IAM OIDC identity provider for GitLab using the
    official GitLab OIDC documentation.
3.  Create an IAM role whose trust policy restricts the audience and
    GitLab project/ref to the intended project and branch.
4.  Grant only the permissions needed to authenticate to ECR and push
    images to the specific repository.
5.  Update the role ARN, AWS region, ECR registry and repository
    variables in `.gitlab-ci.yml` for the target account.
6.  Run the pipeline on `main` and confirm that all jobs pass and the
    expected commit-tagged image appears in ECR.

Do not copy the example account ID or role ARN from another environment.
Use the values for your own AWS account.

## 7. Reproduce the deployment from a clean AWS account

This section describes the deployment process at a high level. Exact
resource names, variables, and commands must match the Terraform modules
and Ansible inventory in this repository.

1.  **Prepare the account and region.** Choose the AWS region, confirm
    budget/cost limits, and configure an IAM identity with
    least-privilege access for the resources declared by the Terraform
    configuration.
2.  **Review the infrastructure.** Read the root Terraform files and
    modules, identify every resource to be created, check variable
    defaults, and confirm networking, security groups, IAM policies,
    logs, alarms, and scaling settings.
3.  **Configure state safely.** If the Terraform backend uses S3 and
    lock files, create the state bucket in the chosen account/region
    before initializing the backend. Enable encryption and appropriate
    access controls. Keep the state file private because it can contain
    sensitive values. For a first-time deployment, follow the
    repository's backend bootstrap procedure rather than assuming the
    state bucket already exists.
4.  **Configure variables and secrets.** Supply environment-specific
    values using an untracked `.tfvars` file or approved secret
    mechanism. Never put credentials in source control.
5.  **Initialize and review the plan.** From the repository root, run
    the Terraform initialization command appropriate to the configured
    backend, then generate and review a plan before applying it. A
    validation-only initialization is not a deployment.
6.  **Deploy infrastructure only after review.** Apply the approved
    Terraform plan only after confirming all resources and their
    expected charges. Do not run `terraform apply` just to test the
    pipeline.
7.  **Configure hosts if required.** Update the Ansible inventory for
    the newly created target hosts and run the playbooks with the
    required SSH credentials and privilege escalation. Verify that each
    play completes successfully.
8.  **Publish the image.** Configure GitLab OIDC and ECR as described
    above, then run the pipeline to build and publish the image for the
    intended commit.
9.  **Deploy and verify the application.** Follow the actual
    Terraform/service configuration to deploy the published image.
    Confirm the service is healthy, database connectivity works, logs
    are visible, and the intended endpoint is reachable.
10. **Verify scaling and monitoring.** Confirm that the scaling Lambda,
    EventBridge rule, CloudWatch alarms, IAM permissions, and
    service/task-definition settings are created as expected. Test
    scaling behavior in a controlled environment and check logs and
    metrics. Do not trigger load or scaling tests in a production
    account without approval.
11. **Record cleanup instructions.** Document how to stop or remove test
    resources and how to preserve or intentionally delete the Terraform
    state. Review costs before leaving resources running.

Useful validation commands (adjust paths and backend configuration to
match the repository):

``` powershell
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

`terraform plan` previews intended changes. Review it before any apply
operation. Some repositories keep Terraform state bootstrap separate
from the main stack; follow that design if present.

## 8. Completion checklist

Before marking the assignment complete, collect evidence for each item
required by the original brief:

-   [ ] Root-level `README.md` includes the DevOps vs. Platform
    Engineering essay.
-   [ ] README discusses the DevSecOps shift and why it matters.
-   [ ] README provides local setup/run instructions and a clean-account
    deployment procedure.
-   [ ] GitLab pipeline for the latest commit passes all required jobs.
-   [ ] Automated tests pass against PostgreSQL.
-   [ ] Dependency security scan passes.
-   [ ] Docker image is built and published to the intended ECR
    repository.
-   [ ] Terraform formatting and validation pass.
-   [ ] Required AWS resources are deployed and healthy, if live
    deployment is part of the brief.
-   [ ] Required Ansible playbooks and scaling automation are executed
    and verified, if required.
-   [ ] No credentials, local `.env` files, or Terraform state are
    committed.
-   [ ] Submission repository URL and any required evidence are ready to
    share.

A green pipeline and a successful image push are important evidence, but
they do not prove that live infrastructure, database-backed behavior,
Ansible, or scaling works. Mark those items complete only after
verifying them against the original assignment requirements.
