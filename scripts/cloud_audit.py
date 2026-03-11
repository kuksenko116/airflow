#!/usr/bin/env python3
"""
Cloud Resource Audit & Cleanup Tool

Scans AWS and GCP for active resources using CLI credentials.
Organizes by: Organization -> Project/Account -> Tags -> Resources
Shows estimated costs and allows interactive selection for destruction.

Usage:
    python3 scripts/cloud_audit.py                # Scan both providers
    python3 scripts/cloud_audit.py --gcp          # GCP only
    python3 scripts/cloud_audit.py --aws          # AWS only
    python3 scripts/cloud_audit.py --destroy      # Enable destroy mode
    python3 scripts/cloud_audit.py --json         # Output as JSON
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Optional

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, Prompt
from rich.table import Table
from rich.tree import Tree

console = Console()


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------
@dataclass
class Resource:
    provider: str  # "gcp" or "aws"
    org: str
    project: str  # GCP project ID or AWS account ID
    resource_type: str  # e.g. "Compute Instance", "EC2 Instance"
    resource_id: str
    name: str
    location: str  # region/zone
    tags: dict = field(default_factory=dict)
    monthly_cost: Optional[float] = None  # estimated or actual
    status: str = "ACTIVE"
    details: str = ""  # extra info (machine type, size, etc.)
    delete_cmd: str = ""  # CLI command to destroy this resource

    @property
    def display_name(self):
        return self.name or self.resource_id

    @property
    def cost_str(self):
        if self.monthly_cost is None:
            return ""
        if self.monthly_cost == 0:
            return "free tier"
        return f"~${self.monthly_cost:,.2f}/mo"


# ---------------------------------------------------------------------------
# CLI runner
# ---------------------------------------------------------------------------
def run_cmd(cmd: str, timeout: int = 60) -> tuple[bool, str]:
    """Run a shell command and return (success, output)."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode == 0:
            return True, result.stdout.strip()
        return False, result.stderr.strip()
    except subprocess.TimeoutExpired:
        return False, "Command timed out"
    except Exception as e:
        return False, str(e)


def run_json(cmd: str, timeout: int = 60) -> tuple[bool, list | dict]:
    """Run a CLI command expecting JSON output."""
    ok, output = run_cmd(cmd, timeout)
    if not ok:
        return False, output
    if not output:
        return True, []
    try:
        return True, json.loads(output)
    except json.JSONDecodeError:
        return False, f"Invalid JSON: {output[:200]}"


def cli_available(name: str) -> bool:
    ok, _ = run_cmd(f"which {name}")
    return ok


# ---------------------------------------------------------------------------
# GCP Scanner
# ---------------------------------------------------------------------------
# Maps resource type -> (list command template, name field, location field,
#                        delete command template, monthly cost estimate)
GCP_RESOURCE_SCANNERS = {
    "Compute Instance": {
        "list": "gcloud compute instances list --project={project} --format=json",
        "name": "name",
        "location": "zone",
        "status": "status",
        "details": "machineType",
        "delete": "gcloud compute instances delete {name} --zone={location} --project={project} --quiet",
        "cost": 25.00,
    },
    "GKE Cluster": {
        "list": "gcloud container clusters list --project={project} --format=json",
        "name": "name",
        "location": "location",
        "status": "status",
        "details": "currentNodeCount",
        "delete": "gcloud container clusters delete {name} --location={location} --project={project} --quiet",
        "cost": 73.00,
    },
    "Cloud SQL Instance": {
        "list": "gcloud sql instances list --project={project} --format=json",
        "name": "name",
        "location": "region",
        "status": "state",
        "details": "databaseVersion",
        "delete": "gcloud sql instances delete {name} --project={project} --quiet",
        "cost": 25.00,
    },
    "Composer Environment": {
        "list": "gcloud composer environments list --project={project} --locations=- --format=json",
        "name": "name",
        "location": "location",
        "status": "state",
        "details": "",
        "delete": "gcloud composer environments delete {name} --location={location} --project={project} --quiet",
        "cost": 250.00,
    },
    "Cloud Function": {
        "list": "gcloud functions list --project={project} --format=json",
        "name": "name",
        "location": "region",
        "status": "status",
        "details": "runtime",
        "delete": "gcloud functions delete {name} --region={location} --project={project} --quiet",
        "cost": 0.00,
    },
    "Cloud Run Service": {
        "list": "gcloud run services list --project={project} --format=json",
        "name": "metadata.name",
        "location": "metadata.labels.cloud\\.googleapis\\.com/location",
        "status": "",
        "details": "",
        "delete": "gcloud run services delete {name} --region={location} --project={project} --quiet",
        "cost": 0.00,
    },
    "BigQuery Dataset": {
        "list": "bq ls --project_id={project} --format=json",
        "name": "datasetReference.datasetId",
        "location": "location",
        "status": "",
        "details": "",
        "delete": "bq rm -r -f {project}:{name}",
        "cost": 0.00,
    },
    "GCS Bucket": {
        "list": "gcloud storage buckets list --project={project} --format=json",
        "name": "name",
        "location": "location",
        "status": "",
        "details": "storageClass",
        "delete": "gcloud storage rm -r gs://{name} --project={project}",
        "cost": 0.00,
    },
}


def get_nested(obj: dict, path: str, default=""):
    """Get a nested dict value by dot-separated path."""
    parts = path.replace("\\.", "__DOT__").split(".")
    current = obj
    for part in parts:
        part = part.replace("__DOT__", ".")
        if isinstance(current, dict):
            current = current.get(part, default)
        else:
            return default
    return current or default


def extract_short_location(location_str: str) -> str:
    """Extract clean location from full GCP resource URLs."""
    if "/" in location_str:
        # e.g., "projects/xxx/zones/us-central1-a" -> "us-central1-a"
        parts = location_str.split("/")
        return parts[-1]
    return location_str


def extract_machine_type(details_str: str) -> str:
    """Extract machine type name from full URL."""
    if "/" in str(details_str):
        return str(details_str).split("/")[-1]
    return str(details_str)


def scan_gcp() -> list[Resource]:
    """Scan all GCP projects for resources."""
    resources = []

    console.print("\n[bold cyan]Scanning GCP...[/]")

    # Get organization info
    ok, orgs = run_json("gcloud organizations list --format=json")
    org_name = "No Organization"
    if ok and orgs:
        org_name = orgs[0].get("displayName", orgs[0].get("name", "Unknown"))

    # List all active projects
    ok, projects = run_json(
        "gcloud projects list --filter=lifecycleState:ACTIVE --format=json"
    )
    if not ok:
        console.print(f"  [red]Failed to list projects: {projects}[/]")
        return resources

    console.print(f"  Found [bold]{len(projects)}[/] active projects")

    for proj in projects:
        project_id = proj["projectId"]
        project_name = proj.get("name", project_id)
        console.print(f"  Scanning [cyan]{project_id}[/] ({project_name})...")

        # Check billing
        ok, billing_out = run_cmd(
            f"gcloud billing projects describe {project_id} "
            f"--format='value(billingAccountName)'"
        )
        has_billing = ok and billing_out.strip() != ""

        # Scan each resource type
        for rtype, scanner in GCP_RESOURCE_SCANNERS.items():
            list_cmd = scanner["list"].format(project=project_id)
            ok, items = run_json(list_cmd, timeout=30)

            if not ok or not items:
                continue

            # Handle bq ls returning different format
            if isinstance(items, dict):
                items = items.get("datasets", items.get("items", [items]))
            if not isinstance(items, list):
                items = [items]

            for item in items:
                name = get_nested(item, scanner["name"])
                location = get_nested(item, scanner["location"], "global")
                location = extract_short_location(str(location))
                status = get_nested(item, scanner["status"], "ACTIVE") if scanner["status"] else "ACTIVE"
                details = get_nested(item, scanner["details"], "") if scanner["details"] else ""
                details = extract_machine_type(details)

                # Extract labels/tags from GCP resource
                tags = {}
                for label_key in ["labels", "metadata.labels", "resourceLabels"]:
                    labels = get_nested(item, label_key)
                    if isinstance(labels, dict):
                        tags.update(labels)
                        break

                cost = scanner["cost"] if has_billing else 0.0

                delete_cmd = scanner["delete"].format(
                    name=name, location=location, project=project_id
                )

                resources.append(Resource(
                    provider="gcp",
                    org=org_name,
                    project=project_id,
                    resource_type=rtype,
                    resource_id=f"{project_id}/{rtype}/{name}",
                    name=str(name),
                    location=str(location),
                    tags=tags,
                    monthly_cost=cost,
                    status=str(status).upper(),
                    details=str(details),
                    delete_cmd=delete_cmd,
                ))

    console.print(f"  [green]Found {len(resources)} GCP resources[/]")
    return resources


# ---------------------------------------------------------------------------
# AWS Scanner
# ---------------------------------------------------------------------------
AWS_RESOURCE_SCANNERS = {
    "EC2 Instance": {
        "list": (
            "aws ec2 describe-instances --region {region} "
            "--query 'Reservations[].Instances[]' --output json"
        ),
        "name_tag": "Name",
        "id": "InstanceId",
        "status": "State.Name",
        "details": "InstanceType",
        "delete": "aws ec2 terminate-instances --instance-ids {id} --region {region}",
        "cost_map": {
            "t2.micro": 8.47, "t2.small": 16.94, "t2.medium": 33.87,
            "t3.micro": 7.59, "t3.small": 15.18, "t3.medium": 30.37,
            "t3.large": 60.74, "m5.large": 70.08, "m5.xlarge": 140.16,
            "default": 30.00,
        },
    },
    "RDS Instance": {
        "list": (
            "aws rds describe-db-instances --region {region} "
            "--query 'DBInstances' --output json"
        ),
        "name_tag": "",
        "id": "DBInstanceIdentifier",
        "status": "DBInstanceStatus",
        "details": "DBInstanceClass",
        "delete": (
            "aws rds delete-db-instance --db-instance-identifier {id} "
            "--skip-final-snapshot --region {region}"
        ),
        "cost_map": {
            "db.t3.micro": 12.41, "db.t3.small": 24.82,
            "db.t3.medium": 49.64, "db.r5.large": 175.20,
            "default": 50.00,
        },
    },
    "ECS Cluster": {
        "list": (
            "aws ecs describe-clusters --region {region} "
            "--clusters $(aws ecs list-clusters --region {region} "
            "--query 'clusterArns' --output text) "
            "--query 'clusters' --output json 2>/dev/null"
        ),
        "name_tag": "",
        "id": "clusterName",
        "status": "status",
        "details": "registeredContainerInstancesCount",
        "delete": "aws ecs delete-cluster --cluster {id} --region {region}",
        "cost_map": {"default": 0.00},
    },
    "EKS Cluster": {
        "list": (
            "aws eks list-clusters --region {region} --output json "
            "--query 'clusters'"
        ),
        "name_tag": "",
        "id": "",
        "status": "",
        "details": "",
        "delete": "aws eks delete-cluster --name {id} --region {region}",
        "cost_map": {"default": 73.00},
    },
    "Lambda Function": {
        "list": (
            "aws lambda list-functions --region {region} "
            "--query 'Functions' --output json"
        ),
        "name_tag": "",
        "id": "FunctionName",
        "status": "State",
        "details": "Runtime",
        "delete": "aws lambda delete-function --function-name {id} --region {region}",
        "cost_map": {"default": 0.00},
    },
    "S3 Bucket": {
        "list": "aws s3api list-buckets --query 'Buckets' --output json",
        "name_tag": "",
        "id": "Name",
        "status": "",
        "details": "",
        "delete": "aws s3 rb s3://{id} --force",
        "cost_map": {"default": 0.00},
        "global": True,
    },
    "RDS Cluster": {
        "list": (
            "aws rds describe-db-clusters --region {region} "
            "--query 'DBClusters' --output json"
        ),
        "name_tag": "",
        "id": "DBClusterIdentifier",
        "status": "Status",
        "details": "Engine",
        "delete": (
            "aws rds delete-db-cluster --db-cluster-identifier {id} "
            "--skip-final-snapshot --region {region}"
        ),
        "cost_map": {"default": 75.00},
    },
    "ElastiCache Cluster": {
        "list": (
            "aws elasticache describe-cache-clusters --region {region} "
            "--query 'CacheClusters' --output json"
        ),
        "name_tag": "",
        "id": "CacheClusterId",
        "status": "CacheClusterStatus",
        "details": "CacheNodeType",
        "delete": (
            "aws elasticache delete-cache-cluster "
            "--cache-cluster-id {id} --region {region}"
        ),
        "cost_map": {
            "cache.t3.micro": 11.52, "cache.t3.small": 23.04,
            "default": 25.00,
        },
    },
    "DynamoDB Table": {
        "list": (
            "aws dynamodb list-tables --region {region} "
            "--query 'TableNames' --output json"
        ),
        "name_tag": "",
        "id": "",
        "status": "",
        "details": "",
        "delete": "aws dynamodb delete-table --table-name {id} --region {region}",
        "cost_map": {"default": 0.00},
    },
}


def get_aws_tags(item: dict) -> dict:
    """Extract tags from an AWS resource (handles Tags list format)."""
    tags = {}
    tag_list = item.get("Tags", item.get("TagList", []))
    if isinstance(tag_list, list):
        for t in tag_list:
            key = t.get("Key", t.get("key", ""))
            val = t.get("Value", t.get("value", ""))
            if key:
                tags[key] = val
    return tags


def scan_aws() -> list[Resource]:
    """Scan AWS account for resources."""
    resources = []

    console.print("\n[bold yellow]Scanning AWS...[/]")

    # Get account info
    ok, identity = run_json("aws sts get-caller-identity --output json")
    if not ok:
        console.print(f"  [red]AWS not configured or not authenticated: {identity}[/]")
        return resources

    account_id = identity.get("Account", "unknown")

    # Get configured region
    ok, region_out = run_cmd("aws configure get region")
    default_region = region_out.strip() if ok and region_out.strip() else "us-east-1"

    console.print(f"  Account: [bold]{account_id}[/], Region: [bold]{default_region}[/]")

    # Get AWS organization info
    ok, org_info = run_json("aws organizations describe-organization --output json")
    org_name = "No Organization"
    if ok and isinstance(org_info, dict):
        org_data = org_info.get("Organization", org_info)
        org_name = org_data.get("Id", "AWS Org")

    # Scan additional regions where resources are common
    regions_to_scan = [default_region]
    ok, all_regions = run_json(
        "aws ec2 describe-regions --query 'Regions[].RegionName' --output json"
    )

    # Track S3 (global) scanned once
    s3_scanned = False

    for region in regions_to_scan:
        for rtype, scanner in AWS_RESOURCE_SCANNERS.items():
            # S3 is global, only scan once
            if scanner.get("global") and s3_scanned:
                continue

            list_cmd = scanner["list"].format(region=region)
            ok, items = run_json(list_cmd, timeout=30)

            if scanner.get("global"):
                s3_scanned = True

            if not ok or not items:
                continue

            if not isinstance(items, list):
                items = [items]

            for item in items:
                # Handle simple string lists (EKS clusters, DynamoDB tables)
                if isinstance(item, str):
                    item = {scanner["id"] or "name": item}

                res_id = get_nested(item, scanner["id"]) if scanner["id"] else str(item)
                if isinstance(res_id, dict):
                    res_id = str(res_id)

                status = get_nested(item, scanner["status"], "active") if scanner["status"] else "active"
                details = get_nested(item, scanner["details"], "") if scanner["details"] else ""

                # Get name from Name tag or ID
                tags = get_aws_tags(item)
                name = tags.get("Name", tags.get("name", str(res_id)))

                # Cost estimate based on instance type / details
                cost_map = scanner.get("cost_map", {})
                cost = cost_map.get(str(details), cost_map.get("default", 0.0))

                delete_cmd = scanner["delete"].format(id=res_id, region=region)

                resources.append(Resource(
                    provider="aws",
                    org=org_name,
                    project=account_id,
                    resource_type=rtype,
                    resource_id=f"{account_id}/{region}/{rtype}/{res_id}",
                    name=str(name),
                    location=region if not scanner.get("global") else "global",
                    tags=tags,
                    monthly_cost=cost,
                    status=str(status).upper() if status else "ACTIVE",
                    details=str(details),
                    delete_cmd=delete_cmd,
                ))

    # Fetch actual AWS costs from Cost Explorer
    resources = enrich_aws_costs(resources, account_id)

    console.print(f"  [green]Found {len(resources)} AWS resources[/]")
    return resources


def enrich_aws_costs(resources: list[Resource], account_id: str) -> list[Resource]:
    """Try to get actual costs from AWS Cost Explorer."""
    end_date = datetime.now().strftime("%Y-%m-%d")
    start_date = (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d")

    ok, cost_data = run_json(
        f"aws ce get-cost-and-usage "
        f"--time-period Start={start_date},End={end_date} "
        f"--granularity MONTHLY "
        f"--metrics BlendedCost "
        f"--group-by Type=DIMENSION,Key=SERVICE "
        f"--output json",
        timeout=30,
    )

    if not ok or not isinstance(cost_data, dict):
        return resources

    # Build a service -> cost mapping
    service_costs = {}
    for period in cost_data.get("ResultsByTime", []):
        for group in period.get("Groups", []):
            service = group["Keys"][0]
            amount = float(group["Metrics"]["BlendedCost"]["Amount"])
            service_costs[service] = service_costs.get(service, 0) + amount

    # Map AWS service names to our resource types
    service_to_type = {
        "Amazon Elastic Compute Cloud - Compute": "EC2 Instance",
        "Amazon Relational Database Service": "RDS Instance",
        "Amazon Simple Storage Service": "S3 Bucket",
        "AWS Lambda": "Lambda Function",
        "Amazon ElastiCache": "ElastiCache Cluster",
        "Amazon DynamoDB": "DynamoDB Table",
        "Amazon Elastic Container Service": "ECS Cluster",
        "Amazon Elastic Kubernetes Service": "EKS Cluster",
    }

    # Distribute service cost across resources of that type
    type_counts = {}
    for r in resources:
        if r.provider == "aws":
            type_counts[r.resource_type] = type_counts.get(r.resource_type, 0) + 1

    for service_name, cost in service_costs.items():
        rtype = service_to_type.get(service_name)
        if rtype and rtype in type_counts and type_counts[rtype] > 0:
            per_resource = cost / type_counts[rtype]
            for r in resources:
                if r.provider == "aws" and r.resource_type == rtype:
                    r.monthly_cost = round(per_resource, 2)

    return resources


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------
def build_resource_tree(
    resources: list[Resource],
) -> tuple[Tree, dict[int, Resource]]:
    """Build a rich Tree organized by provider -> org -> project -> tags -> resources.

    Returns the tree and a mapping of display number -> Resource.
    """
    tree = Tree("[bold]Cloud Resource Audit[/]")
    numbered = {}
    counter = 1

    # Group: provider -> org -> project -> tag_group -> resources
    providers = {}
    for r in resources:
        providers.setdefault(r.provider, {})
        providers[r.provider].setdefault(r.org, {})
        providers[r.provider][r.org].setdefault(r.project, [])
        providers[r.provider][r.org][r.project].append(r)

    provider_labels = {"gcp": "[bold cyan]Google Cloud Platform[/]", "aws": "[bold yellow]Amazon Web Services[/]"}

    for provider in ["gcp", "aws"]:
        if provider not in providers:
            continue

        p_branch = tree.add(provider_labels[provider])

        for org_name, projects in providers[provider].items():
            o_branch = p_branch.add(f"[bold]Org:[/] {org_name}")

            for project_id, proj_resources in projects.items():
                # Calculate project total cost
                proj_cost = sum(r.monthly_cost or 0 for r in proj_resources)
                cost_label = f" [red]${proj_cost:,.2f}/mo[/]" if proj_cost > 0 else ""
                pj_branch = o_branch.add(
                    f"[bold]Project:[/] {project_id}{cost_label} "
                    f"[dim]({len(proj_resources)} resources)[/]"
                )

                # Group by tags
                tagged = {}    # tag_str -> [resources]
                untagged = []
                for r in proj_resources:
                    if r.tags:
                        # Use first meaningful tag as group key
                        tag_str = ", ".join(f"{k}={v}" for k, v in sorted(r.tags.items()))
                        tagged.setdefault(tag_str, []).append(r)
                    else:
                        untagged.append(r)

                # Display tagged groups
                for tag_str, tag_resources in sorted(tagged.items()):
                    tag_cost = sum(r.monthly_cost or 0 for r in tag_resources)
                    cost_label = f" [red]${tag_cost:,.2f}/mo[/]" if tag_cost > 0 else ""
                    t_branch = pj_branch.add(
                        f"[green]Tags:[/] {tag_str}{cost_label}"
                    )
                    for r in sorted(tag_resources, key=lambda x: x.resource_type):
                        numbered[counter] = r
                        t_branch.add(_format_resource(counter, r))
                        counter += 1

                # Display untagged
                if untagged:
                    u_cost = sum(r.monthly_cost or 0 for r in untagged)
                    cost_label = f" [red]${u_cost:,.2f}/mo[/]" if u_cost > 0 else ""
                    u_branch = pj_branch.add(
                        f"[dim]Untagged{cost_label}[/]"
                    )
                    for r in sorted(untagged, key=lambda x: x.resource_type):
                        numbered[counter] = r
                        u_branch.add(_format_resource(counter, r))
                        counter += 1

    return tree, numbered


def _format_resource(num: int, r: Resource) -> str:
    """Format a single resource line for the tree."""
    cost = f" [red]{r.cost_str}[/]" if r.cost_str else ""
    status_color = "green" if r.status in ("ACTIVE", "RUNNING") else "yellow"
    details = f" ({r.details})" if r.details else ""
    location = f" [{r.location}]" if r.location else ""

    return (
        f"[bold white]\\[{num}][/] "
        f"{r.resource_type}: [bold]{r.display_name}[/]"
        f"{details}{location} "
        f"[{status_color}]{r.status}[/]"
        f"{cost}"
    )


def show_cost_summary(resources: list[Resource]):
    """Show a cost summary table by provider and project."""
    table = Table(title="Cost Summary (Estimated Monthly)", show_lines=True)
    table.add_column("Provider", style="bold")
    table.add_column("Project", style="cyan")
    table.add_column("Resources", justify="right")
    table.add_column("Est. Monthly Cost", justify="right", style="red")

    # Group by provider + project
    groups = {}
    for r in resources:
        key = (r.provider.upper(), r.project)
        if key not in groups:
            groups[key] = {"count": 0, "cost": 0.0}
        groups[key]["count"] += 1
        groups[key]["cost"] += r.monthly_cost or 0

    total_cost = 0.0
    for (provider, project), data in sorted(groups.items()):
        table.add_row(
            provider, project,
            str(data["count"]),
            f"${data['cost']:,.2f}",
        )
        total_cost += data["cost"]

    table.add_row(
        "[bold]TOTAL[/]", "", "",
        f"[bold]${total_cost:,.2f}[/]",
    )
    console.print(table)


# ---------------------------------------------------------------------------
# Interactive selection & destruction
# ---------------------------------------------------------------------------
def parse_selection(selection: str, max_num: int) -> set[int]:
    """Parse user selection string like '1,3-5,8' into a set of numbers."""
    selected = set()
    if not selection.strip():
        return selected

    if selection.strip().lower() == "all":
        return set(range(1, max_num + 1))

    for part in selection.split(","):
        part = part.strip()
        if "-" in part:
            try:
                start, end = part.split("-", 1)
                for i in range(int(start.strip()), int(end.strip()) + 1):
                    if 1 <= i <= max_num:
                        selected.add(i)
            except ValueError:
                console.print(f"  [red]Invalid range: {part}[/]")
        else:
            try:
                n = int(part)
                if 1 <= n <= max_num:
                    selected.add(n)
            except ValueError:
                console.print(f"  [red]Invalid number: {part}[/]")

    return selected


def confirm_and_destroy(selected: dict[int, Resource]):
    """Show destruction plan and execute if confirmed."""
    if not selected:
        console.print("[yellow]No resources selected for destruction.[/]")
        return

    # Show destruction plan
    console.print("\n[bold red]DESTRUCTION PLAN[/]")
    table = Table(show_lines=True)
    table.add_column("#", style="bold", justify="right")
    table.add_column("Provider")
    table.add_column("Project")
    table.add_column("Resource")
    table.add_column("Name", style="bold")
    table.add_column("Location")
    table.add_column("Est. Cost", justify="right", style="red")

    total_savings = 0.0
    for num in sorted(selected.keys()):
        r = selected[num]
        table.add_row(
            str(num),
            r.provider.upper(),
            r.project,
            r.resource_type,
            r.display_name,
            r.location,
            r.cost_str or "-",
        )
        total_savings += r.monthly_cost or 0

    console.print(table)
    console.print(
        f"\n[bold]Total resources to destroy:[/] {len(selected)}"
        f"\n[bold]Estimated monthly savings:[/] [green]${total_savings:,.2f}/mo[/]"
    )

    # Show the actual commands that will run
    console.print("\n[bold]Commands that will execute:[/]")
    for num in sorted(selected.keys()):
        r = selected[num]
        console.print(f"  [dim]{r.delete_cmd}[/]")

    console.print()
    if not Confirm.ask(
        "[bold red]Are you sure you want to destroy these resources?[/]",
        default=False,
    ):
        console.print("[yellow]Aborted. No resources were destroyed.[/]")
        return

    # Double confirmation for safety
    confirm_text = Prompt.ask(
        "[bold red]Type 'destroy' to confirm[/]"
    )
    if confirm_text != "destroy":
        console.print("[yellow]Aborted. No resources were destroyed.[/]")
        return

    # Execute destruction
    console.print("\n[bold red]Destroying resources...[/]\n")
    for num in sorted(selected.keys()):
        r = selected[num]
        console.print(f"  Destroying [{num}] {r.resource_type}: {r.display_name}...", end=" ")
        ok, output = run_cmd(r.delete_cmd, timeout=300)
        if ok:
            console.print("[green]DONE[/]")
        else:
            console.print(f"[red]FAILED[/]: {output[:100]}")

    console.print("\n[bold green]Destruction complete.[/]")


def export_json(resources: list[Resource], numbered: dict[int, Resource]):
    """Export resource inventory as JSON."""
    output = []
    for num, r in sorted(numbered.items()):
        output.append({
            "number": num,
            "provider": r.provider,
            "org": r.org,
            "project": r.project,
            "resource_type": r.resource_type,
            "resource_id": r.resource_id,
            "name": r.name,
            "location": r.location,
            "tags": r.tags,
            "monthly_cost": r.monthly_cost,
            "status": r.status,
            "details": r.details,
            "delete_cmd": r.delete_cmd,
        })
    print(json.dumps(output, indent=2))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Cloud Resource Audit & Cleanup Tool"
    )
    parser.add_argument("--gcp", action="store_true", help="Scan GCP only")
    parser.add_argument("--aws", action="store_true", help="Scan AWS only")
    parser.add_argument(
        "--destroy", action="store_true",
        help="Enable interactive destroy mode"
    )
    parser.add_argument(
        "--json", action="store_true", dest="json_output",
        help="Output as JSON instead of interactive display"
    )
    args = parser.parse_args()

    # Default to scanning both if neither flag is set
    scan_gcp_flag = args.gcp or (not args.gcp and not args.aws)
    scan_aws_flag = args.aws or (not args.gcp and not args.aws)

    console.print(Panel(
        "[bold]Cloud Resource Audit & Cleanup Tool[/]\n"
        "Scanning your cloud infrastructure...",
        border_style="blue",
    ))

    # Check CLI availability
    all_resources = []

    if scan_gcp_flag:
        if cli_available("gcloud"):
            all_resources.extend(scan_gcp())
        else:
            console.print("[yellow]gcloud CLI not found, skipping GCP[/]")

    if scan_aws_flag:
        if cli_available("aws"):
            all_resources.extend(scan_aws())
        else:
            console.print("[yellow]aws CLI not found, skipping AWS[/]")

    if not all_resources:
        console.print("\n[bold yellow]No resources found across any provider.[/]")
        return

    # Build display tree
    tree, numbered = build_resource_tree(all_resources)

    # JSON output mode
    if args.json_output:
        export_json(all_resources, numbered)
        return

    # Display tree
    console.print()
    console.print(tree)
    console.print()

    # Cost summary
    show_cost_summary(all_resources)

    # Interactive destroy mode
    if args.destroy:
        console.print(
            "\n[bold]Enter resource numbers to destroy[/] "
            "(comma-separated, ranges like 1-5, or 'all'):"
        )
        selection = Prompt.ask("[bold red]Destroy[/]", default="")
        selected_nums = parse_selection(selection, len(numbered))

        if selected_nums:
            selected_resources = {
                n: numbered[n] for n in selected_nums if n in numbered
            }
            confirm_and_destroy(selected_resources)
        else:
            console.print("[yellow]No resources selected.[/]")
    else:
        console.print(
            "\n[dim]Run with --destroy to interactively select resources "
            "for deletion.[/]"
        )


if __name__ == "__main__":
    main()
