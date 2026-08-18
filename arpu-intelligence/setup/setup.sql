-- ============================================================
-- ARPU Intelligence Demo - Full Setup Script
-- ============================================================
-- Run top-to-bottom on a Medium warehouse.
-- Prerequisites: ACCOUNTADMIN role, Medium standard warehouse
--
-- Swap the two variables below before running:
--   DEMO_DB  : name for the demo database
--   DEMO_WH  : your warehouse name
-- ============================================================

SET demo_db = 'ARPU_INTELLIGENCE_DEMO';
SET demo_wh = 'COMPUTE_WH';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($demo_wh);

-- ============================================================
-- 1. DATABASE & SCHEMAS
-- ============================================================
CREATE DATABASE IF NOT EXISTS IDENTIFIER($demo_db)
  COMMENT = 'ARPU Intelligence Demo - Artist analytics, ML recommendations, Cortex Agent';

CREATE SCHEMA IF NOT EXISTS IDENTIFIER($demo_db || '.RAW');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($demo_db || '.ANALYTICS');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($demo_db || '.ML');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($demo_db || '.AGENT');

-- ============================================================
-- 2. RAW TABLES
-- ============================================================
-- Generate 5,000 synthetic artists
CREATE OR REPLACE TABLE IDENTIFIER($demo_db || '.RAW.ARTISTS') AS
WITH genres AS (SELECT column1 AS genre FROM VALUES ('Hip-Hop'),('R&B'),('Pop'),('Latin'),('Afrobeats'),('Country'),('Rock'),('Electronic')),
     tiers  AS (SELECT column1 AS tier,  column2 AS weight FROM VALUES ('Free',60),('Select',25),('Pro',10),('Gold',4),('Platinum',1)),
     countries AS (SELECT column1 AS country FROM VALUES ('US'),('UK'),('Nigeria'),('Brazil'),('Colombia'),('Ghana'),('Canada'),('Mexico'))
SELECT
    'ARTIST_' || LPAD(ROW_NUMBER() OVER (ORDER BY RANDOM()), 6, '0') AS artist_id,
    'Artist ' || ROW_NUMBER() OVER (ORDER BY RANDOM()) AS artist_name,
    g.genre,
    t.tier,
    DATEADD(DAY, -UNIFORM(1,1095,RANDOM()), CURRENT_DATE()) AS join_date,
    c.country,
    UNIFORM(100, 500000, RANDOM()) AS monthly_listeners,
    UNIFORM(1, 50, RANDOM()) AS catalog_size
FROM TABLE(GENERATOR(ROWCOUNT=>5000))
JOIN LATERAL (SELECT genre FROM genres ORDER BY RANDOM() LIMIT 1) g ON TRUE
JOIN LATERAL (SELECT tier FROM tiers ORDER BY RANDOM() LIMIT 1) t ON TRUE
JOIN LATERAL (SELECT country FROM countries ORDER BY RANDOM() LIMIT 1) c ON TRUE;

-- Generate monthly transactions (approx 230k+ rows)
CREATE OR REPLACE TABLE IDENTIFIER($demo_db || '.RAW.TRANSACTIONS') AS
WITH months AS (
    SELECT DATEADD(MONTH, -seq4(), DATE_TRUNC('MONTH', CURRENT_DATE())) AS period_month
    FROM TABLE(GENERATOR(ROWCOUNT=>24))
),
platforms AS (SELECT column1 AS platform, column2 AS weight FROM VALUES
    ('Spotify',40),('Apple Music',25),('YouTube Music',15),('Amazon Music',10),('TikTok',7),('Tidal',3)),
base AS (
    SELECT
        'TXN_' || LPAD(ROW_NUMBER() OVER (ORDER BY RANDOM()), 9, '0') AS transaction_id,
        a.artist_id,
        m.period_month,
        p.platform,
        CASE WHEN a.tier IN ('Platinum','Gold') THEN UNIFORM(50000,500000,RANDOM())
             WHEN a.tier = 'Pro' THEN UNIFORM(5000,50000,RANDOM())
             WHEN a.tier = 'Select' THEN UNIFORM(500,5000,RANDOM())
             ELSE UNIFORM(10,500,RANDOM()) END AS stream_count
    FROM IDENTIFIER($demo_db || '.RAW.ARTISTS') a
    JOIN months m ON m.period_month >= DATEADD(MONTH,-12,CURRENT_DATE())
    JOIN LATERAL (SELECT platform FROM platforms ORDER BY RANDOM() LIMIT 1) p ON TRUE
    WHERE RANDOM() < 0.7
)
SELECT
    transaction_id, artist_id, period_month, platform, stream_count,
    ROUND(stream_count * 0.004, 4) AS royalty_usd,
    ROUND(stream_count * 0.004 * 0.15, 4) AS distribution_fee_usd,
    ROUND(stream_count * 0.004 * 0.85, 4) AS net_payout_usd,
    ROUND(stream_count * 0.004, 4) AS arpu_usd
FROM base;

-- Generate feature adoption data
CREATE OR REPLACE TABLE IDENTIFIER($demo_db || '.RAW.FEATURE_ADOPTION') AS
WITH features AS (SELECT column1 AS feature_name FROM VALUES
    ('Smart Links'),('Analytics Dashboard'),('Playlist Pitching'),
    ('Distribution Plus'),('Social Clip Tool'),('Sync Licensing'))
SELECT
    a.artist_id,
    f.feature_name,
    DATEADD(DAY, -UNIFORM(1,365,RANDOM()), CURRENT_DATE()) AS first_used_date,
    UNIFORM(0,30,RANDOM()) AS sessions_last_30d,
    CASE WHEN RANDOM() < 0.6 THEN TRUE ELSE FALSE END AS is_active_user
FROM IDENTIFIER($demo_db || '.RAW.ARTISTS') a
JOIN features f ON RANDOM() < 0.45;

-- ============================================================
-- 3. ANALYTICS VIEWS
-- ============================================================
CREATE OR REPLACE VIEW IDENTIFIER($demo_db || '.ANALYTICS.ARTIST_ARPU_TIMESERIES') AS
SELECT artist_id, period_month, ROUND(SUM(arpu_usd), 2) AS arpu_usd
FROM IDENTIFIER($demo_db || '.RAW.TRANSACTIONS')
GROUP BY artist_id, period_month;

CREATE OR REPLACE VIEW IDENTIFIER($demo_db || '.ANALYTICS.ARTIST_FEATURES') AS
WITH latest AS (
    SELECT artist_id, ROUND(SUM(net_payout_usd),2) AS current_arpu
    FROM IDENTIFIER($demo_db || '.RAW.TRANSACTIONS')
    WHERE period_month = DATE_TRUNC('MONTH', DATEADD(MONTH,-1,CURRENT_DATE()))
    GROUP BY artist_id
),
prior AS (
    SELECT artist_id, ROUND(SUM(net_payout_usd),2) AS prior_arpu
    FROM IDENTIFIER($demo_db || '.RAW.TRANSACTIONS')
    WHERE period_month = DATE_TRUNC('MONTH', DATEADD(MONTH,-2,CURRENT_DATE()))
    GROUP BY artist_id
),
adoption AS (
    SELECT artist_id,
           COUNT(DISTINCT feature_name) AS feature_adoption_count,
           SUM(sessions_last_30d) AS total_sessions_30d
    FROM IDENTIFIER($demo_db || '.RAW.FEATURE_ADOPTION')
    GROUP BY artist_id
)
SELECT
    a.artist_id,
    COALESCE(l.current_arpu, 0) AS current_arpu,
    COALESCE(ad.feature_adoption_count, 0) AS feature_adoption_count,
    COALESCE(ad.total_sessions_30d, 0) AS total_sessions_30d,
    ROUND(DATEDIFF('MONTH', a.join_date, CURRENT_DATE()), 0) AS months_on_platform,
    a.monthly_listeners, a.catalog_size, a.tier, a.genre,
    ROUND(CASE WHEN COALESCE(p.prior_arpu,0) = 0 THEN 0
               ELSE (COALESCE(l.current_arpu,0) - p.prior_arpu) / p.prior_arpu * 100 END, 1) AS arpu_change_pct,
    CASE WHEN COALESCE(l.current_arpu,0) < 5 AND COALESCE(ad.total_sessions_30d,0) < 5 THEN 'High'
         WHEN COALESCE(l.current_arpu,0) < 20 OR COALESCE(ad.total_sessions_30d,0) < 15 THEN 'Medium'
         ELSE 'Low' END AS churn_risk_label
FROM IDENTIFIER($demo_db || '.RAW.ARTISTS') a
LEFT JOIN latest l ON l.artist_id = a.artist_id
LEFT JOIN prior p ON p.artist_id = a.artist_id
LEFT JOIN adoption ad ON ad.artist_id = a.artist_id;

-- ============================================================
-- 4. ML TRAINING DATA VIEWS
-- ============================================================
CREATE OR REPLACE VIEW IDENTIFIER($demo_db || '.ML.FORECAST_TRAINING_DATA') AS
SELECT t.artist_id, t.period_month, t.arpu_usd
FROM IDENTIFIER($demo_db || '.ANALYTICS.ARTIST_ARPU_TIMESERIES') t
WHERE t.artist_id IN (
    SELECT artist_id FROM IDENTIFIER($demo_db || '.ANALYTICS.ARTIST_ARPU_TIMESERIES')
    WHERE period_month < DATE_TRUNC('MONTH', CURRENT_DATE())
    GROUP BY artist_id HAVING COUNT(*) >= 10 LIMIT 50
) AND t.period_month < DATE_TRUNC('MONTH', CURRENT_DATE());

CREATE OR REPLACE VIEW IDENTIFIER($demo_db || '.ML.CHURN_TRAINING_DATA') AS
SELECT feature_adoption_count, total_sessions_30d, current_arpu, arpu_change_pct,
       monthly_listeners, catalog_size, months_on_platform, tier, genre, churn_risk_label
FROM IDENTIFIER($demo_db || '.ANALYTICS.ARTIST_FEATURES');

-- ============================================================
-- 5. TRAIN ML MODELS
-- ============================================================
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST IDENTIFIER($demo_db || '.ML.ARPU_FORECAST_MODEL')(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', $demo_db || '.ML.FORECAST_TRAINING_DATA'),
  SERIES_COLNAME => 'ARTIST_ID',
  TIMESTAMP_COLNAME => 'PERIOD_MONTH',
  TARGET_COLNAME => 'ARPU_USD'
);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION IDENTIFIER($demo_db || '.ML.REVENUE_ANOMALY_MODEL')(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', $demo_db || '.ML.FORECAST_TRAINING_DATA'),
  SERIES_COLNAME => 'ARTIST_ID',
  TIMESTAMP_COLNAME => 'PERIOD_MONTH',
  TARGET_COLNAME => 'ARPU_USD'
);

-- ============================================================
-- 6. STORE MODEL OUTPUTS
-- ============================================================
CREATE OR REPLACE TABLE IDENTIFIER($demo_db || '.ML.FORECAST_RESULTS') AS
SELECT f.series AS artist_id, f.ts AS forecast_month,
       ROUND(f.forecast, 2) AS forecast_arpu,
       ROUND(f.lower_bound, 2) AS lower_bound,
       ROUND(f.upper_bound, 2) AS upper_bound
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Run forecast to populate results
CALL IDENTIFIER($demo_db || '.ML.ARPU_FORECAST_MODEL')!FORECAST(
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', $demo_db || '.ML.FORECAST_TRAINING_DATA'),
    SERIES_COLNAME => 'ARTIST_ID', TIMESTAMP_COLNAME => 'PERIOD_MONTH',
    TARGET_COLNAME => 'ARPU_USD', FORECASTING_PERIODS => 3
);

INSERT INTO IDENTIFIER($demo_db || '.ML.FORECAST_RESULTS')
SELECT series AS artist_id, ts AS forecast_month,
       ROUND(forecast, 2) AS forecast_arpu,
       ROUND(lower_bound, 2) AS lower_bound,
       ROUND(upper_bound, 2) AS upper_bound
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Pre-compute predictions table (churn + forecast combined)
CREATE OR REPLACE TABLE IDENTIFIER($demo_db || '.ML.PREDICTIONS') AS
SELECT
    af.artist_id,
    CASE WHEN af.churn_risk_label = 'High' THEN ROUND(UNIFORM(0.65, 0.99, RANDOM()), 3)
         WHEN af.churn_risk_label = 'Medium' THEN ROUND(UNIFORM(0.35, 0.64, RANDOM()), 3)
         ELSE ROUND(UNIFORM(0.01, 0.34, RANDOM()), 3) END AS churn_score,
    af.churn_risk_label,
    COALESCE(fr.forecast_arpu, af.current_arpu * 1.05) AS arpu_forecast_next_90d,
    CASE WHEN RANDOM() < 0.2 THEN 'Sync Licensing'
         WHEN RANDOM() < 0.4 THEN 'Distribution Plus'
         WHEN RANDOM() < 0.6 THEN 'Playlist Pitching'
         WHEN RANDOM() < 0.8 THEN 'Analytics Dashboard'
         ELSE 'Smart Links' END AS top_recommended_feature,
    ROUND(UNIFORM(5, 55, RANDOM()), 1) AS forecast_lift_pct
FROM IDENTIFIER($demo_db || '.ANALYTICS.ARTIST_FEATURES') af
LEFT JOIN IDENTIFIER($demo_db || '.ML.FORECAST_RESULTS') fr ON fr.artist_id = af.artist_id;

-- Portfolio-level AI recommendations
CREATE OR REPLACE TABLE IDENTIFIER($demo_db || '.ML.RECOMMENDATIONS') AS
SELECT
    column1 AS recommendation_text,
    column2 AS priority,
    column3 AS category,
    column4 AS scope,
    CURRENT_TIMESTAMP() AS generated_at
FROM VALUES
    ('Focus retention efforts on High-risk artists earning above median ARPU — they represent your highest revenue-at-risk segment.', 1, 'Retention', 'portfolio'),
    ('Sync Licensing shows a 55% revenue lift and is underutilized — run a targeted activation campaign for Pro and Select tier artists.', 2, 'Feature Adoption', 'portfolio'),
    ('Artists using 3+ platform features have 2x higher ARPU than those using 1 feature — feature adoption is your leading revenue indicator.', 3, 'Revenue Growth', 'portfolio');

-- ============================================================
-- 7. CORTEX SEARCH (Artist FAQ)
-- ============================================================
CREATE OR REPLACE TABLE IDENTIFIER($demo_db || '.AGENT.KNOWLEDGE_BASE') (
    doc_id VARCHAR, title VARCHAR, content TEXT, category VARCHAR
);

INSERT INTO IDENTIFIER($demo_db || '.AGENT.KNOWLEDGE_BASE') VALUES
('FAQ_001', 'How are royalties calculated?', 'Royalties are calculated based on stream count multiplied by the per-stream rate for each platform. Spotify pays approximately $0.003-0.005 per stream. Your net payout is royalties minus the platform distribution fee (typically 15%).', 'Royalties'),
('FAQ_002', 'What is ARPU?', 'ARPU (Average Revenue Per User) measures the average monthly revenue generated per artist. It is calculated as total net payouts divided by the number of active artists in that period. Higher-tier artists typically have significantly higher ARPU.', 'Metrics'),
('FAQ_003', 'How does Playlist Pitching work?', 'Playlist Pitching lets you submit unreleased tracks to editorial playlist curators before your release date. Artists who get playlist placements see an average 32% increase in streams and royalties within 30 days of release.', 'Features'),
('FAQ_004', 'What is Distribution Plus?', 'Distribution Plus is a premium distribution tier that includes priority processing, enhanced metadata, and access to exclusive platform deals. Artists on Distribution Plus earn an average of 41% more revenue than standard distribution artists.', 'Features'),
('FAQ_005', 'What is Sync Licensing?', 'Sync Licensing allows your music to be licensed for use in TV shows, films, ads, and video games. Sync deals typically pay a one-time fee ($500-$50,000+) plus ongoing royalties. Artists with sync deals earn an average of 55% more annually.', 'Revenue'),
('FAQ_006', 'How do I reduce my churn risk?', 'Churn risk is based on recent revenue trends, platform engagement, and feature adoption. To reduce risk: log in weekly, use Analytics Dashboard to track performance, adopt at least 3 platform features, and maintain consistent release activity.', 'Retention'),
('FAQ_007', 'Which platform pays the most per stream?', 'Tidal pays the highest per-stream rate (~$0.01), followed by Apple Music (~$0.006), Spotify (~$0.004), Amazon Music (~$0.004), YouTube Music (~$0.002), and TikTok (~$0.001). However, Spotify and YouTube drive the most total volume.', 'Platforms'),
('FAQ_008', 'How are tiers determined?', 'Artist tiers (Free, Select, Pro, Gold, Platinum) are based on subscription plan and catalog performance. Higher tiers unlock more features, better distribution terms, and priority support. Tier upgrades are available in your account settings.', 'Account');

CREATE OR REPLACE CORTEX SEARCH SERVICE IDENTIFIER($demo_db || '.AGENT.ARTIST_FAQ')
ON content
ATTRIBUTES title, category
WAREHOUSE = IDENTIFIER($demo_wh)
TARGET_LAG = '1 hour'
AS SELECT doc_id, title, content, category FROM IDENTIFIER($demo_db || '.AGENT.KNOWLEDGE_BASE');

-- ============================================================
-- 8. SEMANTIC MODEL STAGE
-- ============================================================
CREATE STAGE IF NOT EXISTS IDENTIFIER($demo_db || '.AGENT.MODELS')
  COMMENT = 'Semantic model YAML files for Cortex Analyst';

-- Upload semantic_model.yaml to this stage:
-- PUT 'file://agent/semantic_model.yaml' @<demo_db>.AGENT.MODELS AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ============================================================
-- 9. CORTEX AGENT
-- ============================================================
-- After uploading semantic_model.yaml, create the agent:
/*
CREATE OR REPLACE AGENT IDENTIFIER($demo_db || '.AGENT.ARTIST_AGENT')
  WAREHOUSE = IDENTIFIER($demo_wh)
  COMMENT = 'Artist-facing analytics assistant'
AS $$
  tools:
    - tool_type: cortex_analyst_tool
      name: ArtistAnalytics
      spec:
        semantic_model: '@<demo_db>.AGENT.MODELS/semantic_model.yaml'
    - tool_type: cortex_search_tool
      name: ArtistFAQ
      spec:
        service: <demo_db>.AGENT.ARTIST_FAQ
        max_results: 3
  tool_resources:
    ArtistFAQ:
      service: IDENTIFIER($demo_db || '.AGENT.ARTIST_FAQ')
$$;
*/

-- ============================================================
-- 10. STREAMLIT STAGE & APP
-- ============================================================
CREATE STAGE IF NOT EXISTS IDENTIFIER($demo_db || '.ANALYTICS.STREAMLIT_STAGE');

-- PUT 'file://streamlit/streamlit_app.py' @<demo_db>.ANALYTICS.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

/*
CREATE OR REPLACE STREAMLIT IDENTIFIER($demo_db || '.ANALYTICS.ARPU_INTELLIGENCE')
  ROOT_LOCATION = '@<demo_db>.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = IDENTIFIER($demo_wh)
  TITLE = 'ARPU Intelligence';
*/

-- ============================================================
-- 11. VERIFICATION
-- ============================================================
SELECT 'ARTISTS' AS obj, COUNT(*) AS rows FROM IDENTIFIER($demo_db || '.RAW.ARTISTS')
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM IDENTIFIER($demo_db || '.RAW.TRANSACTIONS')
UNION ALL SELECT 'FEATURE_ADOPTION', COUNT(*) FROM IDENTIFIER($demo_db || '.RAW.FEATURE_ADOPTION')
UNION ALL SELECT 'PREDICTIONS', COUNT(*) FROM IDENTIFIER($demo_db || '.ML.PREDICTIONS')
UNION ALL SELECT 'FORECAST_RESULTS', COUNT(*) FROM IDENTIFIER($demo_db || '.ML.FORECAST_RESULTS')
UNION ALL SELECT 'RECOMMENDATIONS', COUNT(*) FROM IDENTIFIER($demo_db || '.ML.RECOMMENDATIONS');
