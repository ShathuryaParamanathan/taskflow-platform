# Operational Runbook — TaskFlow

**Audience:** On-call engineers  
**Purpose:** Diagnose incidents, restore service, deploy releases safely, manage scaling, and recover the RDS database.

## 0. Environment and initial checks

### 0.1 Set the AWS context

Run commands from a trusted workstation with the appropriate AWS IAM permissions.

```bash
export AWS_PROFILE=taskflow-dev
export AWS_REGION=ap-south-1
export CLUSTER=taskflow-cluster
export SERVICE=taskflow-api
export DB_ID=taskflow-db

aws sts get-caller-identity
aws configure get region --profile "$AWS_PROFILE"
```

Confirm that the AWS account, region, cluster, service, and database match the target environment before making changes.

The resource names above are expected defaults. Verify them against Terraform outputs and the deployed AWS resources.

| Component | Reference |
|---|---|
| Application | TaskFlow API |
| ECS cluster | `taskflow-cluster` |
| ECS service | `taskflow-api` |
| Application logs | `/ecs/taskflow-api` |
| Container image | ECR repository `taskflow-api` |
| Health endpoint | `GET /health` through the ALB |
| Infrastructure | Terraform |
| CI/CD | GitLab CI/CD |
| Database | Amazon RDS |

### 0.2 Initial incident triage

Start here for any service incident.

```bash
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].{
    desired:desiredCount,
    running:runningCount,
    pending:pendingCount,
    taskDefinition:taskDefinition,
    events:events[:10].message
  }'
```

Inspect the application logs:

```bash
aws logs tail /ecs/taskflow-api \
  --since 15m \
  --region "$AWS_REGION" \
  --follow
```

Check the application health endpoint:

```bash
curl -i --max-time 10 http://<alb-dns>/health
```

Replace `<alb-dns>` with the deployed Application Load Balancer DNS name.

**Operational rule:** Stabilize the service first, preserve evidence, and investigate the root cause. Roll back only when the evidence indicates that a recent release is responsible or when rollback is the safest available recovery action.

---

## 1. Deployment and rollback

### 1.1 Standard deployment procedure

Deployments should normally use the repository's GitLab CI/CD pipeline.

1. Create a feature branch and submit a merge request.
2. Review the changes, especially application configuration, infrastructure changes, IAM permissions, and database migrations.
3. Ensure the required pipeline jobs pass. These should include the checks actually configured in `.gitlab-ci.yml`, such as linting and tests.
4. Merge the approved changes into the deployment branch.
5. Confirm that the pipeline builds the application image and pushes it to ECR using the commit SHA or another immutable image identifier.
6. Confirm that the pipeline registers the correct ECS task definition revision and updates the ECS service.
7. Monitor ECS deployment events, task startup, application logs, and ALB target health.
8. Verify the health endpoint and perform a basic application smoke test.
9. Monitor error rates and latency after deployment.

Check the deployment:

```bash
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].{
    taskDefinition:taskDefinition,
    desired:desiredCount,
    running:runningCount,
    pending:pendingCount,
    deployments:deployments[].{
      status:status,
      taskDefinition:taskDefinition,
      rolloutState:rolloutState,
      running:runningCount
    },
    events:events[:10].message
  }'
```

Wait for ECS to report service stability:

```bash
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE"
```

Then check application health:

```bash
curl -fsS --max-time 10 http://<alb-dns>/health
```

A successful health response alone is not sufficient. Confirm that the ALB has healthy targets and that normal application requests work.

**Important:** Use the pipeline's actual deployment behavior. Do not assume automated rollback, security scanning, or Terraform execution exists unless those steps are configured in the repository.

### 1.2 Emergency rollback

Initiate rollback when a release causes a sustained increase in errors, failed health checks, severe latency, or a service outage.

First, identify the currently deployed task definition:

```bash
CURRENT_TD=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].taskDefinition' \
  --output text)

echo "$CURRENT_TD"
```

List recent task definition revisions:

```bash
aws ecs list-task-definitions \
  --family-prefix taskflow-api \
  --sort DESC \
  --max-items 10
```

Identify the previous known-good revision using deployment history, pipeline records, or the last successful release. Do not blindly assume that the numerically previous revision is the correct rollback target.

Set the verified revision:

```bash
export PREVIOUS_TD=taskflow-api:<known-good-revision>
```

Update the service:

```bash
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$PREVIOUS_TD"
```

Monitor the rollback:

```bash
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE"

curl -fsS --max-time 10 http://<alb-dns>/health
```

Verify that the intended task definition is active, the desired number of tasks is running, the ALB targets are healthy, and application errors have returned to an acceptable level.

If rollback fails, inspect ECS service events and stopped-task reasons. Escalate to the engineering lead if service cannot be restored promptly.

### 1.3 Rollback precautions

- Preserve the failed release's commit SHA, task definition ARN, logs, and deployment timestamps.
- Do not delete the failed revision or its image before the investigation is complete.
- Check database migration compatibility before reverting application code. A database schema change may not be reversible simply by restoring an older application image.
- Prefer backward-compatible expand-and-contract migrations.
- If Terraform manages the affected resource, make the permanent correction in Terraform and reconcile manual changes before the next `terraform apply`.
- Record the incident and the final recovery action.

---

## 2. Scaling and manual intervention

### 2.1 Determine the scaling mechanism

Before intervening, identify the mechanism implemented in the deployed infrastructure.

- **Horizontal scaling** changes the number of ECS tasks.
- **Vertical scaling** changes the CPU and memory assigned to a task, generally through a new task definition revision and service deployment.
- **EC2 capacity scaling** increases or decreases the number of EC2 instances available to an ECS cluster.

These are separate mechanisms and must not be treated as interchangeable.

Inspect the current service:

```bash
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].{
    desiredCount:desiredCount,
    runningCount:runningCount,
    taskDefinition:taskDefinition,
    capacityProviders:capacityProviderStrategy
  }'
```

Inspect task resource allocation:

```bash
CURRENT_TD=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].taskDefinition' \
  --output text)

aws ecs describe-task-definition \
  --task-definition "$CURRENT_TD" \
  --query 'taskDefinition.{
    cpu:cpu,
    memory:memory,
    containers:containerDefinitions[].{
      name:name,
      cpu:cpu,
      memory:memory,
      memoryReservation:memoryReservation
    }
  }'
```

Inspect scaling alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix taskflow- \
  --query 'MetricAlarms[].{
    name:AlarmName,
    state:StateValue,
    metric:MetricName,
    actionsEnabled:ActionsEnabled
  }'
```

Review the Terraform configuration and deployment history to determine which alarms, scaling policies, Lambda functions, or automation components actually control the service.

### 2.2 Automated vertical scaling

If the deployed implementation uses automated vertical scaling, document its actual trigger, thresholds, cooldown, permitted task sizes, and execution mechanism here.

The expected operational sequence for a task-definition-based vertical scaler is:

1. A monitored metric crosses its configured threshold.
2. The configured alarm or automation detects the condition.
3. The scaler selects an allowed CPU and memory configuration.
4. A new task definition revision is registered.
5. The ECS service deploys tasks using the new revision.
6. Health checks determine whether the new tasks are suitable to serve traffic.
7. Monitoring confirms whether resource pressure has improved.

The implementation may use a different trigger or workflow. Verify the deployed configuration before relying on this sequence.

**Guard rails to verify:** minimum and maximum task sizes, cooldown periods, protection against repeated scaling actions, deployment health checks, alerting, and sufficient cluster capacity.

### 2.3 Manual intervention

If scaling repeatedly changes task sizes, fails to respond, or causes task placement failures:

1. Check the relevant alarm state, recent scaling actions, service events, CPU and memory utilization, and application error rate.
2. Determine whether the immediate problem is task resource allocation, task count, EC2 capacity, or a database bottleneck.
3. If the automated controller is repeatedly applying an unsafe configuration, disable only the relevant scaling action using the mechanism documented in the infrastructure. Preserve monitoring and alerting where possible.
4. Restore a known-good task definition if the current resource configuration is causing failures.
5. If the application is overloaded but each task has sufficient resources, increase the ECS desired task count within the available capacity and configured limits.
6. If the cluster lacks capacity, address the underlying EC2 capacity or placement constraint.
7. Correct the source configuration in Terraform and redeploy it through the approved workflow.
8. Re-enable the relevant automation and verify normal operation.

Example: temporarily increase the ECS service's desired task count, if horizontal scaling is supported by the deployed service:

```bash
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --desired-count <approved-task-count>
```

This changes the number of tasks; it does not increase their CPU or memory allocation.

**Caution:** Manual changes may be overwritten by automated scaling or a subsequent Terraform deployment. Record every intervention and restore the intended configuration after the incident.

---

## 3. Incident response

### 3.1 Incident A: ECS tasks stuck in PENDING

**Symptoms**

- The pending task count remains above zero.
- The running task count is lower than the desired count.
- ECS service events report placement failures.

**Diagnosis**

```bash
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].events[:15].message'

aws ecs list-container-instances \
  --cluster "$CLUSTER" \
  --query 'containerInstanceArns'
```

Inspect recent stopped tasks:

```bash
aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status STOPPED \
  --max-results 10
```

If the cluster uses the EC2 launch type, inspect container instance capacity and registration. If it uses Fargate, investigate Fargate-specific placement, subnet, IP address, IAM, and task configuration issues instead.

**Common causes and remediation**

| Cause | Remediation |
|---|---|
| Insufficient CPU or memory | Reduce the task's resource request only if safe, or provide suitable additional capacity. |
| EC2 Auto Scaling Group at its maximum | Verify scaling activity and increase the configured maximum through the approved infrastructure workflow. |
| ECS container instance disconnected | Inspect ECS agent health, instance logs, networking, and cluster registration. Replace unhealthy instances through the normal recovery process. |
| ECR image cannot be pulled | Verify image existence, execution-role permissions, network connectivity, and registry access. |
| Subnet IP exhaustion | Check available subnet addresses and task networking requirements. |
| Placement constraints or capacity provider problems | Inspect ECS service events, capacity-provider settings, instance types, and placement rules. |

**Verification**

- Running tasks match the desired count, subject to the configured deployment state.
- The ALB has healthy targets.
- The application health endpoint responds successfully.
- ECS service events no longer report the original placement failure.

### 3.2 Incident B: ALB returns HTTP 502

**Symptoms**

- Users receive `502 Bad Gateway`.
- ALB 5xx errors increase.
- Requests fail despite the ALB DNS name resolving.

**Diagnosis**

Inspect target health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --query 'TargetHealthDescriptions[].{
    target:Target.Id,
    state:TargetHealth.State,
    reason:TargetHealth.Reason,
    description:TargetHealth.Description
  }'
```

Inspect application logs:

```bash
aws logs tail /ecs/taskflow-api \
  --since 15m \
  --region "$AWS_REGION"
```

Inspect stopped tasks:

```bash
aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status STOPPED \
  --max-results 10
```

**Common causes and remediation**

| Cause | Remediation |
|---|---|
| No healthy targets | Inspect task failures and health-check results; roll back a faulty release if appropriate. |
| Application crashes during startup | Inspect container logs, environment variables, secrets, and database connectivity. |
| Incorrect target port or health-check path | Compare the container port, target group configuration, and application health route. |
| ALB-to-task network access blocked | Verify security group rules, routing, and network ACLs. |
| Application overload or out-of-memory termination | Inspect resource utilization and stopped-task reasons; restore capacity or correct the resource configuration. |
| Application closes connections unexpectedly | Inspect application and ALB logs, keep-alive settings, and timeout configuration. |

**Verification**

1. Target health reports healthy targets.
2. The health endpoint returns the expected successful status.
3. A representative application request succeeds.
4. ALB error rates and application latency return to baseline.

If the incident began immediately after a deployment and the release is the likely cause, use Section 1.2 to roll back.

### 3.3 Incident C: Database connection pool exhaustion

**Symptoms**

- API requests fail or time out.
- Logs report connection acquisition timeouts or connection-limit errors.
- RDS connection counts increase.
- Database queries may slow down even when application CPU utilization is low.

**Diagnosis**

Check the RDS connection metric:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_ID" \
  --start-time <start-time-UTC> \
  --end-time <end-time-UTC> \
  --period 60 \
  --statistics Maximum
```

Replace the time placeholders with valid UTC timestamps.

Determine the database engine before running engine-specific queries. For PostgreSQL, an authorized database session can use:

```sql
SELECT state, COUNT(*)
FROM pg_stat_activity
GROUP BY state;

SELECT pid,
       state,
       now() - query_start AS query_duration,
       LEFT(query, 120) AS query_text
FROM pg_stat_activity
WHERE state <> 'idle'
  AND query_start IS NOT NULL
ORDER BY query_start
LIMIT 10;

SHOW max_connections;
```

For MySQL, use the corresponding `SHOW PROCESSLIST` and connection-limit diagnostics.

**Remediation**

1. Determine whether the problem is a traffic spike, slow query, leaked connection, or excessive aggregate pool size.
2. Check the total potential connection demand across all application tasks, including background workers and other clients.
3. Reduce incoming load or scale application tasks only after considering the additional database connections each task can create.
4. Restart unhealthy application tasks if a confirmed connection leak or stuck pool requires it and the impact is understood.
5. Terminate individual database sessions only after confirming that they are safe to terminate. Avoid indiscriminately terminating active transactions.
6. Correct connection acquisition and release logic, pool limits, and query or connection timeouts.
7. Consider RDS Proxy if appropriate for the workload and architecture.
8. Alert before the connection count approaches the database's safe operating limit.

**Verification**

- Connection counts stabilize below the configured operational limit.
- Connection acquisition timeouts stop.
- Application error rates and latency recover.
- No important transaction or data-integrity issue remains.

### 3.4 Incident D: Deployment fails or repeatedly rolls back

**Symptoms**

- New tasks fail health checks.
- ECS deployment events report failures.
- The service does not stabilize on the expected revision.

**Diagnosis**

```bash
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].{
    taskDefinition:taskDefinition,
    deployments:deployments,
    events:events[:15].message
  }'
```

Inspect stopped-task details:

```bash
aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status STOPPED \
  --max-results 10
```

Use the returned task ARNs with `aws ecs describe-tasks` to inspect stop codes and stopped reasons.

**Remediation**

1. Check image availability and task execution-role permissions.
2. Verify required environment variables, secrets, ports, and health checks.
3. Check database connectivity and migration compatibility.
4. Confirm that the cluster has enough capacity for the deployment strategy.
5. If the release is faulty, roll back using Section 1.2.
6. Correct the underlying issue and deploy again through the approved pipeline.

**Verification:** The service stabilizes, the expected task definition is active, and application smoke tests pass.

---

## 4. RDS backup and restore

### 4.1 Backup requirements

Verify the actual database configuration before an incident:

- Automated backup retention period.
- Point-in-time recovery availability and latest restorable time.
- Encryption and KMS permissions.
- Database subnet group and security group.
- Required recovery point and acceptable data loss.
- Recovery time objective (RTO) and recovery point objective (RPO).

Automated backups and manual snapshots serve different recovery needs. Multi-AZ deployment improves availability but does not replace backups for accidental deletion, corruption, or unwanted schema changes.

Do not assume that Multi-AZ, a particular backup retention period, or point-in-time recovery is enabled until verified.

Inspect the RDS configuration:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{
    status:DBInstanceStatus,
    endpoint:Endpoint.Address,
    engine:Engine,
    multiAZ:MultiAZ,
    backupRetention:BackupRetentionPeriod,
    latestRestorableTime:LatestRestorableTime,
    subnetGroup:DBSubnetGroup.DBSubnetGroupName,
    vpcSecurityGroups:VpcSecurityGroups[].VpcSecurityGroupId
  }'
```

### 4.2 Create a manual snapshot

Before a risky database migration or maintenance operation, take a manual snapshot if the recovery plan requires one.

```bash
export SNAPSHOT_ID="taskflow-manual-$(date -u +%Y%m%d-%H%M%S)"

aws rds create-db-snapshot \
  --db-instance-identifier "$DB_ID" \
  --db-snapshot-identifier "$SNAPSHOT_ID"

aws rds wait db-snapshot-available \
  --db-snapshot-identifier "$SNAPSHOT_ID"
```

Verify that the snapshot is available:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --query 'DBSnapshots[0].{
    status:Status,
    created:SnapshotCreateTime,
    encrypted:Encrypted,
    source:DBInstanceIdentifier
  }'
```

Store snapshot identifiers and recovery notes in the approved operational record.

### 4.3 Restore to a new RDS instance

**Do not overwrite or delete the original database during recovery.** Restore to a new instance, validate the recovered data, and plan the cutover.

#### Option A: Point-in-time recovery

Use this when recovering to a known time before accidental deletion, corruption, or a faulty migration, provided that the required recovery point is within the available recovery window.

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier "$DB_ID" \
  --target-db-instance-identifier taskflow-db-restore \
  --restore-time <recovery-time-UTC> \
  --db-subnet-group-name <db-subnet-group> \
  --vpc-security-group-ids <db-security-group-id> \
  --no-publicly-accessible
```

Use a valid UTC timestamp and confirm that the selected time is supported by RDS.

#### Option B: Restore from a manual snapshot

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier taskflow-db-restore \
  --db-snapshot-identifier <snapshot-id> \
  --db-subnet-group-name <db-subnet-group> \
  --vpc-security-group-ids <db-security-group-id> \
  --no-publicly-accessible
```

Check the actual database engine, subnet configuration, encryption requirements, and security group before executing either command.

Wait for the restored instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier taskflow-db-restore
```

Retrieve the new endpoint:

```bash
aws rds describe-db-instances \
  --db-instance-identifier taskflow-db-restore \
  --query 'DBInstances[0].{
    status:DBInstanceStatus,
    endpoint:Endpoint.Address,
    port:Endpoint.Port
  }'
```

### 4.4 Validate and cut over

1. Connect through an approved private access path.
2. Confirm that the database is accessible and the expected schema exists.
3. Validate critical records, row counts, and application-level consistency.
4. Determine whether the incident requires a full cutover or selective data recovery.
5. Obtain approval before redirecting production traffic.
6. Update the database connection secret or parameter using the approved configuration-management workflow.
7. Restart or redeploy application tasks if required to reload the database configuration.
8. Run application smoke tests and monitor errors, database connections, and latency.
9. Keep the original database and relevant snapshots until the recovery is validated and the retention decision is approved.

**Important:** Restoring an RDS instance does not automatically update the application endpoint. Do not assume that an ECS deployment reloads secrets unless the task configuration and application support that behavior.

If Terraform manages the database, reconcile the restored resource with the infrastructure configuration before making subsequent changes. Avoid an unreviewed `terraform apply` that could replace or destroy recovery resources.

### 4.5 Backup and restore verification

Perform periodic restore drills in a non-production environment.

Record:

- Snapshot or recovery-point identifier.
- Restore start and completion times.
- Data validation results.
- Application reconnection results.
- Actual recovery time and recoverable data-loss window.
- Any permissions, networking, or configuration issues discovered.

A successful snapshot operation alone does not prove that the application can be recovered.

---

## 5. Escalation and incident closure

Escalate immediately when there is a full outage, suspected data loss, a security incident, or a recovery action that could cause irreversible changes.

For each incident, record:

- Start time and user impact.
- Symptoms and relevant alarms.
- Deployment or infrastructure changes preceding the incident.
- Commands executed and changes made.
- Recovery and verification results.
- Root cause, if known.
- Follow-up actions and the owner responsible.

Update this runbook whenever a real incident reveals missing or incorrect instructions.

**Final operational principle:** Restore service safely, verify recovery, preserve evidence, and fix the underlying cause through the version-controlled infrastructure and deployment workflow.