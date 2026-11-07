# ADR 0003 — No Spark in the reference stack

Status: accepted · Date: 2026-11-08

## Decision
Trino (or Athena) handles writes, MERGE, and Iceberg maintenance. Spark is
added only when a workload demonstrates a need: multi-hour shuffles, UDF
logic SQL cannot express, or ML feature pipelines.

## Consequences
One engine for query, transform and maintenance; one access-control model;
no Spark Operator, shuffle storage or executor tuning to run.
