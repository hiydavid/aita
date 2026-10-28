BEGIN
  FOR principal AS
    SELECT principal_name
    FROM VALUES ('aita_users'), ('aita_hr_admin') AS principals(principal_name)
  DO
    EXECUTE IMMEDIATE CONCAT(
      'GRANT USE CATALOG ON CATALOG `', :catalog, '` TO `',
      principal.principal_name, '`'
    );
    EXECUTE IMMEDIATE CONCAT(
      'GRANT USE SCHEMA ON SCHEMA `', :catalog, '`.`', :gold_schema,
      '` TO `', principal.principal_name, '`'
    );
    FOR object AS
      SELECT object_name
      FROM VALUES
        ('dim_worker'),
        ('dim_org'),
        ('dim_job'),
        ('talent_watchlist'),
        ('semantic_workforce_monthly'),
        ('semantic_talent_snapshot'),
        ('semantic_talent_skills'),
        ('mv_workforce'),
        ('mv_attrition'),
        ('mv_engagement'),
        ('mv_productivity'),
        ('mv_talent'),
        ('mv_talent_skills'),
        ('mv_requisitions'),
        ('mv_recruiting_funnel') AS objects(object_name)
    DO
      EXECUTE IMMEDIATE CONCAT(
        'GRANT SELECT ON TABLE `', :catalog, '`.`', :gold_schema, '`.`',
        object.object_name, '` TO `', principal.principal_name, '`'
      );
    END FOR;
    EXECUTE IMMEDIATE CONCAT(
      'GRANT EXECUTE ON FUNCTION `', :catalog, '`.`', :gold_schema,
      '`.`mask_compensation` TO `', principal.principal_name, '`'
    );
  END FOR;
END;
