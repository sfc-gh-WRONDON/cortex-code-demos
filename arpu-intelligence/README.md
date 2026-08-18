# ARPU Intelligence Demo

A complete Snowflake Cortex AI demo for music/creator distribution platforms. Shows ML-powered artist revenue analytics, an internal ops dashboard, and an external artist-facing agent — all running natively inside Snowflake.

## What This Demo Shows

1. **Snowflake ML** — `FORECAST` and `ANOMALY_DETECTION` models trained on artist revenue data
2. **Cortex AI** — `AI_COMPLETE` generating personalized artist recommendations
3. **Cortex Analyst** — Text-to-SQL over a semantic model for natural language querying
4. **Cortex Search** — FAQ retrieval for the artist-facing agent
5. **Cortex Agent** — Multi-tool agent combining Analyst + Search
6. **Streamlit in Snowflake** — Internal ops dashboard with 6 tabs

## Quick Start

```sql
-- 1. Open setup/setup.sql and set your database and warehouse at the top:
SET demo_db = 'ARPU_INTELLIGENCE_DEMO';
SET demo_wh = 'COMPUTE_WH';

-- 2. Run setup/setup.sql top-to-bottom in a Snowsight worksheet

-- 3. Upload the semantic model to the agent stage
PUT 'file://agent/semantic_model.yaml'
  @ARPU_INTELLIGENCE_DEMO.AGENT.MODELS
  AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- 4. Deploy the Streamlit app
PUT 'file://streamlit/streamlit_app.py'
  @ARPU_INTELLIGENCE_DEMO.ANALYTICS.STREAMLIT_STAGE
  AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

CREATE OR REPLACE STREAMLIT ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARPU_INTELLIGENCE
  ROOT_LOCATION = '@ARPU_INTELLIGENCE_DEMO.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = COMPUTE_WH
  TITLE = 'ARPU Intelligence';
```

## Project Structure

```
arpu-intelligence/
├── README.md                          — This file
├── SKILL.md                           — CoCo context for extending the demo
├── setup/
│   └── setup.sql                      — Full DDL, data generation, ML training
├── streamlit/
│   └── streamlit_app.py               — 6-tab internal ops dashboard
├── agent/
│   └── semantic_model.yaml            — Cortex Analyst semantic model
└── notebook/
    └── ml_pipeline_walkthrough.ipynb  — ML pipeline walkthrough notebook
```

## Prerequisites

- Snowflake account with ACCOUNTADMIN role
- Medium standard warehouse
- `ARPU_INTELLIGENCE_DEMO` database (created by `setup/setup.sql`)

## Snowflake Capabilities Demonstrated

| Capability | Object |
|---|---|
| ML Forecast | `ARPU_INTELLIGENCE_DEMO.ML.ARPU_FORECAST_MODEL` |
| Anomaly Detection | `ARPU_INTELLIGENCE_DEMO.ML.REVENUE_ANOMALY_MODEL` |
| Cortex Search | `ARPU_INTELLIGENCE_DEMO.AGENT.ARTIST_FAQ` |
| Cortex Agent | `ARPU_INTELLIGENCE_DEMO.AGENT.ARTIST_AGENT` |
| Streamlit in Snowflake | `ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARPU_INTELLIGENCE` |

## Sample Questions for "Ask Your Data" Tab

- What are the top 10 artists by total royalties?
- Which platform has the highest average royalty per stream?
- How many artists are at high churn risk?
- What's the average ARPU by genre?
- Which Gold-tier artists have declining streams?
