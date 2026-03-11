-- Upsert respiratory metrics into fact table.
-- MERGE on date_key + region_key + age_group_key + season_key.

MERGE `{{ var.value.gcp_project_id }}.gold.fact_respiratory_metrics` T
USING (
  SELECT
    d.date_key,
    r.region_key,
    a.age_group_key,
    s.season_key,
    v.cov_positives,
    v.cov_total_tests,
    v.cov_tp,
    v.cov_tp_level,
    v.flu_positives,
    v.flu_total_tests,
    v.flu_tp,
    v.flu_tp_level,
    v.rsv_positives,
    v.rsv_total_tests,
    v.rsv_tp,
    v.rsv_tp_level,
    v.cov_ed_visits,
    v.flu_ed_visits,
    v.rsv_ed_visits,
    v.population,
    v.cov_adm,
    v.flu_adm,
    v.rsv_adm,
    v.cov_adm_rate,
    v.flu_adm_rate,
    v.rsv_adm_rate,
    v.cov_adm_level,
    v.flu_adm_level,
    v.rsv_adm_level,
    v.total_deaths,
    v.cov_deaths,
    v.flu_deaths,
    v.rsv_deaths,
    v.cov_deaths_per,
    v.flu_deaths_per,
    v.rsv_deaths_per,
    v.season_cov_ped_deaths,
    v.season_flu_ped_deaths,
    v.season_rsv_ped_deaths,
    v.flu_a_tests,
    v.flu_b_tests
  FROM `{{ var.value.gcp_project_id }}.silver.respiratory_virus` v
  JOIN `{{ var.value.gcp_project_id }}.gold.dim_date` d
    ON d.full_date = v.week_ending
  JOIN `{{ var.value.gcp_project_id }}.gold.dim_season` s
    ON s.season_name = v.season
  JOIN `{{ var.value.gcp_project_id }}.gold.dim_region` r
    ON r.rpho_region = v.rpho_region
  JOIN `{{ var.value.gcp_project_id }}.gold.dim_age_group` a
    ON a.age_group_label = v.age_group
) S
ON  T.date_key      = S.date_key
AND T.region_key     = S.region_key
AND T.age_group_key  = S.age_group_key
AND T.season_key     = S.season_key
WHEN MATCHED THEN
  UPDATE SET
    cov_positives         = S.cov_positives,
    cov_total_tests       = S.cov_total_tests,
    cov_tp                = S.cov_tp,
    cov_tp_level          = S.cov_tp_level,
    flu_positives         = S.flu_positives,
    flu_total_tests       = S.flu_total_tests,
    flu_tp                = S.flu_tp,
    flu_tp_level          = S.flu_tp_level,
    rsv_positives         = S.rsv_positives,
    rsv_total_tests       = S.rsv_total_tests,
    rsv_tp                = S.rsv_tp,
    rsv_tp_level          = S.rsv_tp_level,
    cov_ed_visits         = S.cov_ed_visits,
    flu_ed_visits         = S.flu_ed_visits,
    rsv_ed_visits         = S.rsv_ed_visits,
    population            = S.population,
    cov_adm               = S.cov_adm,
    flu_adm               = S.flu_adm,
    rsv_adm               = S.rsv_adm,
    cov_adm_rate          = S.cov_adm_rate,
    flu_adm_rate          = S.flu_adm_rate,
    rsv_adm_rate          = S.rsv_adm_rate,
    cov_adm_level         = S.cov_adm_level,
    flu_adm_level         = S.flu_adm_level,
    rsv_adm_level         = S.rsv_adm_level,
    total_deaths          = S.total_deaths,
    cov_deaths            = S.cov_deaths,
    flu_deaths            = S.flu_deaths,
    rsv_deaths            = S.rsv_deaths,
    cov_deaths_per        = S.cov_deaths_per,
    flu_deaths_per        = S.flu_deaths_per,
    rsv_deaths_per        = S.rsv_deaths_per,
    season_cov_ped_deaths = S.season_cov_ped_deaths,
    season_flu_ped_deaths = S.season_flu_ped_deaths,
    season_rsv_ped_deaths = S.season_rsv_ped_deaths,
    flu_a_tests           = S.flu_a_tests,
    flu_b_tests           = S.flu_b_tests
WHEN NOT MATCHED THEN
  INSERT (date_key, region_key, age_group_key, season_key,
          cov_positives, cov_total_tests, cov_tp, cov_tp_level,
          flu_positives, flu_total_tests, flu_tp, flu_tp_level,
          rsv_positives, rsv_total_tests, rsv_tp, rsv_tp_level,
          cov_ed_visits, flu_ed_visits, rsv_ed_visits, population,
          cov_adm, flu_adm, rsv_adm,
          cov_adm_rate, flu_adm_rate, rsv_adm_rate,
          cov_adm_level, flu_adm_level, rsv_adm_level,
          total_deaths, cov_deaths, flu_deaths, rsv_deaths,
          cov_deaths_per, flu_deaths_per, rsv_deaths_per,
          season_cov_ped_deaths, season_flu_ped_deaths, season_rsv_ped_deaths,
          flu_a_tests, flu_b_tests)
  VALUES (S.date_key, S.region_key, S.age_group_key, S.season_key,
          S.cov_positives, S.cov_total_tests, S.cov_tp, S.cov_tp_level,
          S.flu_positives, S.flu_total_tests, S.flu_tp, S.flu_tp_level,
          S.rsv_positives, S.rsv_total_tests, S.rsv_tp, S.rsv_tp_level,
          S.cov_ed_visits, S.flu_ed_visits, S.rsv_ed_visits, S.population,
          S.cov_adm, S.flu_adm, S.rsv_adm,
          S.cov_adm_rate, S.flu_adm_rate, S.rsv_adm_rate,
          S.cov_adm_level, S.flu_adm_level, S.rsv_adm_level,
          S.total_deaths, S.cov_deaths, S.flu_deaths, S.rsv_deaths,
          S.cov_deaths_per, S.flu_deaths_per, S.rsv_deaths_per,
          S.season_cov_ped_deaths, S.season_flu_ped_deaths, S.season_rsv_ped_deaths,
          S.flu_a_tests, S.flu_b_tests)
