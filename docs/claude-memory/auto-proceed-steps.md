---
name: auto-proceed-steps
description: "User allows moving to next plan step without waiting for \"go\"; still show checklist after each step"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 3199b2c4-d499-48e4-a95c-a6700b18e716
  modified: 2026-10-31T21:15:30.255Z
---

During a multi-step build plan, proceed from one step to the next without asking "say go". (User, 2026-11-01, fix build plan.)

**Why:** user tired of typing "go" between every step.
**How to apply:** after finishing a step, post the checklist ([[checklists-in-chat]]) and continue straight into the next step. Still stop for: edge function deploys (confirm), things needing user input (Maps key, dashboard settings), destructive git ops. See [[fix-build-plan]].
