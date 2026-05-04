# Cost Model

## Dev Cost Assumptions

This project is modeled as a low-volume development environment, not a production workload.

Assumptions:
- Databricks pipelines run on demand, not continuously
- Workflow orchestration is triggered manually or once daily
- Event volume is small (a few thousand events, not millions)
- Event Hubs runs at minimal throughput for development
- Key Vault usage is low and limited to secret reads/writes during setup and rotation
- Storage footprint is small because the dataset is tiny
- Terraform is used as a plan-only artifact and does not create persistent duplicated infrastructure

The goal of the dev cost model is not billing precision.
The goal is to identify the dominant cost drivers and show how cost would scale in production.

## Main Cost Drivers

The main cost drivers in this project are:

1. **Databricks compute**
   - DLT pipeline runs
   - workflow-triggered refreshes
   - SQL warehouse usage during validation and analysis

2. **Event Hubs**
   - throughput capacity
   - retention window
   - message volume over time

3. **Key Vault**
   - secret operations such as reads, writes, and rotations
   - typically low cost in dev compared to compute

4. **Storage**
   - Delta tables across Bronze, Silver, and Gold
   - log/history growth over time
   - small in dev, potentially meaningful in prod

For this project, Databricks compute is the dominant cost driver by far.
Event Hubs is secondary.
Storage and Key Vault are minor in the current development setup.

## Estimated Monthly Dev Cost

This project is intentionally kept in a low-cost development mode.

A realistic development estimate is:

- **Databricks:** low to moderate cost, depending on how often pipelines and SQL warehouses are run
- **Event Hubs:** low cost at dev-scale message volume
- **Key Vault:** negligible cost in this setup
- **Storage:** negligible to low cost because the dataset is small

A reasonable summary for this project is:

> The monthly dev cost is dominated by Databricks compute, while Event Hubs, Key Vault, and storage remain minor contributors.

This is a directional cost model, not a billing forecast.
Its purpose is to show cost awareness, identify the dominant driver, and explain how the design would scale under higher throughput or more frequent refreshes.

## What Changes in Prod

Production changes the cost model in both scale and design discipline.

Compared with dev, production would likely include:
- more frequent or continuous pipeline runs
- higher event volume and longer retention requirements
- more monitoring, alerting, and workflow runs
- more storage growth across Bronze, Silver, Gold, and logs
- stronger networking and security controls that can add operational cost

The most important shift is that compute efficiency matters much more in prod.
At higher scale, small inefficiencies in transformation logic, refresh frequency, table layout, or warehouse usage become recurring cost problems.

That means production cost control depends on:
- choosing the right refresh cadence
- optimizing table layout and query patterns
- avoiding unnecessary full rebuilds
- reducing waste in compute usage