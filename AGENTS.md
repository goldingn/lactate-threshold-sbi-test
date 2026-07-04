# Repository guide for AI agents

## What this repository is

A test case for amortised, simulation-based Bayesian inference (SBI) of a
lactate-threshold model.

- **Phase 1 (this `main` branch):** a mechanistic two-compartment lactate model,
  a forward simulator (`R/simulate.R`), and code to download and format the
  Bernard et al. (2024) exercise-test dataset (`R/download_data.R`). The model
  and data are defined in [`README.md`](README.md). This is the baseline that
  exists *before* any SBI work.
- **Phase 2 (other branches):** individual agentic Bayesian SBI experiments,
  each built on top of phase 1 in its own branch.

## If you are running a phase-2 SBI experiment — READ THIS

You are (most likely) working on a phase-2 experiment branch. When the Bayesian
SBI workflow for this experiment is **finalised**, you must preserve the
conversation that produced it:

1. **Prompt the user.** Once the workflow is complete and working, ask them,
   e.g.:
   > "The SBI workflow looks finalised. Shall I save this conversation to the
   > repo with `scripts/save-conversation.sh` so there's a durable record of
   > this experiment?"
2. **On confirmation, run the save script** from the repository root:
   ```sh
   scripts/save-conversation.sh
   ```
   This copies the current Claude Code session log into
   `conversations/phase2/<branch>.{jsonl,md}` and commits it. (On `main` it goes
   to `conversations/phase1/` instead.)
3. Do **not** `git push` unless the user asks.

Do this **once, at the very end** of the experiment, after the workflow is
finalised — not partway through. If you are unsure whether the workflow is
final, ask before saving.

See [`conversations/README.md`](conversations/README.md) for the record layout
and [`scripts/save-conversation.sh`](scripts/save-conversation.sh) for options
(`--dry-run`, explicit name, pinning a session id).

## Ground rules

- Keep `main` as the pre-SBI simulation baseline. SBI-specific scaffolding
  belongs on phase-2 branches, not on `main`.
- The dataset is large; `R/download_data.R` fetches it into `data-raw/` on
  demand. Do not commit the downloaded data.
