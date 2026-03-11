-- Upsert age groups into dim_age_group.

MERGE `{{ var.value.gcp_project_id }}.gold.dim_age_group` T
USING (
  SELECT
    FARM_FINGERPRINT(age_group) AS age_group_key,
    age_group                   AS age_group_label
  FROM (
    SELECT DISTINCT age_group
    FROM `{{ var.value.gcp_project_id }}.silver.respiratory_virus`
    WHERE age_group IS NOT NULL
  )
) S
ON T.age_group_label = S.age_group_label
WHEN NOT MATCHED THEN
  INSERT (age_group_key, age_group_label)
  VALUES (S.age_group_key, S.age_group_label)
