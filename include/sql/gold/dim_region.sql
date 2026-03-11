-- Upsert RPHO regions into dim_region.

MERGE `{{ var.value.gcp_project_id }}.gold.dim_region` T
USING (
  SELECT
    FARM_FINGERPRINT(rpho_region) AS region_key,
    rpho_region
  FROM (
    SELECT DISTINCT rpho_region
    FROM `{{ var.value.gcp_project_id }}.silver.respiratory_virus`
    WHERE rpho_region IS NOT NULL
  )
) S
ON T.rpho_region = S.rpho_region
WHEN NOT MATCHED THEN
  INSERT (region_key, rpho_region)
  VALUES (S.region_key, S.rpho_region)
