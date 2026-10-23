import os
import boto3

ecs = boto3.client("ecs")
CLUSTER = os.environ["ECS_CLUSTER"]
SERVICE = os.environ["ECS_SERVICE"]
MAX_CPU = int(os.environ.get("MAX_TASK_CPU", "512"))
MAX_MEMORY = int(os.environ.get("MAX_TASK_MEMORY", "1024"))

def lambda_handler(event, context):
    state = event.get("detail", {}).get("state", {}).get("value")
    if state and state != "ALARM": return {"status": "ignored"}
    response = ecs.describe_services(cluster=CLUSTER, services=[SERVICE])
    services = response.get("services", [])
    if not services or services[0].get("status") != "ACTIVE": raise RuntimeError("TaskFlow ECS service unavailable")
    task = ecs.describe_task_definition(taskDefinition=services[0]["taskDefinition"])["taskDefinition"]
    cpu, memory = int(task["cpu"]), int(task["memory"])
    if cpu >= MAX_CPU or memory >= MAX_MEMORY: return {"status": "limit_reached"}
    definition = {k:v for k,v in task.items() if k not in {"taskDefinitionArn","revision","status","requiresAttributes","compatibilities","registeredAt","registeredBy","deregisteredAt"}}
    new_cpu, new_memory = min(cpu*2,MAX_CPU), min(memory*2,MAX_MEMORY)
    definition["cpu"], definition["memory"] = str(new_cpu), str(new_memory)
    for container in definition.get("containerDefinitions", []): container["cpu"], container["memory"] = new_cpu, new_memory
    registered = ecs.register_task_definition(**definition)
    ecs.update_service(cluster=CLUSTER, service=SERVICE, taskDefinition=registered["taskDefinition"]["taskDefinitionArn"], forceNewDeployment=True)
    return {"status":"scaling_started","cpu":new_cpu,"memory":new_memory}
