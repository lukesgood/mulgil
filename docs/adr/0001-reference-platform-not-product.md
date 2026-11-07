# ADR 0001 — Mulgil is a reference platform, not a product

Status: accepted · Date: 2026-11-08

## Context
DataPond 1.x grew to eighteen components because platform features kept
being added to a governance product. Mulgil is created to hold the platform
side so Sumun can stay narrow.

## Decision
Mulgil is glue, sample models and deployment profiles over upstream
open-source components. It has no API, UI or scheduler of its own. Revenue
comes from build engagements, not from Mulgil itself.

## Consequences
- A feature request that needs Mulgil code of its own goes upstream or to Sumun.
- Mulgil is public from day one; nothing in it is proprietary.
