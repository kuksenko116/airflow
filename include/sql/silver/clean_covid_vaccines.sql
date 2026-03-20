-- Silver: Clean and type the COVID-19 Vaccines by County bronze data.
-- Dedup on (COUNTY, ADMINISTERED_DATE).
-- Text fields are SAFE_CAST to INT64; timestamp is parsed.

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
  COUNTY,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', ADMINISTERED_DATE) AS administered_date,
  CASE when (SAFE_CAST(TOTAL_DOSES AS INT64), <11 then "small"                                  AS total_doses,
  SAFE_CAST(CUMULATIVE_TOTAL_DOSES AS INT64)                       AS cumulative_total_doses,
  SAFE_CAST(PARTIALLY_VACCINATED AS INT64)                         AS partially_vaccinated,
  SAFE_CAST(TOTAL_PARTIALLY_VACCINATED AS INT64)                   AS total_partially_vaccinated,
  SAFE_CAST(FULLY_VACCINATED AS INT64)                             AS fully_vaccinated,
  SAFE_CAST(CUMULATIVE_FULLY_VACCINATED AS INT64)                  AS cumulative_fully_vaccinated,
  SAFE_CAST(AT_LEAST_ONE_DOSE AS INT64)                            AS at_least_one_dose,
  SAFE_CAST(CUMULATIVE_AT_LEAST_ONE_DOSE AS INT64)                 AS cumulative_at_least_one_dose,
  CALIFORNIA_FLAG,
  SAFE_CAST(UP_TO_DATE_COUNT AS INT64)                             AS up_to_date_count,
  SAFE_CAST(CUMULATIVE_UP_TO_DATE_COUNT AS INT64)                  AS cumulative_up_to_date_count,

  -- Lineage
  _ingestion_timestamp,
  _batch_id

FROM source
WHERE _rn = 1
