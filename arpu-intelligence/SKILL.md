# SKILL.md — arpu_intelligence_demo

## Purpose
Build, extend, or regenerate the ARPU Intelligence demo environment — a Snowflake Cortex AI showcase for music/creator distribution platforms.

## When to Use
When a user asks to create ML models, modify the Streamlit dashboard, update the semantic model, extend the Cortex Agent, or retrain predictions for this demo.

## Demo Architecture

```
RAW.ARTISTS + RAW.TRANSACTIONS + RAW.FEATURE_ADOPTION
    │
    ▼
ANALYTICS.ARTIST_ARPU_TIMESERIES  (monthly ARPU per artist)
ANALYTICS.ARTIST_FEATURES         (behavioral feature matrix)
    │
    ▼
ML.FORECAST_TRAINING_DATA         (50 artists, 10+ months history)
ML.CHURN_TRAINING_DATA            (feature matrix with churn labels)
    │
    ▼
ML.ARPU_FORECAST_MODEL            (SNOWFLAKE.ML.FORECAST)
ML.REVENUE_ANOMALY_MODEL          (SNOWFLAKE.ML.ANOMALY_DETECTION)
    │
    ▼
ML.PREDICTIONS                    (churn score + ARPU forecast + feature recs per artist)
    │
    ├── ANALYTICS.ARPU_INTELLIGENCE (Streamlit — internal ops dashboard)
    └── AGENT.ARTIST_AGENT          (Cortex Agent — external artist-facing)
```

## Snowflake Features

- `SNOWFLAKE.ML.FORECAST` — time-series ARPU prediction
- `SNOWFLAKE.ML.ANOMALY_DETECTION` — revenue anomaly detection
- `SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', ...)` — AI recommendations
- `CREATE CORTEX SEARCH SERVICE` — artist FAQ retrieval
- `CREATE AGENT` — multi-tool orchestration (Analyst + Search)
- Streamlit in Snowflake — internal ops dashboard
- Semantic Model YAML — Cortex Analyst text-to-SQL grounding

## Database Convention
All objects use the `ARPU_INTELLIGENCE_DEMO` database with four schemas: `RAW`, `ANALYTICS`, `ML`, `AGENT`.

Always use fully qualified names: `ARPU_INTELLIGENCE_DEMO.<SCHEMA>.<OBJECT>`

## Streamlit Compatibility Notes (Streamlit-in-Snowflake)
- Do NOT use `st.scatter_chart` — use `altair` for scatter plots
- Do NOT use `color=` parameter in `st.line_chart` — pivot data into columns instead
- Do NOT use `hide_index=True` in `st.dataframe`
- Do NOT use `st.container(border=True)`
- Use `st.markdown("---")` for dividers

## Key Files
- `streamlit/streamlit_app.py` — dashboard source (6 tabs: ARPU Trends, Churn Risk, Feature Impact, AI Recommendations, Forecasts, Ask Your Data)
- `agent/semantic_model.yaml` — Cortex Analyst semantic model
- `setup/setup.sql` — complete DDL + data generation script (set `demo_db` and `demo_wh` at the top)
- `notebook/ml_pipeline_walkthrough.ipynb` — step-by-step ML pipeline walkthrough
