-- Upsert seasons into dim_season.

MERGE `{{ var.value.gcp_project_id }}.gold.dim_season` T
USING (
  SELECT
    FARM_FINGERPRINT(season) AS season_key,
    season                   AS season_name
  FROM (
    SELECT DISTINCT season
    FROM `{{ var.value.gcp_project_id }}.silver.respiratory_virus`
    WHERE season IS NOT NULL
  )
) S
ON T.season_name = S.season_name
WHEN NOT MATCHED THEN
  INSERT (season_key, season_name)
  VALUES (S.season_key, S.season_name)
