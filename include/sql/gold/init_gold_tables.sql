-- Create all gold star-schema tables if they do not yet exist.
-- Run this before any MERGE statements.

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.dim_date` (
  date_key     INT64   NOT NULL,
  full_date    DATE    NOT NULL,
  year         INT64,
  quarter      INT64,
  month        INT64,
  month_name   STRING,
  week_of_year INT64,
  day_of_week  INT64,
  day_name     STRING,
  day_of_year  INT64
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.dim_county` (
  county_key  INT64  NOT NULL,
  county_name STRING NOT NULL,
  population  INT64
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.dim_season` (
  season_key  INT64  NOT NULL,
  season_name STRING NOT NULL
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.dim_region` (
  region_key  INT64  NOT NULL,
  rpho_region STRING NOT NULL
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.dim_age_group` (
  age_group_key   INT64  NOT NULL,
  age_group_label STRING NOT NULL
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.fact_covid_vaccination_summary` (
  date_key                     INT64 NOT NULL,
  county_key                   INT64 NOT NULL,
  total_doses                  INT64,
  cumulative_total_doses       INT64,
  partially_vaccinated         INT64,
  total_partially_vaccinated   INT64,
  fully_vaccinated             INT64,
  cumulative_fully_vaccinated  INT64,
  at_least_one_dose            INT64,
  cumulative_at_least_one_dose INT64,
  california_flag              BOOL,
  up_to_date_count             INT64,
  cumulative_up_to_date_count  INT64
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.fact_respiratory_metrics` (
  date_key              INT64 NOT NULL,
  region_key            INT64 NOT NULL,
  age_group_key         INT64 NOT NULL,
  season_key            INT64 NOT NULL,
  cov_positives         INT64,
  cov_total_tests       INT64,
  cov_tp                FLOAT64,
  cov_tp_level          STRING,
  flu_positives         INT64,
  flu_total_tests       INT64,
  flu_tp                FLOAT64,
  flu_tp_level          STRING,
  rsv_positives         INT64,
  rsv_total_tests       INT64,
  rsv_tp                FLOAT64,
  rsv_tp_level          STRING,
  cov_ed_visits         INT64,
  flu_ed_visits         INT64,
  rsv_ed_visits         INT64,
  population            INT64,
  cov_adm               INT64,
  flu_adm               INT64,
  rsv_adm               INT64,
  cov_adm_rate          FLOAT64,
  flu_adm_rate          FLOAT64,
  rsv_adm_rate          FLOAT64,
  cov_adm_level         STRING,
  flu_adm_level         STRING,
  rsv_adm_level         STRING,
  total_deaths          INT64,
  cov_deaths            INT64,
  flu_deaths            INT64,
  rsv_deaths            INT64,
  cov_deaths_per        FLOAT64,
  flu_deaths_per        FLOAT64,
  rsv_deaths_per        FLOAT64,
  season_cov_ped_deaths INT64,
  season_flu_ped_deaths INT64,
  season_rsv_ped_deaths INT64,
  flu_a_tests           INT64,
  flu_b_tests           INT64
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.revoked_medicare_providers_by_state` (
  state_cd                STRING NOT NULL,
  total_revocations       INT64,
  active_revocations      INT64,
  reenrollment_eligible   INT64,
  distinct_provider_types INT64,
  most_common_reason      STRING,
  earliest_revocation     DATE,
  latest_revocation       DATE,
  _gold_built_at          TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `{{ var.value.gcp_project_id }}.gold.revoked_medicare_providers_trends` (
  revocation_year          INT64  NOT NULL,
  revocation_reason        STRING NOT NULL,
  revocation_count         INT64,
  reenrollment_eligible    INT64,
  reenrollment_rate        FLOAT64,
  distinct_states          INT64,
  _gold_built_at           TIMESTAMP
);
