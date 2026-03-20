-- Silver: MERGE/upsert Respiratory Virus Dashboard bronze data.
-- Natural key: (season, age_group, rpho_region, week_ending)
-- Deduplicates bronze rows, then upserts into silver.

MERGE `{{ var.value.gcp_project_id }}.silver.respiratory_virus` T
USING (
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
    SEASON                                                     AS season,
    AGE_GRP                                                    AS age_group,
    RPHO_REGION                                                AS rpho_region,
    PARSE_DATE('%m/%d/%Y', WEEKENDING)                         AS week_ending,
    SAFE_CAST(MMWR_WEEK AS INT64)                              AS mmwr_week,
    SAFE_CAST(MMWR_YEAR AS INT64)                              AS mmwr_year,
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
    COALESCE(SAFE_CAST(TOTAL_DEATHS AS INT64), 0)              AS total_deaths,
    COALESCE(SAFE_CAST(POP AS INT64), 0)                       AS population,
    COALESCE(SAFE_CAST(SEASON_COV_PED_DEATHS AS INT64), 0)     AS season_cov_ped_deaths,
    COALESCE(SAFE_CAST(SEASON_FLU_PED_DEATHS AS INT64), 0)     AS season_flu_ped_deaths,
    COALESCE(SAFE_CAST(SEASON_RSV_PED_DEATHS AS INT64), 0)     AS season_rsv_ped_deaths,
    _ingestion_timestamp,
    _batch_id
  FROM source
  WHERE _rn = 1
) S
ON  T.season      = S.season
AND T.age_group   = S.age_group
AND T.rpho_region = S.rpho_region
AND T.week_ending = S.week_ending
WHEN MATCHED THEN
  UPDATE SET
    mmwr_week             = S.mmwr_week,
    mmwr_year             = S.mmwr_year,
    cov_positives         = S.cov_positives,
    cov_total_tests       = S.cov_total_tests,
    cov_tp                = S.cov_tp,
    cov_tp_level          = S.cov_tp_level,
    cov_ed_visits         = S.cov_ed_visits,
    cov_adm               = S.cov_adm,
    cov_adm_rate          = S.cov_adm_rate,
    cov_adm_level         = S.cov_adm_level,
    cov_deaths            = S.cov_deaths,
    cov_deaths_per        = S.cov_deaths_per,
    flu_positives         = S.flu_positives,
    flu_total_tests       = S.flu_total_tests,
    flu_tp                = S.flu_tp,
    flu_tp_level          = S.flu_tp_level,
    flu_a_tests           = S.flu_a_tests,
    flu_b_tests           = S.flu_b_tests,
    flu_ed_visits         = S.flu_ed_visits,
    flu_adm               = S.flu_adm,
    flu_adm_rate          = S.flu_adm_rate,
    flu_adm_level         = S.flu_adm_level,
    flu_deaths            = S.flu_deaths,
    flu_deaths_per        = S.flu_deaths_per,
    rsv_positives         = S.rsv_positives,
    rsv_total_tests       = S.rsv_total_tests,
    rsv_tp                = S.rsv_tp,
    rsv_tp_level          = S.rsv_tp_level,
    rsv_ed_visits         = S.rsv_ed_visits,
    rsv_adm               = S.rsv_adm,
    rsv_adm_rate          = S.rsv_adm_rate,
    rsv_adm_level         = S.rsv_adm_level,
    rsv_deaths            = S.rsv_deaths,
    rsv_deaths_per        = S.rsv_deaths_per,
    total_deaths          = S.total_deaths,
    population            = S.population,
    season_cov_ped_deaths = S.season_cov_ped_deaths,
    season_flu_ped_deaths = S.season_flu_ped_deaths,
    season_rsv_ped_deaths = S.season_rsv_ped_deaths,
    _ingestion_timestamp  = S._ingestion_timestamp,
    _batch_id             = S._batch_id
WHEN NOT MATCHED THEN
  INSERT (season, age_group, rpho_region, week_ending, mmwr_week, mmwr_year,
          cov_positives, cov_total_tests, cov_tp, cov_tp_level,
          cov_ed_visits, cov_adm, cov_adm_rate, cov_adm_level,
          cov_deaths, cov_deaths_per,
          flu_positives, flu_total_tests, flu_tp, flu_tp_level,
          flu_a_tests, flu_b_tests, flu_ed_visits, flu_adm, flu_adm_rate,
          flu_adm_level, flu_deaths, flu_deaths_per,
          rsv_positives, rsv_total_tests, rsv_tp, rsv_tp_level,
          rsv_ed_visits, rsv_adm, rsv_adm_rate, rsv_adm_level,
          rsv_deaths, rsv_deaths_per,
          total_deaths, population,
          season_cov_ped_deaths, season_flu_ped_deaths, season_rsv_ped_deaths,
          _ingestion_timestamp, _batch_id)
  VALUES (S.season, S.age_group, S.rpho_region, S.week_ending, S.mmwr_week, S.mmwr_year,
          S.cov_positives, S.cov_total_tests, S.cov_tp, S.cov_tp_level,
          S.cov_ed_visits, S.cov_adm, S.cov_adm_rate, S.cov_adm_level,
          S.cov_deaths, S.cov_deaths_per,
          S.flu_positives, S.flu_total_tests, S.flu_tp, S.flu_tp_level,
          S.flu_a_tests, S.flu_b_tests, S.flu_ed_visits, S.flu_adm, S.flu_adm_rate,
          S.flu_adm_level, S.flu_deaths, S.flu_deaths_per,
          S.rsv_positives, S.rsv_total_tests, S.rsv_tp, S.rsv_tp_level,
          S.rsv_ed_visits, S.rsv_adm, S.rsv_adm_rate, S.rsv_adm_level,
          S.rsv_deaths, S.rsv_deaths_per,
          S.total_deaths, S.population,
          S.season_cov_ped_deaths, S.season_flu_ped_deaths, S.season_rsv_ped_deaths,
          S._ingestion_timestamp, S._batch_id)
