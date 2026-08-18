"""
ARPU Intelligence Dashboard
Internal tool for data/product team to monitor artist ARPU,
ML-powered churn risk, feature adoption impact, and AI recommendations.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="ARPU Intelligence", layout="wide")

session = get_active_session()

# --- Header ---
st.title("ARPU Intelligence")
st.caption("Internal dashboard — ML-powered insights for data & product teams")

# --- KPI Row ---
kpi_data = session.sql("""
    SELECT 
        COUNT(DISTINCT a.artist_id) AS total_artists,
        ROUND(AVG(af.current_arpu), 2) AS avg_arpu,
        ROUND(AVG(CASE WHEN af.churn_risk_label = 'High' THEN af.current_arpu END), 2) AS avg_high_risk_arpu,
        SUM(CASE WHEN af.churn_risk_label = 'High' THEN 1 ELSE 0 END) AS high_risk_count,
        ROUND(SUM(af.current_arpu), 0) AS total_monthly_revenue
    FROM ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARTIST_FEATURES af
    JOIN ARPU_INTELLIGENCE_DEMO.RAW.ARTISTS a ON a.artist_id = af.artist_id
""").to_pandas()

col1, col2, col3, col4, col5 = st.columns(5)
col1.metric("Total Artists", f"{kpi_data['TOTAL_ARTISTS'][0]:,}")
col2.metric("Avg ARPU", f"${kpi_data['AVG_ARPU'][0]:.2f}")
col3.metric("Monthly Revenue", f"${kpi_data['TOTAL_MONTHLY_REVENUE'][0]:,.0f}")
col4.metric("High Risk Artists", f"{kpi_data['HIGH_RISK_COUNT'][0]:,}")
col5.metric("Avg High-Risk ARPU", f"${kpi_data['AVG_HIGH_RISK_ARPU'][0]:.2f}")

st.divider()

# --- Tabs ---
tab1, tab2, tab3, tab4, tab5, tab6 = st.tabs([
    "📊 ARPU Trends", "⚠️ Churn Risk", "🚀 Feature Impact",
    "🔮 AI Recommendations", "📈 Forecasts", "💬 Ask Your Data"
])

# --- Tab 1: ARPU Trends ---
with tab1:
    st.subheader("Portfolio ARPU Over Time")
    
    arpu_trend = session.sql("""
        SELECT 
            t.period_month,
            a.tier,
            ROUND(AVG(t.arpu_usd), 2) AS avg_arpu
        FROM ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARTIST_ARPU_TIMESERIES t
        JOIN ARPU_INTELLIGENCE_DEMO.RAW.ARTISTS a ON a.artist_id = t.artist_id
        GROUP BY t.period_month, a.tier
        ORDER BY t.period_month
    """).to_pandas()
    
    # Pivot so each tier is a column (compatible with SiS Streamlit version)
    arpu_pivot = arpu_trend.pivot(index="PERIOD_MONTH", columns="TIER", values="AVG_ARPU")
    st.line_chart(arpu_pivot)
    
    col_a, col_b = st.columns(2)
    with col_a:
        st.subheader("ARPU by Genre")
        genre_arpu = session.sql("""
            SELECT a.genre, ROUND(AVG(af.current_arpu), 2) AS avg_arpu, COUNT(*) AS artists
            FROM ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARTIST_FEATURES af
            JOIN ARPU_INTELLIGENCE_DEMO.RAW.ARTISTS a ON a.artist_id = af.artist_id
            GROUP BY a.genre ORDER BY avg_arpu DESC
        """).to_pandas()
        st.bar_chart(genre_arpu, x="GENRE", y="AVG_ARPU")
    
    with col_b:
        st.subheader("ARPU by Country (Top 10)")
        country_arpu = session.sql("""
            SELECT a.country, ROUND(AVG(af.current_arpu), 2) AS avg_arpu, COUNT(*) AS artists
            FROM ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARTIST_FEATURES af
            JOIN ARPU_INTELLIGENCE_DEMO.RAW.ARTISTS a ON a.artist_id = af.artist_id
            GROUP BY a.country ORDER BY avg_arpu DESC LIMIT 10
        """).to_pandas()
        st.bar_chart(country_arpu, x="COUNTRY", y="AVG_ARPU")

# --- Tab 2: Churn Risk ---
with tab2:
    st.subheader("Churn Risk Heatmap")
    st.caption("Artists plotted by ARPU vs. Churn Score — focus on High Value / High Risk quadrant")
    
    churn_scatter = session.sql("""
        SELECT 
            p.artist_id,
            a.artist_name,
            a.tier,
            a.genre,
            af.current_arpu,
            p.churn_score,
            p.churn_risk_label,
            p.top_recommended_feature
        FROM ARPU_INTELLIGENCE_DEMO.ML.PREDICTIONS p
        JOIN ARPU_INTELLIGENCE_DEMO.RAW.ARTISTS a ON a.artist_id = p.artist_id
        JOIN ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARTIST_FEATURES af ON af.artist_id = p.artist_id
        WHERE af.current_arpu > 0
        ORDER BY p.churn_score DESC
    """).to_pandas()
    
    # Use altair for scatter (st.scatter_chart not available in this SiS version)
    import altair as alt
    scatter = alt.Chart(churn_scatter).mark_circle(size=40, opacity=0.6).encode(
        x=alt.X('CHURN_SCORE:Q', title='Churn Score'),
        y=alt.Y('CURRENT_ARPU:Q', title='Current ARPU ($)'),
        color=alt.Color('CHURN_RISK_LABEL:N', title='Risk Level',
                        scale=alt.Scale(domain=['Low','Medium','High'], range=['#10B981','#F59E0B','#EF4444'])),
        tooltip=['ARTIST_NAME','TIER','GENRE','CURRENT_ARPU','CHURN_SCORE']
    ).properties(width=700, height=400)
    st.altair_chart(scatter, use_container_width=True)
    
    st.subheader("High Value / High Risk Artists (Top Priority)")
    high_risk = churn_scatter[
        (churn_scatter['CHURN_RISK_LABEL'] == 'High') & 
        (churn_scatter['CURRENT_ARPU'] > churn_scatter['CURRENT_ARPU'].median())
    ].sort_values('CURRENT_ARPU', ascending=False).head(20)
    
    st.dataframe(
        high_risk[['ARTIST_NAME', 'TIER', 'GENRE', 'CURRENT_ARPU', 'CHURN_SCORE', 'TOP_RECOMMENDED_FEATURE']],
        use_container_width=True
    )

# --- Tab 3: Feature Impact ---
with tab3:
    st.subheader("Feature Adoption vs. Revenue Lift")
    st.caption("Features ranked by proven revenue impact — compare to current adoption rate")
    
    feature_impact = session.sql("""
        WITH feature_lift AS (
            SELECT column1 AS feature_name, column2 AS lift_pct FROM VALUES
            ('Playlist Pitching', 32), ('Distribution Plus', 41), 
            ('Sync Licensing', 55), ('Analytics Dashboard', 18),
            ('Smart Links', 9), ('Social Clip Tool', 14)
        ),
        adoption AS (
            SELECT feature_name, COUNT(DISTINCT artist_id) AS adopters
            FROM ARPU_INTELLIGENCE_DEMO.RAW.FEATURE_ADOPTION
            GROUP BY feature_name
        )
        SELECT 
            fl.feature_name,
            fl.lift_pct AS revenue_lift_pct,
            COALESCE(ad.adopters, 0) AS current_adopters,
            ROUND(COALESCE(ad.adopters, 0) / 5000.0 * 100, 1) AS adoption_rate_pct
        FROM feature_lift fl
        LEFT JOIN adoption ad ON ad.feature_name = fl.feature_name
        ORDER BY fl.lift_pct DESC
    """).to_pandas()
    
    col_f1, col_f2 = st.columns(2)
    with col_f1:
        st.subheader("Revenue Lift by Feature")
        st.bar_chart(feature_impact, x="FEATURE_NAME", y="REVENUE_LIFT_PCT")
    with col_f2:
        st.subheader("Current Adoption Rate")
        st.bar_chart(feature_impact, x="FEATURE_NAME", y="ADOPTION_RATE_PCT")
    
    st.subheader("Opportunity Gap")
    st.dataframe(feature_impact, use_container_width=True)
    
    # Revenue opportunity calculator
    st.subheader("Revenue Impact Calculator")
    selected_feature = st.selectbox("If all Free-tier artists adopted:", feature_impact['FEATURE_NAME'].tolist())
    lift = feature_impact[feature_impact['FEATURE_NAME'] == selected_feature]['REVENUE_LIFT_PCT'].iloc[0]
    free_avg = kpi_data['AVG_ARPU'][0]
    free_count = 4000
    potential = free_count * free_avg * (lift / 100)
    st.metric("Estimated Monthly Revenue Uplift", f"${potential:,.0f}")

# --- Tab 4: AI Recommendations ---
with tab4:
    st.subheader("AI-Generated Recommendations")
    st.caption("Powered by Cortex AI — synthesized from ML model outputs")
    
    recs = session.sql("""
        SELECT recommendation_text, priority, category, generated_at
        FROM ARPU_INTELLIGENCE_DEMO.ML.RECOMMENDATIONS
        WHERE scope = 'portfolio'
        ORDER BY priority
    """).to_pandas()
    
    for _, row in recs.iterrows():
        badge_color = {"Retention": "🔴", "Feature Adoption": "🟡", "Revenue Growth": "🟢"}.get(row['CATEGORY'], "⚪")
        st.markdown(f"---")
        st.markdown(f"**{badge_color} Priority {row['PRIORITY']} — {row['CATEGORY']}**")
        st.markdown(row['RECOMMENDATION_TEXT'])
    
    if st.button("🔄 Refresh Recommendations"):
        st.info("In production, this triggers a Snowflake Task running AI_COMPLETE against latest ML outputs.")

# --- Tab 5: Forecasts ---
with tab5:
    st.subheader("ARPU Forecast (Next 3 Months)")
    st.caption("Powered by Snowflake ML FORECAST — 50 sample artists")
    
    forecast_data = session.sql("""
        SELECT artist_id, forecast_month, forecast_arpu, lower_bound, upper_bound
        FROM ARPU_INTELLIGENCE_DEMO.ML.FORECAST_RESULTS
        ORDER BY artist_id, forecast_month
    """).to_pandas()
    
    selected_artist = st.selectbox("Select Artist:", forecast_data['ARTIST_ID'].unique()[:20])
    artist_forecast = forecast_data[forecast_data['ARTIST_ID'] == selected_artist]
    
    # Get historical data for this artist
    historical = session.sql(f"""
        SELECT period_month AS forecast_month, arpu_usd AS forecast_arpu, NULL AS lower_bound, NULL AS upper_bound
        FROM ARPU_INTELLIGENCE_DEMO.ANALYTICS.ARTIST_ARPU_TIMESERIES
        WHERE artist_id = '{selected_artist}'
        ORDER BY period_month
    """).to_pandas()
    
    import pandas as pd
    combined = pd.concat([
        historical.rename(columns={"FORECAST_ARPU": "Historical"})[["FORECAST_MONTH", "Historical"]],
        artist_forecast.rename(columns={"FORECAST_ARPU": "Forecast"})[["FORECAST_MONTH", "Forecast"]]
    ])
    chart_data = combined.groupby("FORECAST_MONTH").first().reset_index()
    chart_data = chart_data.set_index("FORECAST_MONTH")
    st.line_chart(chart_data)
    
    st.subheader("Anomaly Detection Results")
    anomalies = session.sql("""
        SELECT artist_id, period_month, actual_arpu, expected_arpu, is_anomaly, anomaly_percentile
        FROM ARPU_INTELLIGENCE_DEMO.ML.ANOMALY_RESULTS
        ORDER BY anomaly_distance DESC
    """).to_pandas()
    st.dataframe(anomalies, use_container_width=True)

# --- Tab 6: Ask Your Data (Cortex Analyst) ---
with tab6:
    st.subheader("Ask Your Data")
    st.caption("Query the ARPU dataset in natural language — powered by Cortex Analyst")
    
    question = st.text_input("Ask a question about artist performance:", 
                             placeholder="e.g., Which genres have the lowest feature adoption?")
    
    if question:
        # Generate SQL using AI_COMPLETE as a lightweight Analyst proxy
        response = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b',
                'You are a SQL expert for a music distribution platform. Given these tables:
                - ARPU_INTELLIGENCE_DEMO.RAW.ARTISTS (artist_id, artist_name, genre, tier, join_date, country, monthly_listeners, catalog_size)
                - ARPU_INTELLIGENCE_DEMO.RAW.TRANSACTIONS (transaction_id, artist_id, period_month, platform, stream_count, royalty_usd, distribution_fee_usd, net_payout_usd)
                - ARPU_INTELLIGENCE_DEMO.RAW.FEATURE_ADOPTION (artist_id, feature_name, first_used_date, sessions_last_30d, is_active_user)
                - ARPU_INTELLIGENCE_DEMO.ML.PREDICTIONS (artist_id, churn_score, churn_risk_label, arpu_forecast_next_90d, top_recommended_feature, forecast_lift_pct)
                
                Write ONLY a single Snowflake SQL query to answer: {question}
                Return ONLY the SQL, no explanation.') AS sql_query
        """).to_pandas()
        
        generated_sql = response['SQL_QUERY'][0].strip().strip('`').replace('```sql', '').replace('```', '').strip()
        # Remove leading "sql" word that the LLM sometimes prepends
        if generated_sql.lower().startswith('sql'):
            generated_sql = generated_sql[3:].strip()
        # Remove trailing semicolons
        generated_sql = generated_sql.rstrip(';').strip()
        st.code(generated_sql, language="sql")
        
        try:
            result = session.sql(generated_sql).to_pandas()
            st.dataframe(result, use_container_width=True)
        except Exception as e:
            st.error(f"Query error: {e}")
