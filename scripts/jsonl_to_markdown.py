#!/usr/bin/env python3
"""Render a Claude Code session log (.jsonl) into a readable Markdown transcript.

Usage:
    jsonl_to_markdown.py <input.jsonl> <output.md> [title]

Best-effort and defensive: unparseable lines are skipped rather than aborting,
so a partial render is always better than none. The canonical record remains the
.jsonl file committed alongside this transcript; this file is for humans reading
the repository.
"""

import json
import sys

TOOL_RESULT_LIMIT = 800  # characters of tool output to keep, per block


def text_blocks(content):
    """Yield ('kind', rendered_string) for each block of a message content."""
    if isinstance(content, str):
        if content.strip():
            yield ("text", content)
        return
    if not isinstance(content, list):
        return
    for b in content:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t == "text":
            txt = b.get("text", "")
            if txt.strip():
                yield ("text", txt)
        elif t == "thinking":
            # Keep the record honest that reasoning happened, without the bulk.
            yield ("thinking", "_(thinking)_")
        elif t == "tool_use":
            name = b.get("name", "tool")
            inp = b.get("input", {})
            desc = ""
            if isinstance(inp, dict):
                for key in ("description", "command", "file_path", "prompt", "query"):
                    if key in inp and isinstance(inp[key], str):
                        desc = inp[key].splitlines()[0][:200]
                        break
            yield ("tool_use", f"🔧 **{name}**" + (f" — {desc}" if desc else ""))
        elif t == "tool_result":
            content_out = b.get("content", "")
            if isinstance(content_out, list):
                parts = []
                for c in content_out:
                    if isinstance(c, dict) and c.get("type") == "text":
                        parts.append(c.get("text", ""))
                content_out = "\n".join(parts)
            content_out = str(content_out)
            clipped = content_out[:TOOL_RESULT_LIMIT]
            if len(content_out) > TOOL_RESULT_LIMIT:
                clipped += f"\n… [+{len(content_out) - TOOL_RESULT_LIMIT} chars]"
            yield ("tool_result", clipped)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    infile, outfile = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else "Conversation history"

    try:
        raw = open(infile, encoding="utf-8").read().splitlines()
    except OSError as e:
        print(f"cannot read {infile}: {e}", file=sys.stderr)
        return 1

    out = [f"# Conversation history: {title}", ""]
    n_entries = 0

    for line in raw:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg = obj.get("message")
        if not isinstance(msg, dict):
            continue
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue

        rendered = list(text_blocks(msg.get("content")))
        if not rendered:
            continue

        heading = "## 👤 User" if role == "user" else "## 🤖 Assistant"
        out.append(heading)
        out.append("")
        for kind, body in rendered:
            if kind == "text":
                out.append(body)
                out.append("")
            elif kind == "thinking":
                out.append(body)
                out.append("")
            elif kind == "tool_use":
                out.append(body)
                out.append("")
            elif kind == "tool_result":
                out.append("<details><summary>tool result</summary>")
                out.append("")
                out.append("```")
                out.append(body)
                out.append("```")
                out.append("")
                out.append("</details>")
                out.append("")
        n_entries += 1

    out.insert(1, f"\n_{n_entries} messages rendered from `{infile.split('/')[-1]}`._\n")

    try:
        open(outfile, "w", encoding="utf-8").write("\n".join(out) + "\n")
    except OSError as e:
        print(f"cannot write {outfile}: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
