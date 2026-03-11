-- Silver: Clean and type the Respiratory Virus Dashboard bronze data.
-- Dedup on (SEASON, AGE_GRP, RPHO_REGION, WEEKENDING).
-- Null handling matches NiFi pipeline: blank numerics default to 0.

WITH source AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY SEASON, AGE_GRP, RPHO_REGION, WEEKENDING
      ORDER BY _ingestion_timestamp DESC
    ) AS _rn
  FROM `{{ var.value.gcp_project_id }}.bronze.chhs_respiratory_virus_raw`
)

SELECT
  -- Dimensions
  SEASON                                                     AS season,
  AGE_GRP                                                    AS age_group,
  RPHO_REGION                                                AS rpho_region,
  PARSE_DATE('%m/%d/%Y', WEEKENDING)                         AS week_ending,
  SAFE_CAST(MMWR_WEEK AS INT64)                              AS mmwr_week,
  SAFE_CAST(MMWR_YEAR AS INT64)                              AS mmwr_year,

  -- COVID-19
  COALESCE(SAFE_CAST(COV_POSITIVES AS INT64), 0)             AS cov_positives,
  COALESCE(SAFE_CAST(COV_TOTAL_TESTS AS INT64), 0)           AS cov_total_tests,
  COALESCE(SAFE_CAST(COV_TP AS FLOAT64), 0)                  AS cov_tp,
  COALESCE(COV_TP_LEVEL, '')                                 AS cov_tp_level,
  COALESCE(SAFE_CAST(COV_ED_VISITS AS INT64), 0)             AS cov_ed_visits,
  COALESCE(SAFE_CAST(COV_ADM AS INT64), 0)                   AS cov_adm,
  COALESCE(SAFE_CAST(COV_ADM_RATE AS FLOAT64), 0)            AS cov_adm_rate,
  COALESCE(COV_ADM_LEVEL, '')                                AS cov_adm_level,
  COALESCE(SAFE_CAST(COV_DEATHS AS INT64), 0)                AS cov_deaths,
  COALESCE(SAFE_CAST(COV_DEATHS_PER AS FLOAT64), 0)          AS cov_deaths_per,

  -- Influenza
  COALESCE(SAFE_CAST(FLU_POSITIVES AS INT64), 0)             AS flu_positives,
  COALESCE(SAFE_CAST(FLU_TOTAL_TESTS AS INT64), 0)           AS flu_total_tests,
  COALESCE(SAFE_CAST(FLU_TP AS FLOAT64), 0)                  AS flu_tp,
  COALESCE(FLU_TP_LEVEL, '')                                 AS flu_tp_level,
  COALESCE(SAFE_CAST(FLU_A_TESTS AS INT64), 0)               AS flu_a_tests,
  COALESCE(SAFE_CAST(FLU_B_TESTS AS INT64), 0)               AS flu_b_tests,
  COALESCE(SAFE_CAST(FLU_ED_VISITS AS INT64), 0)             AS flu_ed_visits,
  COALESCE(SAFE_CAST(FLU_ADM AS INT64), 0)                   AS flu_adm,
  COALESCE(SAFE_CAST(FLU_ADM_RATE AS FLOAT64), 0)            AS flu_adm_rate,
  COALESCE(FLU_ADM_LEVEL, '')                                AS flu_adm_level,
  COALESCE(SAFE_CAST(FLU_DEATHS AS INT64), 0)                AS flu_deaths,
  COALESCE(SAFE_CAST(FLU_DEATHS_PER AS FLOAT64), 0)          AS flu_deaths_per,

  -- RSV
  COALESCE(SAFE_CAST(RSV_POSITIVES AS INT64), 0)             AS rsv_positives,
  COALESCE(SAFE_CAST(RSV_TOTAL_TESTS AS INT64), 0)           AS rsv_total_tests,
  COALESCE(SAFE_CAST(RSV_TP AS FLOAT64), 0)                  AS rsv_tp,
  COALESCE(RSV_TP_LEVEL, '')                                 AS rsv_tp_level,
  COALESCE(SAFE_CAST(RSV_ED_VISITS AS INT64), 0)             AS rsv_ed_visits,
  COALESCE(SAFE_CAST(RSV_ADM AS INT64), 0)                   AS rsv_adm,
  COALESCE(SAFE_CAST(RSV_ADM_RATE AS FLOAT64), 0)            AS rsv_adm_rate,
  COALESCE(RSV_ADM_LEVEL, '')                                AS rsv_adm_level,
  COALESCE(SAFE_CAST(RSV_DEATHS AS INT64), 0)                AS rsv_deaths,
  COALESCE(SAFE_CAST(RSV_DEATHS_PER AS FLOAT64), 0)          AS rsv_deaths_per,

  -- Totals
  COALESCE(SAFE_CAST(TOTAL_DEATHS AS INT64), 0)              AS total_deaths,
  COALESCE(SAFE_CAST(POP AS INT64), 0)                       AS population,

  -- Pediatric season cumulative
  COALESCE(SAFE_CAST(SEASON_COV_PED_DEATHS AS INT64), 0)     AS season_cov_ped_deaths,
  COALESCE(SAFE_CAST(SEASON_FLU_PED_DEATHS AS INT64), 0)     AS season_flu_ped_deaths,
  COALESCE(SAFE_CAST(SEASON_RSV_PED_DEATHS AS INT64), 0)     AS season_rsv_ped_deaths,

  -- Lineage
  _ingestion_timestamp,
  _batch_id

FROM source
WHERE _rn = 1
