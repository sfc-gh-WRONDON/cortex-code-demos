# CardWorks Cortex Code Demo — Updated Talk Track
## Includes Pipeline Monitor Dashboard (Aligned to Mitesh's Use Cases)

## Total Time: 50 minutes

---

## Pre-Demo Setup Checklist
- [ ] Open Cortex Code Desktop with the `cardworks_dbt/` project loaded
- [ ] Confirm Snowflake connection to `SFSENORTHAMERICA-WRONDON_AWS1` (connection: "Personal")
- [ ] Verify data exists:
  - `SELECT COUNT(*) FROM CARDWORKS_DEMO.MARTS.FCT_TRANSACTIONS` → 1000
  - `SELECT COUNT(*) FROM CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY` → ~500
- [ ] Pre-launch both Streamlit dashboards:
  - `SNOWFLAKE_CONNECTION_NAME=Personal streamlit run streamlit/fraud_dashboard.py --server.port 8501 --server.headless true`
  - `SNOWFLAKE_CONNECTION_NAME=Personal streamlit run streamlit/pipeline_monitor.py --server.port 8502 --server.headless true`
- [ ] Browser tabs ready: http://localhost:8501 and http://localhost:8502
- [ ] Pre-open these files in tabs:
  - `SKILL.md`
  - `migration_samples/sas_transaction_enrichment.sas`
  - `migration_samples/sp_account_balance.sql`
  - `streamlit/pipeline_monitor.py`

---

## SEGMENT 1: Opening & Context (3 min)

**What you say:**
> "Today I want to show you how Cortex Code accelerates the exact data engineering work your team does every day — taking mainframe data that lands via Snowpark, replacing SAS logic with dbt, monitoring pipeline health, and catching production issues before they become incidents. Everything runs inside Snowflake's trust boundary with the same RBAC and governance you already manage."

**What you show:**
- Cortex Code Desktop open with the project
- Briefly flash Snowsight (mention it's also available inline there)
- Mention CLI option for terminal-focused engineers

**Key point:**
> "Three access methods — Snowsight, CLI, Desktop — same AI, same security, different interface. Your team picks what fits their workflow."

---

## SEGMENT 2: Team Standards with SKILL.md (5 min)

**What you say:**
> "Before we write any code, let me show you the most important file in this project. We call it a SKILL file — it's how you encode your team's standards so Cortex Code follows them automatically. Think of it as your team's institutional knowledge made machine-readable."

**What you show:**
- Open **`SKILL.md`** in the editor
- Walk through each section:
  - Naming conventions (stg_, fct_, dim_)
  - Structure rules (CTEs, date_trunc)
  - Required tests (not_null, unique, accepted_values)
  - Materialization (staging=view, marts=table)
  - **CardWorks business context** (transaction types, card networks, risk indicators)
  - Data sources (RAW_MAINFRAME, RAW_SQLSERVER)
  - **Ingestion validation rules** — minimum row count thresholds, anomaly detection requirements

**Key point:**
> "Your tech lead writes this once. From that point forward, every engineer — junior or senior — produces code that follows these exact standards. No more review comments about naming or missing tests. But here's what matters most for your team: we can encode your ingestion validation rules here too — so nobody ships a pipeline without threshold checks. That doubled-files incident? It gets caught on day one."

---

## SEGMENT 3: Build dbt Staging Models Live (7 min)

**What you say:**
> "Let's pretend we just got a new raw table from the mainframe. I'll ask Cortex Code to create a staging model for it."

**Prompt 1:**
> "Create a staging model for a new table called `cardholders` in the RAW_MAINFRAME schema. It has columns: CRDHLDR_ID, FIRST_NM, LAST_NM, DOB, SSN_HASH, ADDR_LINE1, CITY, STATE, ZIP, EMAIL, PHONE, CRDHLDR_SINCE_DT, IS_ACTIVE, _LOADED_AT. Follow our SKILL.md standards."

- Show the generated `stg_cardholders.sql` — point out CTE pattern, snake_case, IS_ACTIVE filter

**Prompt 2:**
> "Now generate the schema.yml tests for this model. Remember our standards require not_null on the primary key."

- Show the generated tests

**Then show existing models as reference:**
- Open `models/staging/stg_transactions.sql` — "Here's one we prepared earlier"
- Open `models/staging/src_mainframe.yml` — "Source definitions"

**Key point:**
> "Notice every model follows the identical pattern. A new engineer on day one produces the same quality as your most senior person because the standards are encoded in the SKILL file."

---

## SEGMENT 4: SAS-to-dbt Migration (10 min)

**What you say:**
> "This is your exact journey right now — replacing SAS programs with dbt models on data that Snowpark already landed from the mainframe. Let me show you how Cortex Code compresses that timeline."

### Part A: Simple SAS Conversion (6 min)

**What you show:**
- Open **`migration_samples/sas_transaction_enrichment.sas`**
- Walk through key SAS constructs (30 seconds):
  - DATA step with RETAIN (running balance)
  - PROC SQL joins
  - Conditional logic with FORMAT statements

**Prompt:**
> "Convert this SAS program to a dbt model. The source data is already in our RAW_MAINFRAME schema. Follow SKILL.md standards. Explain what each SAS construct maps to."

**What Cortex Code produces:**
- CTEs replacing DATA steps
- Window functions replacing RETAIN
- Standard SQL replacing PROC SQL
- ref() macros for dependencies

**Point to the backup:**
- Open **`models/marts/fct_monthly_txn_summary.sql`** — "Here's what the final converted model looks like"

### Part B: Complexity at Scale (4 min)

**What you show:**
- Open **`migration_samples/sas_risk_scoring.sas`**
- Highlight complexity: multiple DATA steps, MERGE, weighted scoring, arrays

**Prompt:**
> "Convert this SAS risk scoring program to dbt. It calculates account-level risk scores from utilization, payment behavior, and transaction velocity patterns."

**Key callout:**
> "What took your team 2-3 weeks per SAS program — reading the logic, rewriting, testing — now takes 15 minutes. Your engineers validate the business logic instead of burning time on syntax translation."

---

## SEGMENT 5: SQL Server Migration (5 min)

**What you say:**
> "Same principle works for SQL Server. Quick example of a stored procedure conversion."

**What you show:**
- Open **`migration_samples/sp_account_balance.sql`**
- Point out TSQL-specific patterns: temp tables (#), NOLOCK, GETDATE(), ISNULL, DATEDIFF syntax

**Prompt:**
> "Convert this SQL Server stored procedure to a Snowflake dbt model following our SKILL.md standards."

**What Cortex Code does:**
- #temp tables → CTEs
- GETDATE() → CURRENT_DATE()
- ISNULL → COALESCE
- DATEDIFF(DAY, x, y) → DATEDIFF('day', x, y)
- NOLOCK hints removed

**Key point:**
> "Partners have used this pattern to convert hundreds of SQL Server objects in days instead of months."

---

## SEGMENT 6: Pipeline Monitor — The Payoff (13 min)

**What you say:**
> "Everything we just built — staging models, marts, ingestion pipelines — needs to run reliably in production. Mitesh, you mentioned the incident where a vendor doubled their file volume for two months before anyone caught it. Let me show you what Cortex Code built to solve exactly that problem."

### Part A: Show the Dashboard (5 min)

**What you show:**
- Switch to browser tab → **http://localhost:8502** (Pipeline Monitor)
- Walk through the dashboard top to bottom:

**KPI tiles:**
> "7 pipelines, 2 failed in the last 24 hours, 91% success rate over the last week. Your on-call engineer sees this at 6 AM."

**Pipeline Status Grid (left panel):**
- Point to the red `fct_transactions` failure
> "fct_transactions failed because the mainframe batch file didn't land. The error tells you exactly which file is missing and where it should be. No hunting through logs."

**Volume Anomaly Chart (right panel):**
- Select **ACION_COLLECTIONS_FEED** from dropdown
> "Now here's the big one. See this red zone? That's ACION — your collections vendor — doubling their row count for 32 straight days. In your current setup, this went unnoticed for two months. With this dashboard, it triggers a warning on day one."

- Point to the threshold line
> "Yellow line is +30% above baseline. Anything above that turns red. You'd know about this within hours of the first doubled file."

**Key point:**
> "This entire dashboard — the queries, the anomaly detection logic, the Altair charts, the layout — was built by Cortex Code in a single prompt session. Same tool that wrote your dbt models also builds your monitoring layer."

### Part B: AI Root Cause Analysis (4 min)

**What you say:**
> "But dashboards only show you the problem. Your on-call engineer still needs to figure out what to do. Watch this."

**What you show:**
- Click **"Generate Root Cause Analysis"** button
- Wait for Cortex AI (llama3.1-70b) to generate the response

**What it produces (live):**
- Executive summary of current failures
- Root cause bullets: missing SFTP file, upstream dependency chain
- Anomaly explanation: ACION volume doubled, likely duplicate file ingestion
- Prioritized action items: check SFTP, pause ACION ingestion, deduplicate, verify manifest

> "Your engineer gets a prioritized runbook generated from the actual data — not a generic playbook. It knows the ACION feed doubled and suggests deduplication. It knows the mainframe file is missing and tells you to check the SFTP drop zone. This is the difference between a 2-hour incident and a 10-minute resolution."

### Part C: How This Was Built (4 min)

**What you say:**
> "Let me pull back the curtain. This dashboard is a Streamlit app — 250 lines of Python."

**What you show:**
- Switch back to Cortex Code Desktop
- Open **`streamlit/pipeline_monitor.py`**
- Scroll through quickly, highlighting:
  - Connection setup (same pattern as any Snowflake app)
  - SQL queries with window functions for rolling averages
  - Altair chart with anomaly coloring
  - The AI prompt that generates root cause analysis

**Prompt (optional, if time permits):**
> "Add a new section to this dashboard that shows a data freshness heatmap — for each pipeline, show a grid of the last 30 days colored green/yellow/red based on whether the pipeline ran successfully."

- Show Cortex Code generating the new section live

**Key point:**
> "Your data engineering team can go from 'I want pipeline monitoring' to a production-quality dashboard in an afternoon. No BI team engagement, no Jira ticket, no 6-week project. One engineer with Cortex Code."

---

## SEGMENT 7: Security & Governance (4 min)

**What you say:**
> "I know security is paramount for CardWorks. Let me address how Cortex Code fits your governance model."

**Six pillars (conversational, not slides):**

1. **No data leaves Snowflake** — "Your PAN data, customer PII — none of it leaves the Snowflake perimeter."
2. **RBAC-controlled** — "One GRANT statement enables or disables access per role."
3. **Full audit trail** — "Every interaction logged in ACCESS_HISTORY. Your SOX/PCI compliance team can audit it."
4. **Masking policies honored** — "If PAN is masked for a role, Cortex Code sees masked values too."
5. **No model training on your data** — "Contractual guarantee. Your data never trains models."
6. **Network policies apply** — "Existing IP allowlists, PrivateLink — all work. No new firewall rules."

---

## SEGMENT 8: Wrap-Up & Next Steps (3 min)

**What you say:**
> "To recap — in 50 minutes we:
> - Encoded your team standards in a SKILL file so every engineer produces consistent output
> - Built dbt staging models from scratch following those standards
> - Converted SAS programs from your mainframe workflow to production-ready dbt
> - Migrated a SQL Server stored procedure
> - Built a pipeline monitoring dashboard that catches the exact type of incident you described — doubled vendor files, missing mainframe batches — and generates AI-powered root cause analysis
> - All inside your existing Snowflake security framework.
>
> The monitoring dashboard is the one I want to emphasize. Every ingestion pattern your team builds going forward can include built-in validation. And when something does go wrong, the AI tells your on-call engineer what happened and what to do about it — in seconds, not hours."

**Next steps:**
1. Hands-on lab with your 10 engineers — bring your own use cases
2. Half-day SKILL.md workshop to encode CardWorks' exact standards
3. Partner sprint to scope the full SAS migration backlog
4. Deploy pipeline monitoring on your production ingestion patterns

**Close:**
> "The session we're planning for [target date] — your team will get hands-on with all of this. We'll have lab exercises tailored to the ingestion validation, mainframe parsing, and BI acceleration use cases Mitesh outlined. They'll walk away with CoCo installed and running against your real data."

---

## Quick Reference: Asset Locations

| Segment | File to Open | Purpose |
|---------|-------------|---------|
| 2 - Standards | `SKILL.md` | Show team conventions |
| 3 - Staging | `models/staging/stg_transactions.sql` | Reference pattern |
| 3 - Staging | `models/staging/src_mainframe.yml` | Source definitions |
| 4 - SAS Migration | `migration_samples/sas_transaction_enrichment.sas` | Paste for conversion |
| 4 - SAS Migration | `migration_samples/sas_risk_scoring.sas` | Complex example |
| 4 - SAS Backup | `models/marts/fct_monthly_txn_summary.sql` | Pre-built output |
| 5 - SQL Server | `migration_samples/sp_account_balance.sql` | Paste for conversion |
| 6 - Pipeline Monitor | Browser: http://localhost:8502 | Live dashboard |
| 6 - Pipeline Source | `streamlit/pipeline_monitor.py` | Show the code |
| 6 - Pipeline Data | `setup/pipeline_data_seed.sql` | How data was created |

---

## Timing Summary

| Segment | Duration | Running Total |
|---------|----------|---------------|
| 1. Opening & Context | 3 min | 3 min |
| 2. SKILL.md Standards | 5 min | 8 min |
| 3. Build Staging Live | 7 min | 15 min |
| 4. SAS-to-dbt Migration | 10 min | 25 min |
| 5. SQL Server Migration | 5 min | 30 min |
| 6. Pipeline Monitor (payoff) | 13 min | 43 min |
| 7. Security & Governance | 4 min | 47 min |
| 8. Wrap-Up & Next Steps | 3 min | 50 min |

---

## Fallback Plan (If Live Demo Breaks)
- All staging/mart models are pre-built in `CARDWORKS_DEMO` database
- Pipeline Monitor has pre-loaded data — just open the browser tab
- If Streamlit won't launch, show the `.py` source and describe what it renders
- AI Root Cause button can be simulated by running the prompt directly in Cortex Code chat
- Show pre-built files instead of generating live if CoCo is slow

---

## Key Narrative Thread

The demo tells one continuous story:

1. **Standards** → "We encoded your rules so the AI follows them"
2. **Build** → "Now watch it generate production-quality code instantly"
3. **Migrate** → "Your SAS backlog gets compressed from months to days"
4. **Monitor** → "And when things break in production, you know within minutes — not months"
5. **AI Root Cause** → "The AI doesn't just show you the problem. It tells you how to fix it."

The through-line for Mitesh: **"Your team spends less time on manual grunt work and more time on the logic that matters. From ingestion to monitoring, Cortex Code handles the pattern — your engineers handle the judgment."**
