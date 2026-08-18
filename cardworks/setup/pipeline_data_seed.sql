-- ============================================================
-- CardWorks Pipeline Monitor — Demo Data Seed
-- ============================================================
-- Prerequisites: CARDWORKS_DEMO database and MARTS schema exist
-- Run via Snowsight or: snow sql -f setup/pipeline_data_seed.sql
-- ============================================================

CREATE OR REPLACE TABLE CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY AS

WITH

-- 90-day date spine
dates AS (
    SELECT DATEADD('day', -(seq4()), CURRENT_DATE()) AS run_date
    FROM TABLE(GENERATOR(ROWCOUNT => 90))
),

-- Pipeline definitions grounded in the dbt project models + vendor feeds
pipelines AS (
    SELECT
        col1  AS pipeline_name,
        col2  AS source_system,
        col3  AS pipeline_type,
        col4  AS expected_rows,
        col5  AS min_rows,
        col6  AS max_rows,
        col7  AS avg_sec,
        col8  AS sec_variance
    FROM VALUES
        -- dbt staging layer (from RAW_MAINFRAME via Snowpark)
        ('stg_transactions',         'RAW_MAINFRAME',   'DBT_STAGING', 5400,   4800,   6200,   175, 45),
        ('stg_accounts',             'RAW_MAINFRAME',   'DBT_STAGING', 275,    220,    340,    55,  12),
        ('stg_merchants',            'RAW_MAINFRAME',   'DBT_STAGING', 78,     55,     105,    28,  8),
        -- dbt mart layer
        ('fct_transactions',         'STAGING_LAYER',   'DBT_MART',    5400,   4800,   6200,   240, 55),
        ('fct_monthly_txn_summary',  'MARTS_LAYER',     'DBT_MART',    182000, 158000, 208000, 410, 80),
        -- External vendor feeds via Snowpipe
        ('ACION_COLLECTIONS_FEED',   'ACION_EXTERNAL',  'SNOWPIPE',    1740,   1500,   2100,   88,  22),
        ('MAINFRAME_DAILY_BATCH',    'MAINFRAME_SFTP',  'SNOWPIPE',    9100,   7600,   10800,  295, 60)
    AS v
),

-- Cross-join date spine × pipeline config; skip weekends for DBT models
base AS (
    SELECT
        d.run_date,
        p.pipeline_name,
        p.source_system,
        p.pipeline_type,
        p.expected_rows,
        p.min_rows,
        p.max_rows,
        p.avg_sec,
        p.sec_variance,
        -- Deterministic hash for reproducible "random" behaviour
        ABS(HASH(d.run_date::VARCHAR || '|' || p.pipeline_name)) AS h
    FROM dates d
    CROSS JOIN pipelines p
    -- DBT models don't run on weekends (Snowflake DAYOFWEEK: 0=Sun, 6=Sat)
    WHERE NOT (DAYOFWEEK(d.run_date) IN (0, 6) AND p.pipeline_type LIKE 'DBT%')
),

-- Inject the ACION doubled-volume anomaly (mirrors the real CardWorks incident)
-- and scatter a handful of failures/warnings across all pipelines
with_anomaly AS (
    SELECT
        b.*,
        -- ACION doubled its file volume from ~63 to ~31 days ago
        CASE
            WHEN b.pipeline_name = 'ACION_COLLECTIONS_FEED'
             AND b.run_date BETWEEN DATEADD('day', -63, CURRENT_DATE())
                               AND DATEADD('day', -31, CURRENT_DATE())
            THEN 2.0
            ELSE 1.0
        END AS vol_mult,

        -- Specific pinned failures for demo narrative + ~2% random failure rate
        CASE
            WHEN b.pipeline_name = 'fct_transactions'
             AND b.run_date = DATEADD('day', -1, CURRENT_DATE())  THEN 'FAILED'
            WHEN b.pipeline_name = 'fct_transactions'
             AND b.run_date = DATEADD('day', -3, CURRENT_DATE())  THEN 'FAILED'
            WHEN b.pipeline_name = 'MAINFRAME_DAILY_BATCH'
             AND b.run_date = DATEADD('day', -8, CURRENT_DATE())  THEN 'FAILED'
            WHEN b.h % 100 < 2                                   THEN 'FAILED'
            WHEN b.h % 100 BETWEEN 2 AND 7                       THEN 'WARNING'
            ELSE 'SUCCESS'
        END AS status
    FROM base b
),

final AS (
    SELECT
        -- Run ID: date + pipeline abbreviation + hash suffix
        'RUN-'
            || TO_CHAR(run_date, 'YYYYMMDD') || '-'
            || UPPER(SUBSTR(REPLACE(REPLACE(pipeline_name, '_', ''), '-', ''), 1, 5))
            || '-' || LPAD((h % 9999)::VARCHAR, 4, '0')                AS run_id,

        pipeline_name,
        source_system,
        pipeline_type,
        run_date,

        -- Start time = scheduled end minus actual duration
        TIMESTAMPADD(
            'second',
            -(avg_sec + (h % sec_variance - sec_variance / 2)),
            run_date::TIMESTAMP_NTZ + INTERVAL '6 hours'
        )                                                                AS run_start_ts,

        -- End time fixed at 06:00 UTC (overnight batch cadence)
        run_date::TIMESTAMP_NTZ + INTERVAL '6 hours'                    AS run_end_ts,

        -- Duration collapses for failures (they die fast)
        CASE
            WHEN status = 'FAILED'
            THEN GREATEST(8, ROUND(avg_sec * 0.2 + h % 15, 0))
            ELSE ROUND(avg_sec + (h % sec_variance - sec_variance / 2), 0)
        END                                                              AS duration_seconds,

        -- Rows: 0 on failure, slightly low on warning, normal×multiplier on success
        CASE
            WHEN status = 'FAILED'
            THEN 0
            WHEN status = 'WARNING'
            THEN GREATEST(0, ROUND((min_rows + h % (max_rows - min_rows)) * vol_mult * 0.82, 0))
            ELSE ROUND((min_rows + h % (max_rows - min_rows)) * vol_mult, 0)
        END                                                              AS rows_loaded,

        -- Expected rows scales with the anomaly multiplier so the spike is visible
        ROUND(expected_rows * vol_mult)                                  AS rows_expected,

        status,

        -- Error messages tailored to each pipeline for a realistic narrative
        CASE
            WHEN status = 'FAILED' AND pipeline_name = 'fct_transactions'
            THEN 'Upstream dependency stg_transactions incomplete: 0 rows received from '
                 || 'RAW_MAINFRAME batch. File TXNS_' || TO_CHAR(run_date, 'YYYYMMDD')
                 || '.dat not found in SFTP drop zone /incoming/mainframe/.'

            WHEN status = 'FAILED' AND pipeline_name = 'MAINFRAME_DAILY_BATCH'
            THEN 'SFTP connection timeout (30s). Host mainframe-sftp.cardworks.internal '
                 || 'unreachable. Retries 1/3 exhausted. Alert dispatched to on-call.'

            WHEN status = 'FAILED'
            THEN 'Warehouse CARDWORKS_WH auto-suspended mid-run. Execution terminated at '
                 || ROUND(avg_sec * 0.2 + h % 15)::VARCHAR || 's. Row count: 0.'

            WHEN status = 'WARNING' AND pipeline_name = 'ACION_COLLECTIONS_FEED'
            THEN 'Row count ' || ROUND((min_rows + h % (max_rows - min_rows)) * vol_mult * 0.82)::VARCHAR
                 || ' exceeds expected upper bound [' || min_rows::VARCHAR || '–' || max_rows::VARCHAR
                 || ']. Volume +' || ROUND((vol_mult - 1.0) * 100)::VARCHAR
                 || '% above baseline. Possible duplicate file send from vendor.'

            WHEN status = 'WARNING'
            THEN 'Row count below expected minimum (' || min_rows::VARCHAR
                 || '). Potential source data delay. Auto-retry queued in 30 min.'

            ELSE NULL
        END                                                              AS error_message,

        CASE WHEN h % 15 = 0 THEN 'MANUAL' ELSE 'SCHEDULED' END        AS triggered_by,
        'CARDWORKS_WH'                                                   AS warehouse_name

    FROM with_anomaly
)

SELECT * FROM final
ORDER BY run_start_ts DESC;

-- Quick validation
SELECT
    pipeline_name,
    COUNT(*)                                             AS total_runs,
    SUM(IFF(status = 'SUCCESS', 1, 0))                 AS successes,
    SUM(IFF(status = 'WARNING', 1, 0))                 AS warnings,
    SUM(IFF(status = 'FAILED',  1, 0))                 AS failures,
    MAX(rows_loaded)                                    AS max_rows_loaded,
    MIN(IFF(rows_loaded > 0, rows_loaded, NULL))        AS min_rows_loaded
FROM CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY
GROUP BY 1
ORDER BY 1;
