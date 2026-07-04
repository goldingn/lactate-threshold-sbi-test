# Conversation history

Durable records of the Claude Code conversations that produced this repository,
so each experiment can be traced back to the dialogue that created it.

## Layout

- `phase1/` — the setup conversation(s) that built the simulation repo (the
  model, simulator, and data-loading code) on `main`.
- `phase2/` — one record per phase-2 agentic Bayesian SBI experiment. Each
  experiment runs on its own branch, and its conversation is saved here named
  after that branch.

Each saved conversation is stored as two files:

- `<name>.jsonl` — the raw Claude Code session log. This is the canonical,
  complete record.
- `<name>.md` — a human-readable transcript rendered from the log (best effort;
  produced when `python3` is available).

## How records are created

Run, from the repository root, within the Claude Code session you want to save:

```sh
scripts/save-conversation.sh          # names the record after the current branch
scripts/save-conversation.sh my-name  # or give it an explicit name
scripts/save-conversation.sh --dry-run # show what would be saved, change nothing
```

The script picks `phase1/` on `main`/`master` and `phase2/` on any other branch,
copies the current session log in, renders the transcript, and commits both
files. See [`../AGENTS.md`](../AGENTS.md) for when an agent should do this, and
the header of [`../scripts/save-conversation.sh`](../scripts/save-conversation.sh)
for details.
