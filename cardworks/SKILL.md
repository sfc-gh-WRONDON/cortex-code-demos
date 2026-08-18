# SKILL.md — cardworks_dbt_model_builder

## Purpose
Build new dbt models for the CardWorks data engineering project following team standards.

## When to Use
When a user asks to create a new dbt model, staging model, mart, or transformation.

## Standards to Follow

### Naming
- Staging models: stg_[source_entity].sql
- Mart models: fct_[entity].sql for facts, dim_[entity].sql for dimensions
- All column names in snake_case
- Boolean columns prefixed with is_ or has_

### Structure
- Every model starts with CTEs referencing staging models via ref() macro
- Source models use the source() macro with _fivetran_deleted or is_active filter
- Business logic in a final SELECT, not buried in CTEs
- Always include date_trunc columns for month and quarter when a date field is present
- Window functions for running totals and prior period comparisons

### Required Tests
- not_null on all primary key columns and foreign key columns
- unique on the grain of fact tables
- accepted_values on transaction_type: Purchase, Refund, Cash Advance, Balance Transfer, Fee, Payment
- accepted_values on account_status: Active, Closed, Suspended, Delinquent
- accepted_values on card_network: Visa, Mastercard, Discover, Amex

### Materialization
- Staging models: view
- Mart models: table
- Incremental models: use merge strategy with unique_key

### CardWorks Business Context
- CardWorks is a financial services company managing credit union card programs
- Key entities: transactions, accounts, cardholders, merchants, statements
- Transaction types: Purchase, Refund, Cash Advance, Balance Transfer, Fee, Payment
- Card networks: Visa, Mastercard, Discover, Amex
- Key metrics: transaction_amount, net_amount, interchange_fee, merchant_discount_rate
- Risk indicators: transactions over $5000, international transactions, card-not-present, velocity (3+ txns in 1 hour)
- Geographic focus: US-based credit unions
- Source systems: Mainframe (via Snowpark), SQL Server (legacy reporting), SAS (being replaced)

### Data Sources
- RAW_MAINFRAME schema: Core transaction and account data landed by Snowpark from mainframe
- RAW_SQLSERVER schema: Legacy reporting tables migrated from SQL Server
- All raw data is append-only with _loaded_at timestamps
