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
--
-- Tables directly connected to matched tables via FK are
-- automatically included (2-pass expansion).
-- ============================================================
DECLARE @Filter NVARCHAR(200) = '';

-- ============================================================
-- PASS 1: Tables that match the filter directly
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
    -- Uncomment to restrict to a specific schema:
    -- AND t.TABLE_SCHEMA = 'dbo'
;

-- ============================================================
-- PASS 2: Pull in any tables that are connected via FK to
-- the first-pass results but weren't matched themselves.
-- This ensures the diagram has both ends of every relationship.
-- ============================================================
INSERT INTO @MatchedTables (TableName, TableSchema)
SELECT DISTINCT
    it.TABLE_NAME,
    it.TABLE_SCHEMA
FROM sys.foreign_keys               fk
JOIN sys.foreign_key_columns        fkc
    ON  fk.object_id                = fkc.constraint_object_id
JOIN sys.tables                     tp
    ON  fkc.parent_object_id        = tp.object_id
JOIN sys.tables                     tr
    ON  fkc.referenced_object_id    = tr.object_id
-- Join INFORMATION_SCHEMA to get the schema name for the
-- candidate table (we need it for the columns query later)
JOIN INFORMATION_SCHEMA.TABLES      it
    ON  it.TABLE_TYPE               = 'BASE TABLE'
    AND it.TABLE_NAME IN (tp.name, tr.name)
WHERE
    -- At least one end of the FK is already in our matched set
    (
        EXISTS (SELECT 1 FROM @MatchedTables m WHERE m.TableName = tp.name)
        OR
        EXISTS (SELECT 1 FROM @MatchedTables m WHERE m.TableName = tr.name)
    )
    -- But only add the table if it isn't already there
    AND NOT EXISTS (SELECT 1 FROM @MatchedTables m WHERE m.TableName = it.TABLE_NAME)
;

-- ============================================================
-- PART 1: Tables and Columns  (all matched tables, both passes)
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
            c.TABLE_NAME    = t.TableName
            AND c.TABLE_SCHEMA  = t.TableSchema
        ORDER BY c.ORDINAL_POSITION
        FOR JSON PATH
    )                                       AS [columns]
FROM @MatchedTables t
ORDER BY t.TableName
FOR JSON PATH;


-- ============================================================
-- PART 2: Relationships between any two tables in the final set
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
    -- Both ends must now be present in the final matched set
    EXISTS (SELECT 1 FROM @MatchedTables m WHERE m.TableName = tp.name)
    AND
    EXISTS (SELECT 1 FROM @MatchedTables m WHERE m.TableName = tr.name)
ORDER BY fk.name
FOR JSON PATH;