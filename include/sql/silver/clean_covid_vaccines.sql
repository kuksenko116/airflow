-- Silver: Clean and type the COVID-19 Vaccines by County bronze data.
-- Dedup on (COUNTY, ADMINISTERED_DATE).
-- CALIFORNIA_FLAG mapped to BOOL matching NiFi: "California" → TRUE,
-- "Not in California" → FALSE, blank/null → TRUE.

WITH source AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY COUNTY, ADMINISTERED_DATE
      ORDER BY _ingestion_timestamp DESC
    ) AS _rn
  FROM `{{ var.value.gcp_project_id }}.bronze.chhs_covid_vaccines_raw`
)

SELECT
  COUNTY                                                       AS county,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', ADMINISTERED_DATE)
                                                               AS administered_date,
  COALESCE(SAFE_CAST(TOTAL_DOSES AS INT64), 0)                 AS total_doses,
  COALESCE(SAFE_CAST(CUMULATIVE_TOTAL_DOSES AS INT64), 0)      AS cumulative_total_doses,
  COALESCE(SAFE_CAST(PARTIALLY_VACCINATED AS INT64), 0)        AS partially_vaccinated,
  COALESCE(SAFE_CAST(TOTAL_PARTIALLY_VACCINATED AS INT64), 0)  AS total_partially_vaccinated,
  COALESCE(SAFE_CAST(FULLY_VACCINATED AS INT64), 0)            AS fully_vaccinated,
  COALESCE(SAFE_CAST(CUMULATIVE_FULLY_VACCINATED AS INT64), 0) AS cumulative_fully_vaccinated,
  COALESCE(SAFE_CAST(AT_LEAST_ONE_DOSE AS INT64), 0)           AS at_least_one_dose,
  COALESCE(SAFE_CAST(CUMULATIVE_AT_LEAST_ONE_DOSE AS INT64), 0)
                                                               AS cumulative_at_least_one_dose,
  CASE
    WHEN UPPER(TRIM(CALIFORNIA_FLAG)) = 'NOT IN CALIFORNIA' THEN FALSE
    ELSE TRUE  -- blank, null, or "California" → TRUE
  END                                                          AS california_flag,
  COALESCE(SAFE_CAST(UP_TO_DATE_COUNT AS INT64), 0)            AS up_to_date_count,
  COALESCE(SAFE_CAST(CUMULATIVE_UP_TO_DATE_COUNT AS INT64), 0) AS cumulative_up_to_date_count,

  -- Lineage
  _ingestion_timestamp,
  _batch_id

FROM source
WHERE _rn = 1
