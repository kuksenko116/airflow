# Airflow + BigQuery Demo (CHHS Public Data)

A demo project that ingests two California Health & Human Services (CHHS) public datasets into BigQuery using a **medallion architecture** (bronze -> silver -> gold). Infrastructure is deployed via Terraform to a new GCP project running Cloud Composer 3.

## Architecture

```
CHHS CKAN API ──> Cloud Composer 3 (Airflow) ──> BigQuery
                        │                           │
                   Bronze (raw)  ─>  Silver (typed)  ─>  Gold (aggregated)
```

### Datasets

| Dataset | Rows | Schedule | Source |
|---------|------|----------|--------|
| Respiratory Virus Dashboard | ~3,924 | Weekly (Mon 06:00 UTC) | [CHHS](https://data.chhs.ca.gov/dataset/respiratory-virus-dashboard) |
| COVID-19 Vaccines by County | ~34,596 | Daily (07:00 UTC) | [CHHS](https://data.chhs.ca.gov/dataset/vaccine-progress-dashboard) |

### BigQuery Tables

| Layer | Table | Description |
|-------|-------|-------------|
| bronze | `chhs_respiratory_virus_raw` | Raw API response, all STRING columns |
| bronze | `chhs_covid_vaccines_raw` | Raw API response, all STRING columns |
| silver | `respiratory_virus` | Typed, deduped respiratory data |
| silver | `covid_vaccines_by_county` | Typed, deduped vaccine data |
| gold | `respiratory_virus_weekly_summary` | Statewide aggregates, positivity rates, severity |
| gold | `vaccination_coverage_by_county` | Latest snapshot per county with per-capita rates |
| gold | `vaccination_trends` | Daily trends with 7/14/30-day rolling averages |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud`)
- A GCP billing account and folder where you can create projects

## Deployment

### 1. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id, billing_account_id, and folder_id
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform apply
```

This creates: GCP project, APIs, VPC, service account, BigQuery datasets (bronze/silver/gold), and a Cloud Composer 3 environment. The Composer environment takes ~25-30 minutes.

### 3. Set Airflow Variable

```bash
PROJECT_ID=$(terraform output -raw project_id)

gcloud composer environments run chhs-demo \
  --location us-central1 \
  --project "$PROJECT_ID" \
  variables set -- gcp_project_id "$PROJECT_ID"
```

### 4. Upload DAGs and SQL

```bash
DAG_GCS=$(terraform output -raw composer_dag_gcs_prefix)
GCS_BUCKET=$(terraform output -raw gcs_bucket)

# Upload DAGs
gsutil -m rsync -r ../dags/ "$DAG_GCS/"

# Upload SQL templates
gsutil -m rsync -r ../include/ "$GCS_BUCKET/data/"
```

Note: Composer looks for included templates (like SQL files referenced via `{% include %}`) in the `data/` folder of the environment bucket.

### 5. Trigger Initial Load

DAGs are unpaused by default. You can trigger them manually from the Airflow UI:

```bash
AIRFLOW_URI=$(terraform output -raw airflow_uri)
echo "Open: $AIRFLOW_URI"
```

Or via the CLI:

```bash
gcloud composer environments run chhs-demo \
  --location us-central1 \
  --project "$PROJECT_ID" \
  dags trigger -- chhs_respiratory_virus_pipeline

gcloud composer environments run chhs-demo \
  --location us-central1 \
  --project "$PROJECT_ID" \
  dags trigger -- chhs_covid_vaccines_pipeline
```

## Verification

After the DAGs complete, verify row counts:

```sql
-- Run in BigQuery console or via bq CLI
SELECT 'bronze.chhs_respiratory_virus_raw' AS t, COUNT(*) AS rows FROM `<PROJECT>.bronze.chhs_respiratory_virus_raw`
UNION ALL SELECT 'bronze.chhs_covid_vaccines_raw', COUNT(*) FROM `<PROJECT>.bronze.chhs_covid_vaccines_raw`
UNION ALL SELECT 'silver.respiratory_virus', COUNT(*) FROM `<PROJECT>.silver.respiratory_virus`
UNION ALL SELECT 'silver.covid_vaccines_by_county', COUNT(*) FROM `<PROJECT>.silver.covid_vaccines_by_county`
UNION ALL SELECT 'gold.respiratory_virus_weekly_summary', COUNT(*) FROM `<PROJECT>.gold.respiratory_virus_weekly_summary`
UNION ALL SELECT 'gold.vaccination_coverage_by_county', COUNT(*) FROM `<PROJECT>.gold.vaccination_coverage_by_county`
UNION ALL SELECT 'gold.vaccination_trends', COUNT(*) FROM `<PROJECT>.gold.vaccination_trends`;
```

## Cleanup

```bash
cd terraform
terraform destroy
```

## Project Structure

```
├── dags/
│   ├── common/
│   │   ├── __init__.py
│   │   └── default_args.py          # Shared config (PROJECT_ID, DEFAULT_ARGS)
│   ├── chhs_respiratory_virus_pipeline.py
│   └── chhs_covid_vaccines_pipeline.py
├── include/
│   └── sql/
│       ├── silver/
│       │   ├── clean_respiratory_virus.sql
│       │   └── clean_covid_vaccines.sql
│       └── gold/
│           ├── respiratory_weekly_summary.sql
│           ├── vaccination_coverage.sql
│           └── vaccination_trends.sql
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── networking.tf
│   ├── iam.tf
│   ├── bigquery.tf
│   ├── composer.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── tests/
│   └── test_dag_loading.py
├── scripts/
│   └── cloud_audit.py               # Multi-cloud resource audit & cleanup tool
├── requirements.txt
├── README.md
└── .gitignore
```

## Cloud Audit Tool

A standalone utility for auditing and cleaning up resources across GCP and AWS. Scans using CLI credentials and organizes resources by:

**Org -> Project/Account -> Tags -> Resources**

Includes estimated monthly costs and interactive destruction.

```bash
python3 scripts/cloud_audit.py              # Scan both providers
python3 scripts/cloud_audit.py --gcp        # GCP only
python3 scripts/cloud_audit.py --aws        # AWS only
python3 scripts/cloud_audit.py --destroy    # Interactive destroy mode
python3 scripts/cloud_audit.py --json       # JSON export
```

Requires: `pip install rich`, `gcloud` CLI, and/or `aws` CLI.
