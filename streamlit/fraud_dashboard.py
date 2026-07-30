import streamlit as st
import snowflake.connector
import pandas as pd
import os

st.set_page_config(page_title="CardWorks Fraud Detection", layout="wide")
st.title("CardWorks Transaction Fraud Detection Dashboard")

def get_connection():
    if 'conn' not in st.session_state or st.session_state.conn.is_closed():
        st.session_state.conn = snowflake.connector.connect(
            connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME") or "Personal"
        )
    return st.session_state.conn

@st.cache_data(ttl=300)
def load_flagged_transactions():
    conn = get_connection()
    query = """
    SELECT
        transaction_id,
        account_id,
        merchant_name,
        merchant_category_description,
        transaction_amount,
        transaction_date,
        card_network,
        is_card_present,
        is_international,
        risk_level
    FROM CARDWORKS_DEMO.MARTS.FCT_TRANSACTIONS
    WHERE risk_level = 'HIGH'
      AND transaction_date >= DATEADD('day', -90, CURRENT_DATE())
    ORDER BY transaction_date DESC, transaction_amount DESC
    LIMIT 500
    """
    return pd.read_sql(query, conn)

@st.cache_data(ttl=300)
def load_risk_summary():
    conn = get_connection()
    query = """
    SELECT
        risk_level,
        COUNT(*) AS transaction_count,
        SUM(transaction_amount) AS total_amount,
        AVG(transaction_amount) AS avg_amount
    FROM CARDWORKS_DEMO.MARTS.FCT_TRANSACTIONS
    WHERE transaction_date >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY risk_level
    ORDER BY CASE risk_level WHEN 'HIGH' THEN 1 WHEN 'MODERATE' THEN 2 ELSE 3 END
    """
    return pd.read_sql(query, conn)

@st.cache_data(ttl=300)
def load_daily_trend():
    conn = get_connection()
    query = """
    SELECT
        transaction_date,
        risk_level,
        COUNT(*) AS flagged_count,
        SUM(transaction_amount) AS flagged_amount
    FROM CARDWORKS_DEMO.MARTS.FCT_TRANSACTIONS
    WHERE risk_level IN ('HIGH', 'MODERATE')
      AND transaction_date >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY transaction_date, risk_level
    ORDER BY transaction_date
    """
    return pd.read_sql(query, conn)

@st.cache_data(ttl=300)
def load_category_breakdown():
    conn = get_connection()
    query = """
    SELECT
        merchant_category_description,
        COUNT(*) AS high_risk_count,
        SUM(transaction_amount) AS total_amount
    FROM CARDWORKS_DEMO.MARTS.FCT_TRANSACTIONS
    WHERE risk_level = 'HIGH'
      AND transaction_date >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY merchant_category_description
    ORDER BY high_risk_count DESC
    LIMIT 10
    """
    return pd.read_sql(query, conn)

risk_summary = load_risk_summary()
flagged_txns = load_flagged_transactions()
daily_trend = load_daily_trend()
category_breakdown = load_category_breakdown()

st.subheader("Risk Summary (Last 90 Days)")
col1, col2, col3, col4 = st.columns(4)

if not risk_summary.empty:
    high_risk = risk_summary[risk_summary['RISK_LEVEL'] == 'HIGH']
    moderate_risk = risk_summary[risk_summary['RISK_LEVEL'] == 'MODERATE']

    with col1:
        count = int(high_risk['TRANSACTION_COUNT'].values[0]) if not high_risk.empty else 0
        st.metric("High Risk Transactions", f"{count:,}")
    with col2:
        amount = float(high_risk['TOTAL_AMOUNT'].values[0]) if not high_risk.empty else 0
        st.metric("High Risk Volume", f"${amount:,.0f}")
    with col3:
        count = int(moderate_risk['TRANSACTION_COUNT'].values[0]) if not moderate_risk.empty else 0
        st.metric("Moderate Risk Transactions", f"{count:,}")
    with col4:
        total = risk_summary['TRANSACTION_COUNT'].sum()
        high_count = int(high_risk['TRANSACTION_COUNT'].values[0]) if not high_risk.empty else 0
        rate = (high_count / total * 100) if total > 0 else 0
        st.metric("High Risk Rate", f"{rate:.2f}%")

st.divider()

left_col, right_col = st.columns(2)

with left_col:
    st.subheader("Daily Fraud Alerts Trend")
    if not daily_trend.empty:
        st.line_chart(
            daily_trend.pivot(index='TRANSACTION_DATE', columns='RISK_LEVEL', values='FLAGGED_COUNT'),
            use_container_width=True
        )

with right_col:
    st.subheader("Top Merchant Categories (High Risk)")
    if not category_breakdown.empty:
        st.bar_chart(
            category_breakdown.set_index('MERCHANT_CATEGORY_DESCRIPTION')['HIGH_RISK_COUNT'],
            use_container_width=True
        )

st.divider()
st.subheader("Flagged Transactions (Last 90 Days)")

col_filter1, col_filter2 = st.columns(2)
with col_filter1:
    network_filter = st.multiselect(
        "Filter by Card Network",
        options=flagged_txns['CARD_NETWORK'].unique().tolist() if not flagged_txns.empty else [],
        default=[]
    )
with col_filter2:
    min_amount = st.number_input("Minimum Amount ($)", value=0, step=1000)

filtered = flagged_txns.copy()
if network_filter:
    filtered = filtered[filtered['CARD_NETWORK'].isin(network_filter)]
if min_amount > 0:
    filtered = filtered[filtered['TRANSACTION_AMOUNT'] >= min_amount]

st.dataframe(filtered, use_container_width=True, hide_index=True)
st.caption(f"Showing {len(filtered)} of {len(flagged_txns)} flagged transactions")

st.divider()
st.subheader("AI-Generated Fraud Summary")

def generate_ai_summary():
    conn = get_connection()
    cur = conn.cursor()

    high_count = int(high_risk['TRANSACTION_COUNT'].values[0]) if not high_risk.empty else 0
    high_volume = float(high_risk['TOTAL_AMOUNT'].values[0]) if not high_risk.empty else 0
    mod_count = int(moderate_risk['TRANSACTION_COUNT'].values[0]) if not moderate_risk.empty else 0
    total_txns = int(risk_summary['TRANSACTION_COUNT'].sum())
    top_categories = category_breakdown['MERCHANT_CATEGORY_DESCRIPTION'].tolist()[:5] if not category_breakdown.empty else []

    prompt = f"""You are a fraud analytics assistant for a credit union card program.
Summarize the following fraud detection findings from the last 90 days in 3-4 concise bullet points.
Include actionable recommendations for the fraud operations team.

Data:
- Total transactions analyzed: {total_txns:,}
- High risk transactions: {high_count} totaling ${high_volume:,.0f}
- Moderate risk transactions: {mod_count}
- High risk rate: {(high_count/total_txns*100) if total_txns > 0 else 0:.2f}%
- Top merchant categories with high risk flags: {', '.join(top_categories)}
- Flagged transactions include international and card-not-present patterns
"""

    cur.execute(
        "SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', %s) AS summary",
        (prompt,)
    )
    result = cur.fetchone()
    return result[0] if result else "Unable to generate summary."

if st.button("Generate AI Summary", type="primary"):
    with st.spinner("Analyzing fraud patterns with Cortex AI..."):
        summary = generate_ai_summary()
    st.markdown(summary)
