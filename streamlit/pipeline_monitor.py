import os
import streamlit as st
import snowflake.connector
import pandas as pd
import altair as alt
from datetime import datetime

st.set_page_config(
    page_title="CardWorks | Pipeline Monitor",
    layout="wide",
    page_icon="🔧",
)

st.markdown("""
<style>
[data-testid="stMetricValue"] { font-size: 1.6rem; }
.block-container { padding-top: 1.5rem; }
</style>
""", unsafe_allow_html=True)


# ─── Connection ───────────────────────────────────────────────────────────────

def get_connection():
    if "conn" not in st.session_state or st.session_state.conn.is_closed():
        st.session_state.conn = snowflake.connector.connect(
            connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME") or "Personal"
        )
    return st.session_state.conn


# ─── Data loaders ─────────────────────────────────────────────────────────────

@st.cache_data(ttl=60)
def load_kpis():
    return pd.read_sql("""
        SELECT
            COUNT(DISTINCT pipeline_name)                                              AS total_pipelines,
            SUM(IFF(status = 'FAILED'  AND run_date >= DATEADD('day',-1,CURRENT_DATE()), 1, 0)) AS failed_24h,
            SUM(IFF(status = 'WARNING' AND run_date >= DATEADD('day',-7,CURRENT_DATE()), 1, 0)) AS warnings_7d,
            ROUND(AVG(IFF(status != 'RUNNING', duration_seconds, NULL)), 0)           AS avg_duration_sec,
            ROUND(
                100.0 * SUM(IFF(status = 'SUCCESS', 1, 0))
                      / NULLIF(SUM(IFF(status != 'RUNNING', 1, 0)), 0)
            , 1)                                                                       AS success_rate_pct
        FROM CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY
        WHERE run_date >= DATEADD('day', -7, CURRENT_DATE())
    """, get_connection())


@st.cache_data(ttl=60)
def load_pipeline_summary():
    return pd.read_sql("""
        WITH latest AS (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY pipeline_name ORDER BY run_start_ts DESC) AS rn
            FROM CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY
        )
        SELECT
            pipeline_name,
            source_system,
            pipeline_type,
            run_date                                                                 AS last_run_date,
            duration_seconds,
            rows_loaded,
            rows_expected,
            ROUND(rows_loaded / NULLIF(rows_expected, 0) * 100, 1)                  AS volume_pct,
            status,
            error_message
        FROM latest
        WHERE rn = 1
        ORDER BY
            CASE status WHEN 'FAILED' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
            pipeline_name
    """, get_connection())


@st.cache_data(ttl=60)
def load_volume_trend(pipeline_name: str):
    # pipeline_name comes from a dropdown of known DB values — safe to interpolate
    return pd.read_sql(f"""
        SELECT
            run_date,
            rows_loaded,
            rows_expected,
            status,
            AVG(rows_loaded) OVER (
                PARTITION BY pipeline_name
                ORDER BY run_date
                ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
            )::INT AS rolling_14d_avg
        FROM CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY
        WHERE pipeline_name = '{pipeline_name}'
          AND status != 'RUNNING'
        ORDER BY run_date
    """, get_connection())


@st.cache_data(ttl=60)
def load_recent_runs():
    return pd.read_sql("""
        SELECT
            run_id, pipeline_name, source_system, run_date, run_start_ts,
            duration_seconds, rows_loaded, rows_expected,
            status, triggered_by, error_message
        FROM CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY
        ORDER BY run_start_ts DESC
        LIMIT 400
    """, get_connection())


# ─── AI root cause ────────────────────────────────────────────────────────────

def generate_ai_summary(failures_df: pd.DataFrame, anomalies_df: pd.DataFrame) -> str:
    cur = get_connection().cursor()

    failure_lines = "\n".join(
        f"  • {r['PIPELINE_NAME']} ({r['LAST_RUN_DATE']}): {r['ERROR_MESSAGE'] or 'no error detail'}"
        for _, r in failures_df.iterrows()
    ) or "  None"

    anomaly_lines = "\n".join(
        f"  • {r['PIPELINE_NAME']}: {int(r['ROWS_LOADED'] or 0):,} rows loaded "
        f"vs {int(r['ROWS_EXPECTED'] or 0):,} expected ({r['VOLUME_PCT']:.0f}% of expected)"
        for _, r in anomalies_df.iterrows()
    ) or "  None detected"

    prompt = (
        "You are a data engineering on-call assistant for CardWorks, a financial services company "
        "running credit card and merchant services on Snowflake.\n\n"
        "Analyze the following pipeline monitoring data and respond with a concise incident report.\n\n"
        f"ACTIVE FAILURES:\n{failure_lines}\n\n"
        f"VOLUME ANOMALIES (rows outside ±30% of expected):\n{anomaly_lines}\n\n"
        "Your response must contain exactly these four sections:\n"
        "1. Executive Summary (2 sentences)\n"
        "2. Root Cause Analysis — one bullet per failure\n"
        "3. Volume Anomaly Explanation — flag any that suggest duplicate ingestion\n"
        "4. Prioritized Action Items — numbered, most urgent first\n\n"
        "Keep each section short and actionable. Write for an on-call data engineer."
    )

    cur.execute("SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', %s)", (prompt,))
    row = cur.fetchone()
    return row[0] if row else "Unable to generate summary."


# ─── Main UI ──────────────────────────────────────────────────────────────────

st.title("CardWorks Data Pipeline Monitor")
st.caption(
    f"Last refreshed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  ·  "
    "Data: CARDWORKS_DEMO.MARTS.PIPELINE_RUN_HISTORY  ·  "
    "Refreshes every 60s"
)

try:
    kpis        = load_kpis()
    summary     = load_pipeline_summary()
    recent_runs = load_recent_runs()
except Exception as e:
    st.error(f"Could not connect to Snowflake: {e}")
    st.stop()


# ── KPI tiles ─────────────────────────────────────────────────────────────────

k = kpis.iloc[0]
failed_24h   = int(k["FAILED_24H"] or 0)
warnings_7d  = int(k["WARNINGS_7D"] or 0)
avg_dur_sec  = int(k["AVG_DURATION_SEC"] or 0)
success_rate = float(k["SUCCESS_RATE_PCT"] or 0)

c1, c2, c3, c4, c5 = st.columns(5)
c1.metric("Active Pipelines",   int(k["TOTAL_PIPELINES"]))
c2.metric("Failed (last 24 h)", failed_24h,
          delta="needs attention" if failed_24h else "all clear",
          delta_color="inverse")
c3.metric("Warnings (7 d)",     warnings_7d,  delta_color="inverse")
c4.metric("Avg Run Time",       f"{avg_dur_sec // 60}m {avg_dur_sec % 60}s")
c5.metric("7-Day Success Rate", f"{success_rate:.1f}%",
          delta_color="normal" if success_rate >= 95 else "inverse")

st.divider()


# ── Pipeline status grid  |  Volume anomaly chart ─────────────────────────────

left, right = st.columns([2, 3], gap="large")

STATUS_ICON = {"SUCCESS": "🟢", "WARNING": "🟡", "FAILED": "🔴"}

with left:
    st.subheader("Pipeline Status")

    for _, row in summary.iterrows():
        icon  = STATUS_ICON.get(row["STATUS"], "⚪")
        label = f"{icon} **{row['PIPELINE_NAME']}**"
        # Failures and warnings start expanded
        expanded = row["STATUS"] in ("FAILED", "WARNING")

        with st.expander(label, expanded=expanded):
            ca, cb = st.columns(2)

            with ca:
                st.markdown(f"**Source:** `{row['SOURCE_SYSTEM']}`")
                st.markdown(f"**Type:** {row['PIPELINE_TYPE']}")
                st.markdown(f"**Last run:** {row['LAST_RUN_DATE']}")

            with cb:
                dur = int(row["DURATION_SECONDS"] or 0)
                st.markdown(f"**Duration:** {dur // 60}m {dur % 60}s")

                vol = float(row["VOLUME_PCT"] or 0)
                rows_loaded = int(row["ROWS_LOADED"] or 0)
                if vol > 150 or (0 < vol < 70):
                    vol_badge = "🔴"
                elif vol > 130 or (vol < 85 and vol > 0):
                    vol_badge = "🟡"
                else:
                    vol_badge = "🟢"
                st.markdown(f"**Rows loaded:** {rows_loaded:,} {vol_badge} ({vol:.0f}% of expected)")

            if pd.notna(row["ERROR_MESSAGE"]):
                st.error(row["ERROR_MESSAGE"])


with right:
    st.subheader("Ingestion Volume Trend")

    pipeline_names = summary["PIPELINE_NAME"].tolist()
    default_idx = (
        pipeline_names.index("ACION_COLLECTIONS_FEED")
        if "ACION_COLLECTIONS_FEED" in pipeline_names else 0
    )
    selected = st.selectbox("Select pipeline", options=pipeline_names, index=default_idx)

    if selected:
        trend = load_volume_trend(selected)

        if not trend.empty:
            # Compute anomaly flag and threshold for chart annotations
            latest_expected = int(trend["ROWS_EXPECTED"].iloc[-1])
            upper_thresh    = latest_expected * 1.30
            lower_thresh    = latest_expected * 0.70

            trend["ANOMALY"] = trend["ROWS_LOADED"] > upper_thresh

            # Actual line coloured by anomaly
            actual = (
                alt.Chart(trend)
                .mark_line(strokeWidth=2)
                .encode(
                    x=alt.X("RUN_DATE:T", title="Date"),
                    y=alt.Y("ROWS_LOADED:Q", title="Rows Loaded"),
                    color=alt.condition(
                        alt.datum.ANOMALY,
                        alt.value("#dc2626"),   # red for anomalous days
                        alt.value("#2563eb"),   # blue for normal days
                    ),
                    tooltip=[
                        alt.Tooltip("RUN_DATE:T",       title="Date"),
                        alt.Tooltip("ROWS_LOADED:Q",    title="Rows Loaded", format=","),
                        alt.Tooltip("ROWS_EXPECTED:Q",  title="Expected",    format=","),
                        alt.Tooltip("STATUS:N",         title="Status"),
                    ],
                )
            )

            points = (
                alt.Chart(trend)
                .mark_point(filled=True, size=35)
                .encode(
                    x="RUN_DATE:T",
                    y="ROWS_LOADED:Q",
                    color=alt.condition(
                        alt.datum.ANOMALY,
                        alt.value("#dc2626"),
                        alt.value("#2563eb"),
                    ),
                )
            )

            rolling = (
                alt.Chart(trend)
                .mark_line(strokeDash=[4, 3], strokeWidth=1.5, color="#9ca3af")
                .encode(
                    x="RUN_DATE:T",
                    y=alt.Y("ROLLING_14D_AVG:Q", title=""),
                    tooltip=[alt.Tooltip("ROLLING_14D_AVG:Q", title="14-day avg", format=",")],
                )
            )

            threshold_df = pd.DataFrame({"y": [upper_thresh]})
            threshold_rule = (
                alt.Chart(threshold_df)
                .mark_rule(strokeDash=[6, 3], color="#f59e0b", strokeWidth=1.5)
                .encode(y=alt.Y("y:Q", title=""))
            )

            chart = (
                (actual + points + rolling + threshold_rule)
                .properties(height=310)
                .interactive()
            )
            st.altair_chart(chart, use_container_width=True)

            # Legend callout
            col_leg1, col_leg2, col_leg3 = st.columns(3)
            col_leg1.caption("🔵 Actual row count")
            col_leg2.caption("⬜ 14-day rolling avg")
            col_leg3.caption("🟡 Upper threshold (+30%)")

            anomaly_count = int(trend["ANOMALY"].sum())
            if anomaly_count > 0:
                st.warning(
                    f"⚠️ **{anomaly_count} day(s)** where row count exceeded the +30% threshold "
                    f"({int(upper_thresh):,} rows). Red segments indicate potential duplicate ingestion."
                )
        else:
            st.info("No data found for this pipeline.")

st.divider()


# ── Run log ───────────────────────────────────────────────────────────────────

st.subheader("Pipeline Run Log")

fc1, fc2, fc3 = st.columns(3)
with fc1:
    status_filter = st.multiselect(
        "Status", ["SUCCESS", "WARNING", "FAILED"], default=["FAILED", "WARNING"]
    )
with fc2:
    pipeline_filter = st.multiselect(
        "Pipeline", options=sorted(recent_runs["PIPELINE_NAME"].unique().tolist()), default=[]
    )
with fc3:
    days_back = st.slider("Days to show", min_value=1, max_value=90, value=14)

filtered = recent_runs.copy()
if status_filter:
    filtered = filtered[filtered["STATUS"].isin(status_filter)]
if pipeline_filter:
    filtered = filtered[filtered["PIPELINE_NAME"].isin(pipeline_filter)]
cutoff = pd.Timestamp.now() - pd.Timedelta(days=days_back)
filtered = filtered[pd.to_datetime(filtered["RUN_DATE"]) >= cutoff]

# Format columns for display
display = filtered.copy()
display["STATUS"]      = display["STATUS"].map({"SUCCESS": "✅ SUCCESS", "WARNING": "⚠️ WARNING", "FAILED": "❌ FAILED"})
display["DURATION"]    = display["DURATION_SECONDS"].apply(
    lambda s: f"{int(s) // 60}m {int(s) % 60}s" if pd.notnull(s) and s > 0 else "—"
)
display["ROWS_LOADED"] = display["ROWS_LOADED"].apply(
    lambda x: f"{int(x):,}" if pd.notnull(x) else "—"
)

st.dataframe(
    display[[
        "PIPELINE_NAME", "SOURCE_SYSTEM", "RUN_DATE",
        "STATUS", "DURATION", "ROWS_LOADED", "TRIGGERED_BY", "ERROR_MESSAGE",
    ]],
    use_container_width=True,
    hide_index=True,
    column_config={
        "PIPELINE_NAME": st.column_config.TextColumn("Pipeline",       width="medium"),
        "SOURCE_SYSTEM":  st.column_config.TextColumn("Source",        width="small"),
        "RUN_DATE":       st.column_config.DateColumn("Run Date",      width="small"),
        "STATUS":         st.column_config.TextColumn("Status",        width="medium"),
        "DURATION":       st.column_config.TextColumn("Duration",      width="small"),
        "ROWS_LOADED":    st.column_config.TextColumn("Rows Loaded",   width="small"),
        "TRIGGERED_BY":   st.column_config.TextColumn("Triggered By",  width="small"),
        "ERROR_MESSAGE":  st.column_config.TextColumn("Error Detail",  width="large"),
    },
)
st.caption(f"Showing {len(filtered):,} runs · filtered from last {days_back} days")

st.divider()


# ── AI Root Cause Analysis ────────────────────────────────────────────────────

st.subheader("AI Root Cause Analysis")

failures_df  = summary[summary["STATUS"] == "FAILED"]
anomalies_df = summary[
    (summary["VOLUME_PCT"] > 130) | ((summary["VOLUME_PCT"] > 0) & (summary["VOLUME_PCT"] < 70))
]

if not failures_df.empty or not anomalies_df.empty:
    parts = []
    if not failures_df.empty:
        parts.append(f"**{len(failures_df)} pipeline(s) currently failing**")
    if not anomalies_df.empty:
        parts.append(f"**{len(anomalies_df)} pipeline(s) with volume anomalies**")
    st.info("Detected: " + "  ·  ".join(parts))
else:
    st.success("✅ All pipelines healthy — no active failures or volume anomalies detected.")

btn_label = (
    "🤖  Generate Root Cause Analysis"
    if (not failures_df.empty or not anomalies_df.empty)
    else "🤖  Generate Health Summary"
)

if st.button(btn_label, type="primary"):
    with st.spinner("Analyzing pipeline data with Cortex AI (llama3.1-70b)..."):
        ai_output = generate_ai_summary(failures_df, anomalies_df)
    st.markdown(ai_output)
