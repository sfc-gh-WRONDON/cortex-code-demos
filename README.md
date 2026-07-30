# Cortex Code Demos

Reusable demo assets for showcasing Snowflake Cortex Code to customers and field teams.

## CardWorks — Data Engineering & Pipeline Monitoring

A 50-minute hands-on demo built for CardWorks (financial services / credit union card programs) that demonstrates:

1. **SKILL.md Standards** — Encode team conventions so CoCo generates consistent dbt models
2. **Live Staging Model Build** — Generate dbt models from raw mainframe table descriptions
3. **SAS-to-dbt Migration** — Convert legacy SAS programs to production-ready dbt models
4. **SQL Server Migration** — Convert T-SQL stored procedures to Snowflake SQL
5. **Pipeline Health Monitor** — Streamlit dashboard with anomaly detection and AI root cause analysis

### Quick Start

```bash
# 1. Clone and open in Cortex Code Desktop
cd V2_Cardworks_Demo

# 2. Set up the demo data (run once)
# Execute setup/pipeline_data_seed.sql in Snowsight against CARDWORKS_DEMO database

# 3. Launch the Pipeline Monitor locally
SNOWFLAKE_CONNECTION_NAME=Personal streamlit run streamlit/pipeline_monitor.py --server.port 8502

# 4. Reset between demos
rm -f models/staging/*.sql models/staging/schema.yml models/marts/*
```

### Project Structure

```
├── SKILL.md                     — CoCo reads this for dbt standards
├── models/staging/              — EMPTY (CoCo generates live in demo)
├── models/marts/                — EMPTY (CoCo generates live in demo)
├── migration_samples/           — SAS + SQL Server files for live conversion
├── streamlit/                   — Pipeline Monitor + Fraud Dashboard (built apps)
├── setup/                       — SQL to seed PIPELINE_RUN_HISTORY data
├── deploy/                      — SiS deployment manifest for Snowflake hosting
├── demo_backup/                 — Pre-built models as fallback if CoCo is slow
└── Notes_v3.md                  — Full 50-min talk track with timing
```

### Prerequisites

- Cortex Code Desktop connected to a Snowflake account
- `CARDWORKS_DEMO` database with `RAW_MAINFRAME` and `MARTS` schemas
- `PIPELINE_RUN_HISTORY` table (created by `setup/pipeline_data_seed.sql`)

### Talk Track

See [Notes_v3.md](Notes_v3.md) for the full timed demo script with what to say, what to show, and what to prompt.
