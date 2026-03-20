-- Gold: MERGE/upsert revoked providers aggregated by state.
-- Natural key: state_cd
-- Table created in init_gold_tables.sql

MERGE `{{ var.value.gcp_project_id }}.gold.revoked_medicare_providers_by_state` T
USING (
  WITH by_state AS (
    SELECT
      state_cd,
      COUNT(*)                                                            AS total_revocations,
      COUNTIF(reenrollment_bar_expiration IS NULL
              OR reenrollment_bar_expiration > CURRENT_DATE())            AS active_revocations,
      COUNTIF(reenrollment_bar_expiration IS NOT NULL
              AND reenrollment_bar_expiration <= CURRENT_DATE())          AS reenrollment_eligible,
      COUNT(DISTINCT provider_type_desc)                                  AS distinct_provider_types,
      MIN(revocation_effective_date)                                      AS earliest_revocation,
      MAX(revocation_effective_date)                                      AS latest_revocation
    FROM `{{ var.value.gcp_project_id }}.silver.cms_revoked_medicare_providers`
    WHERE state_cd IS NOT NULL AND state_cd != ''
    GROUP BY state_cd
  ),
  top_reason AS (
    SELECT
      state_cd,
      revocation_reason,
      ROW_NUMBER() OVER (PARTITION BY state_cd ORDER BY COUNT(*) DESC) AS rn
    FROM `{{ var.value.gcp_project_id }}.silver.cms_revoked_medicare_providers`
    WHERE state_cd IS NOT NULL AND state_cd != ''
    GROUP BY state_cd, revocation_reason
  )
  SELECT
    s.state_cd,
    s.total_revocations,
    s.active_revocations,
    s.reenrollment_eligible,
    s.distinct_provider_types,
    r.revocation_reason AS most_common_reason,
    s.earliest_revocation,
    s.latest_revocation,
    CURRENT_TIMESTAMP() AS _gold_built_at
  FROM by_state s
  LEFT JOIN top_reason r ON s.state_cd = r.state_cd AND r.rn = 1
) S
ON T.state_cd = S.state_cd
WHEN MATCHED THEN
  UPDATE SET
    total_revocations       = S.total_revocations,
    active_revocations      = S.active_revocations,
    reenrollment_eligible   = S.reenrollment_eligible,
    distinct_provider_types = S.distinct_provider_types,
    most_common_reason      = S.most_common_reason,
    earliest_revocation     = S.earliest_revocation,
    latest_revocation       = S.latest_revocation,
    _gold_built_at          = S._gold_built_at
WHEN NOT MATCHED THEN
  INSERT (state_cd, total_revocations, active_revocations, reenrollment_eligible,
          distinct_provider_types, most_common_reason,
          earliest_revocation, latest_revocation, _gold_built_at)
  VALUES (S.state_cd, S.total_revocations, S.active_revocations, S.reenrollment_eligible,
          S.distinct_provider_types, S.most_common_reason,
          S.earliest_revocation, S.latest_revocation, S._gold_built_at)
