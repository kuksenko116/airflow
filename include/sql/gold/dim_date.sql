-- Upsert calendar dates into dim_date.
-- Uses FARM_FINGERPRINT on full_date for a stable surrogate key.

MERGE `{{ var.value.gcp_project_id }}.gold.dim_date` T
USING (
  SELECT
    FARM_FINGERPRINT(CAST(d AS STRING)) AS date_key,
    d                                   AS full_date,
    EXTRACT(YEAR FROM d)                AS year,
    EXTRACT(QUARTER FROM d)             AS quarter,
    EXTRACT(MONTH FROM d)               AS month,
    FORMAT_DATE('%B', d)                AS month_name,
    EXTRACT(WEEK FROM d)                AS week_of_year,
    EXTRACT(DAYOFWEEK FROM d)           AS day_of_week,
    FORMAT_DATE('%A', d)                AS day_name,
    EXTRACT(DAYOFYEAR FROM d)           AS day_of_year
  FROM UNNEST(GENERATE_DATE_ARRAY('2020-01-01', '2030-12-31')) AS d
) S
ON T.date_key = S.date_key
WHEN NOT MATCHED THEN
  INSERT (date_key, full_date, year, quarter, month, month_name,
          week_of_year, day_of_week, day_name, day_of_year)
  VALUES (S.date_key, S.full_date, S.year, S.quarter, S.month, S.month_name,
          S.week_of_year, S.day_of_week, S.day_name, S.day_of_year)
