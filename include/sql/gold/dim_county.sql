-- Upsert counties into dim_county.
-- MERGE on county_name; updates population if changed.

MERGE `{{ var.value.gcp_project_id }}.gold.dim_county` T
USING (
  WITH counties AS (
    SELECT DISTINCT county
    FROM `{{ var.value.gcp_project_id }}.silver.covid_vaccines_by_county`
    WHERE california_flag IS TRUE
      AND county IS NOT NULL
      AND county != ''
  ),
  populations AS (
    SELECT county, population FROM UNNEST([
      STRUCT('Alameda' AS county,        1638215 AS population),
      STRUCT('Alpine',                      1204),
      STRUCT('Amador',                     40474),
      STRUCT('Butte',                     206897),
      STRUCT('Calaveras',                  46221),
      STRUCT('Colusa',                     22280),
      STRUCT('Contra Costa',             1161413),
      STRUCT('Del Norte',                  27541),
      STRUCT('El Dorado',                193221),
      STRUCT('Fresno',                   1013581),
      STRUCT('Glenn',                      28917),
      STRUCT('Humboldt',                  135768),
      STRUCT('Imperial',                  179702),
      STRUCT('Inyo',                       18978),
      STRUCT('Kern',                      916467),
      STRUCT('Kings',                     153443),
      STRUCT('Lake',                       68766),
      STRUCT('Lassen',                     30600),
      STRUCT('Los Angeles',             9721138),
      STRUCT('Madera',                    160089),
      STRUCT('Marin',                     262321),
      STRUCT('Mariposa',                   17131),
      STRUCT('Mendocino',                  91601),
      STRUCT('Merced',                    286461),
      STRUCT('Modoc',                       8661),
      STRUCT('Mono',                       13195),
      STRUCT('Monterey',                  439091),
      STRUCT('Napa',                      136207),
      STRUCT('Nevada',                    103487),
      STRUCT('Orange',                   3186989),
      STRUCT('Placer',                    413560),
      STRUCT('Plumas',                     19790),
      STRUCT('Riverside',                2458395),
      STRUCT('Sacramento',               1585055),
      STRUCT('San Benito',                 66677),
      STRUCT('San Bernardino',           2194710),
      STRUCT('San Diego',                3286069),
      STRUCT('San Francisco',             808437),
      STRUCT('San Joaquin',               789410),
      STRUCT('San Luis Obispo',           282424),
      STRUCT('San Mateo',                 737888),
      STRUCT('Santa Barbara',             448229),
      STRUCT('Santa Clara',              1885508),
      STRUCT('Santa Cruz',                267792),
      STRUCT('Shasta',                    182155),
      STRUCT('Sierra',                      3236),
      STRUCT('Siskiyou',                   44118),
      STRUCT('Solano',                    451716),
      STRUCT('Sonoma',                    488863),
      STRUCT('Stanislaus',                552999),
      STRUCT('Sutter',                     99633),
      STRUCT('Tehama',                     65829),
      STRUCT('Trinity',                    16060),
      STRUCT('Tulare',                    477054),
      STRUCT('Tuolumne',                   55810),
      STRUCT('Ventura',                   839784),
      STRUCT('Yolo',                      216403),
      STRUCT('Yuba',                       82275)
    ])
  )
  SELECT
    FARM_FINGERPRINT(c.county) AS county_key,
    c.county                   AS county_name,
    COALESCE(p.population, 0)  AS population
  FROM counties c
  LEFT JOIN populations p ON UPPER(c.county) = UPPER(p.county)
) S
ON T.county_name = S.county_name
WHEN MATCHED AND T.population != S.population THEN
  UPDATE SET population = S.population
WHEN NOT MATCHED THEN
  INSERT (county_key, county_name, population)
  VALUES (S.county_key, S.county_name, S.population)
