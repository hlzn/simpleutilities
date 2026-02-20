-- ============================================================
-- DB Schema Extractor for Diagram Tool
-- ============================================================
-- HOW TO USE IN SSMS:
--   1. Go to Query > Results To > Results to Text  (or Ctrl+T)
--   2. Set @Filter below (or leave blank for all tables)
--   3. Run this script
--   4. Paste the full output into the diagram modal
--
-- NOTE: If output is truncated, run this first:
--   SET TEXTSIZE 2147483647;
--
-- ============================================================

SET TEXTSIZE 2147483647;
SET NOCOUNT ON;

-- ============================================================
-- FILTER VARIABLE
-- Leave blank ('') to include ALL tables and relationships.
-- Provide a partial name to filter tables by LIKE match.
--   Examples:
--     ''          -> all tables
--     'Order'     -> tables whose name contains "Order"
--     'Order%'    -> tables whose name starts with "Order"
--     '%Log'      -> tables whose name ends with "Log"
-- Relationships are included when EITHER end of the FK
-- belongs to a matched table.
-- ============================================================
DECLARE @Filter NVARCHAR(200) = '';

-- ============================================================
-- Resolve the matched table set once so both queries use it
-- ============================================================
DECLARE @MatchedTables TABLE (TableName SYSNAME, TableSchema SYSNAME);

INSERT INTO @MatchedTables (TableName, TableSchema)
SELECT
    t.TABLE_NAME,
    t.TABLE_SCHEMA
FROM INFORMATION_SCHEMA.TABLES t
WHERE
    t.TABLE_TYPE = 'BASE TABLE'
    AND (
        @Filter = ''
        OR t.TABLE_NAME LIKE '%' + @Filter + '%'
    )
    -- Uncomment and edit to restrict to a specific schema:
    -- AND t.TABLE_SCHEMA = 'dbo'
;

-- ============================================================
-- PART 1: Tables and Columns
-- ============================================================
PRINT '--- TABLES ---';

SELECT
    t.TableName                             AS [name],
    (
        SELECT
            c.COLUMN_NAME                   AS [name],
            c.DATA_TYPE                     AS [type],
            c.IS_NULLABLE                   AS [isNullable],
            c.CHARACTER_MAXIMUM_LENGTH      AS [maxLength],
            c.NUMERIC_PRECISION             AS [numericPrecision],
            c.NUMERIC_SCALE                 AS [numericScale],
            CASE
                WHEN pk.COLUMN_NAME IS NOT NULL THEN 1
                ELSE 0
            END                             AS [isPK]
        FROM INFORMATION_SCHEMA.COLUMNS c
        LEFT JOIN (
            SELECT ku.COLUMN_NAME, ku.TABLE_NAME, ku.TABLE_SCHEMA
            FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS   tc
            JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE    ku
                ON  tc.CONSTRAINT_NAME  = ku.CONSTRAINT_NAME
                AND tc.TABLE_NAME       = ku.TABLE_NAME
                AND tc.TABLE_SCHEMA     = ku.TABLE_SCHEMA
            WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
        ) pk
            ON  pk.COLUMN_NAME  = c.COLUMN_NAME
            AND pk.TABLE_NAME   = c.TABLE_NAME
            AND pk.TABLE_SCHEMA = c.TABLE_SCHEMA
        WHERE
            c.TABLE_NAME   = t.TableName
            AND c.TABLE_SCHEMA = t.TableSchema
        ORDER BY c.ORDINAL_POSITION
        FOR JSON PATH
    )                                       AS [columns]
FROM @MatchedTables t
ORDER BY t.TableName
FOR JSON PATH;


-- ============================================================
-- PART 2: Foreign Key Relationships
-- Include a relationship when EITHER the parent (fromTable)
-- OR the referenced (toTable) is in the matched set.
-- ============================================================
PRINT '--- RELATIONSHIPS ---';

SELECT
    fk.name                                 AS [constraintName],
    tp.name                                 AS [fromTable],
    cp.name                                 AS [fromColumn],
    tr.name                                 AS [toTable],
    cr.name                                 AS [toColumn]
FROM sys.foreign_keys                   fk
JOIN sys.foreign_key_columns            fkc
    ON  fk.object_id                    = fkc.constraint_object_id
JOIN sys.tables                         tp
    ON  fkc.parent_object_id            = tp.object_id
JOIN sys.columns                        cp
    ON  fkc.parent_object_id            = cp.object_id
    AND fkc.parent_column_id            = cp.column_id
JOIN sys.tables                         tr
    ON  fkc.referenced_object_id        = tr.object_id
JOIN sys.columns                        cr
    ON  fkc.referenced_object_id        = cr.object_id
    AND fkc.referenced_column_id        = cr.column_id
WHERE
    -- At least one end of the FK must be in the matched table set
    EXISTS (SELECT 1 FROM @MatchedTables m WHERE m.TableName = tp.name)
    OR
    EXISTS (SELECT 1 FROM @MatchedTables m WHERE m.TableName = tr.name)
ORDER BY fk.name
FOR JSON PATH;