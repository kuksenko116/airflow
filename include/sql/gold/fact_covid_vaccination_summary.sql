-- Upsert COVID vaccination data into fact table.
-- MERGE on date_key + county_key; updates measures if matched.

MERGE `{{ var.value.gcp_project_id }}.gold.fact_covid_vaccination_summary` T
USING (
  SELECT
    d.date_key,
    c.county_key,
    v.total_doses,
    v.cumulative_total_doses,
    v.partially_vaccinated,
    v.total_partially_vaccinated,
    v.fully_vaccinated,
    v.cumulative_fully_vaccinated,
    v.at_least_one_dose,
    v.cumulative_at_least_one_dose,
    v.california_flag,
    v.up_to_date_count,
    v.cumulative_up_to_date_count
  FROM `{{ var.value.gcp_project_id }}.silver.covid_vaccines_by_county` v
  JOIN `{{ var.value.gcp_project_id }}.gold.dim_date` d
    ON d.full_date = DATE(v.administered_date)
  JOIN `{{ var.value.gcp_project_id }}.gold.dim_county` c
    ON c.county_name = v.county
) S
ON T.date_key = S.date_key AND T.county_key = S.county_key
WHEN MATCHED THEN
  UPDATE SET
    total_doses                  = S.total_doses,
    cumulative_total_doses       = S.cumulative_total_doses,
    partially_vaccinated         = S.partially_vaccinated,
    total_partially_vaccinated   = S.total_partially_vaccinated,
    fully_vaccinated             = S.fully_vaccinated,
    cumulative_fully_vaccinated  = S.cumulative_fully_vaccinated,
    at_least_one_dose            = S.at_least_one_dose,
    cumulative_at_least_one_dose = S.cumulative_at_least_one_dose,
    california_flag              = S.california_flag,
    up_to_date_count             = S.up_to_date_count,
    cumulative_up_to_date_count  = S.cumulative_up_to_date_count
WHEN NOT MATCHED THEN
  INSERT (date_key, county_key, total_doses, cumulative_total_doses,
          partially_vaccinated, total_partially_vaccinated,
          fully_vaccinated, cumulative_fully_vaccinated,
          at_least_one_dose, cumulative_at_least_one_dose,
          california_flag, up_to_date_count, cumulative_up_to_date_count)
  VALUES (S.date_key, S.county_key, S.total_doses, S.cumulative_total_doses,
          S.partially_vaccinated, S.total_partially_vaccinated,
          S.fully_vaccinated, S.cumulative_fully_vaccinated,
          S.at_least_one_dose, S.cumulative_at_least_one_dose,
          S.california_flag, S.up_to_date_count, S.cumulative_up_to_date_count)
