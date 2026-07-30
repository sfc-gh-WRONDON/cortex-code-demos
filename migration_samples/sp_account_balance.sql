/* ============================================================
   SQL Server Stored Procedure: sp_AccountBalanceSummary
   Database: CardWorks_Reporting
   Purpose: Calculate daily account balance snapshots with
            30/60/90 day aging and delinquency flags.
   Scheduled: Daily at 6AM EST via SQL Agent Job
   Last Modified: 2021-03-22 by R. Singh
   ============================================================ */

CREATE PROCEDURE [dbo].[sp_AccountBalanceSummary]
    @ReportDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @ReportDate IS NULL
        SET @ReportDate = CAST(GETDATE() AS DATE);

    -- Step 1: Get current account balances with aging
    SELECT
        a.ACCT_NUM,
        a.CUST_ID,
        a.CU_ID,
        a.CU_NAME,
        a.CARD_NTWK,
        a.CRED_LMT,
        a.CURR_BAL,
        a.AVAIL_CRED,
        a.DAYS_PAST_DUE,
        a.MIN_PMT_AMT,
        a.PMT_DUE_DT,
        CASE
            WHEN a.DAYS_PAST_DUE = 0 THEN 'Current'
            WHEN a.DAYS_PAST_DUE BETWEEN 1 AND 30 THEN '1-30 Days'
            WHEN a.DAYS_PAST_DUE BETWEEN 31 AND 60 THEN '31-60 Days'
            WHEN a.DAYS_PAST_DUE BETWEEN 61 AND 90 THEN '61-90 Days'
            ELSE '90+ Days'
        END AS aging_bucket,
        CAST(a.CURR_BAL AS FLOAT) / NULLIF(CAST(a.CRED_LMT AS FLOAT), 0) AS utilization_ratio,
        CASE
            WHEN a.DAYS_PAST_DUE > 90 THEN 1
            ELSE 0
        END AS is_delinquent,
        @ReportDate AS snapshot_date
    INTO #AccountSnapshot
    FROM dbo.ACCOUNT_MASTER a WITH (NOLOCK)
    WHERE a.ACCT_STAT_CD = 'A';

    -- Step 2: Get payment history for last 6 months
    SELECT
        t.ACCT_NUM,
        COUNT(*) AS payment_count_6m,
        SUM(t.TXN_AMT) AS total_payments_6m,
        MAX(t.TXN_DT) AS last_payment_date,
        DATEDIFF(DAY, MAX(t.TXN_DT), @ReportDate) AS days_since_last_payment
    INTO #PaymentHistory
    FROM dbo.TRAN_HISTORY t WITH (NOLOCK)
    WHERE t.TXN_TYP_CD = 'PMT'
      AND t.TXN_DT >= DATEADD(MONTH, -6, @ReportDate)
    GROUP BY t.ACCT_NUM;

    -- Step 3: Get spending totals for last 30 days
    SELECT
        t.ACCT_NUM,
        COUNT(*) AS txn_count_30d,
        SUM(t.TXN_AMT) AS total_spend_30d,
        AVG(t.TXN_AMT) AS avg_txn_amount_30d,
        SUM(CASE WHEN t.TXN_AMT > 1000 THEN 1 ELSE 0 END) AS large_txn_count_30d
    INTO #SpendingMetrics
    FROM dbo.TRAN_HISTORY t WITH (NOLOCK)
    WHERE t.TXN_TYP_CD = 'PUR'
      AND t.TXN_DT >= DATEADD(DAY, -30, @ReportDate)
    GROUP BY t.ACCT_NUM;

    -- Step 4: Final output - combine all metrics
    SELECT
        snap.ACCT_NUM AS account_id,
        snap.CUST_ID AS customer_id,
        snap.CU_ID AS credit_union_id,
        snap.CU_NAME AS credit_union_name,
        snap.CARD_NTWK AS card_network,
        snap.CRED_LMT AS credit_limit,
        snap.CURR_BAL AS current_balance,
        snap.AVAIL_CRED AS available_credit,
        snap.utilization_ratio,
        snap.DAYS_PAST_DUE AS days_past_due,
        snap.aging_bucket,
        snap.is_delinquent,
        snap.MIN_PMT_AMT AS minimum_payment,
        snap.PMT_DUE_DT AS payment_due_date,
        ISNULL(ph.payment_count_6m, 0) AS payment_count_6m,
        ISNULL(ph.total_payments_6m, 0) AS total_payments_6m,
        ph.last_payment_date,
        ISNULL(ph.days_since_last_payment, 999) AS days_since_last_payment,
        ISNULL(sm.txn_count_30d, 0) AS transaction_count_30d,
        ISNULL(sm.total_spend_30d, 0) AS total_spend_30d,
        ISNULL(sm.avg_txn_amount_30d, 0) AS avg_transaction_amount_30d,
        ISNULL(sm.large_txn_count_30d, 0) AS large_transaction_count_30d,
        snap.snapshot_date
    FROM #AccountSnapshot snap
    LEFT JOIN #PaymentHistory ph ON snap.ACCT_NUM = ph.ACCT_NUM
    LEFT JOIN #SpendingMetrics sm ON snap.ACCT_NUM = sm.ACCT_NUM
    ORDER BY snap.CURR_BAL DESC;

    -- Cleanup
    DROP TABLE #AccountSnapshot;
    DROP TABLE #PaymentHistory;
    DROP TABLE #SpendingMetrics;
END;
GO
