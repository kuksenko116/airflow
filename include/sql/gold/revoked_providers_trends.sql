-- Gold: MERGE/upsert revocation trends by year and reason.
-- Natural key: (revocation_year, revocation_reason)
-- Table created in init_gold_tables.sql

MERGE `{{ var.value.gcp_project_id }}.gold.revoked_medicare_providers_trends` T
USING (
  SELECT
    EXTRACT(YEAR FROM revocation_effective_date)                  AS revocation_year,
    COALESCE(revocation_reason, 'Unknown')                        AS revocation_reason,
    COUNT(*)                                                      AS revocation_count,
    COUNTIF(reenrollment_bar_expiration IS NOT NULL
            AND reenrollment_bar_expiration <= CURRENT_DATE())    AS reenrollment_eligible,
    SAFE_DIVIDE(
      COUNTIF(reenrollment_bar_expiration IS NOT NULL
              AND reenrollment_bar_expiration <= CURRENT_DATE()),
      COUNT(*)
    )                                                             AS reenrollment_rate,
    COUNT(DISTINCT state_cd)                                      AS distinct_states,
    CURRENT_TIMESTAMP()                                           AS _gold_built_at
  FROM `{{ var.value.gcp_project_id }}.silver.cms_revoked_medicare_providers`
  WHERE revocation_effective_date IS NOT NULL
  GROUP BY revocation_year, revocation_reason
) S
ON  T.revocation_year   = S.revocation_year
AND T.revocation_reason = S.revocation_reason
WHEN MATCHED THEN
  UPDATE SET
    revocation_count      = S.revocation_count,
    reenrollment_eligible = S.reenrollment_eligible,
    reenrollment_rate     = S.reenrollment_rate,
    distinct_states       = S.distinct_states,
    _gold_built_at        = S._gold_built_at
WHEN NOT MATCHED THEN
  INSERT (revocation_year, revocation_reason, revocation_count,
          reenrollment_eligible, reenrollment_rate, distinct_states, _gold_built_at)
  VALUES (S.revocation_year, S.revocation_reason, S.revocation_count,
          S.reenrollment_eligible, S.reenrollment_rate, S.distinct_states, S._gold_built_at)
