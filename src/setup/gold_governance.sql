USE CATALOG IDENTIFIER(:catalog);

CREATE OR REPLACE FUNCTION IDENTIFIER(
  concat(:catalog, '.', :gold_schema, '.mask_compensation')
)(
  value DECIMAL(18, 4)
)
RETURNS DECIMAL(18, 4)
COMMENT 'Returns compensation values to aita_hr_admin members and null to all other users.'
RETURN CASE
  WHEN is_member('aita_hr_admin') THEN value
  ELSE CAST(NULL AS DECIMAL(18, 4))
END;
