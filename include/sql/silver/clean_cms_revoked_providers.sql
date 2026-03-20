-- Silver: MERGE/upsert CMS Revoked Medicare Providers bronze data.
-- Natural key: (enrlmt_id)
-- Bronze columns: ENRLMT_ID, NPI, FIRST_NAME, MDL_NAME, LAST_NAME,
--   ORG_NAME, MULTIPLE_NPI_FLAG, STATE_CD, PROVIDER_TYPE_DESC,
--   REVOCATION_RSN, REVOCATION_EFCTV_DT, REENROLLMENT_BAR_EXPRTN_DT

MERGE `{{ var.value.gcp_project_id }}.silver.cms_revoked_medicare_providers` T
USING (
  WITH source AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY ENRLMT_ID
        ORDER BY _ingestion_timestamp DESC
      ) AS _rn
    FROM `{{ var.value.gcp_project_id }}.bronze.cms_revoked_medicare_providers_raw`
  )
  SELECT
    TRIM(ENRLMT_ID)                                              AS enrlmt_id,
    TRIM(NPI)                                                    AS npi,
    TRIM(FIRST_NAME)                                             AS first_name,
    TRIM(MDL_NAME)                                               AS middle_name,
    TRIM(LAST_NAME)                                              AS last_name,
    TRIM(ORG_NAME)                                               AS org_name,
    TRIM(MULTIPLE_NPI_FLAG)                                      AS multiple_npi_flag,
    TRIM(STATE_CD)                                               AS state_cd,
    TRIM(PROVIDER_TYPE_DESC)                                     AS provider_type_desc,
    TRIM(REVOCATION_RSN)                                         AS revocation_reason,
    SAFE.PARSE_DATE('%m/%d/%Y', REVOCATION_EFCTV_DT)             AS revocation_effective_date,
    SAFE.PARSE_DATE('%m/%d/%Y', REENROLLMENT_BAR_EXPRTN_DT)     AS reenrollment_bar_expiration,
    _ingestion_timestamp,
    _batch_id
  FROM source
  WHERE _rn = 1
    AND ENRLMT_ID IS NOT NULL
) S
ON T.enrlmt_id = S.enrlmt_id
WHEN MATCHED THEN
  UPDATE SET
    npi                         = S.npi,
    first_name                  = S.first_name,
    middle_name                 = S.middle_name,
    last_name                   = S.last_name,
    org_name                    = S.org_name,
    multiple_npi_flag           = S.multiple_npi_flag,
    state_cd                    = S.state_cd,
    provider_type_desc          = S.provider_type_desc,
    revocation_reason           = S.revocation_reason,
    revocation_effective_date   = S.revocation_effective_date,
    reenrollment_bar_expiration = S.reenrollment_bar_expiration,
    _ingestion_timestamp        = S._ingestion_timestamp,
    _batch_id                   = S._batch_id
WHEN NOT MATCHED THEN
  INSERT (enrlmt_id, npi, first_name, middle_name, last_name, org_name,
          multiple_npi_flag, state_cd, provider_type_desc, revocation_reason,
          revocation_effective_date, reenrollment_bar_expiration,
          _ingestion_timestamp, _batch_id)
  VALUES (S.enrlmt_id, S.npi, S.first_name, S.middle_name, S.last_name, S.org_name,
          S.multiple_npi_flag, S.state_cd, S.provider_type_desc, S.revocation_reason,
          S.revocation_effective_date, S.reenrollment_bar_expiration,
          S._ingestion_timestamp, S._batch_id)
