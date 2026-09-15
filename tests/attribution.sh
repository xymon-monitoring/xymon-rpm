#!/bin/sh
# Fails when a text credits an AI tool.
#
# AGENTS.md forbids that credit in commit messages, pull request titles and
# bodies, issue text, review comments, and files added to the tree. This
# covers the two surfaces CI can see.
#
# It exists because the rule was broken once before it did. A commit message
# carrying a Co-Authored-By trailer was cleaned by a local git hook, silently,
# so nothing said the rule had been broken -- and the same credit then went
# into the pull request body, where no hook looks. A hook covers one machine
# and one surface; this covers every contributor and two.
#
#   usage: tests/attribution.sh LABEL FILE
#
# Quoted text is not a credit, so both ways of quoting are blanked before
# matching -- fenced code blocks, and inline code spans -- and a change that
# documents the rule can therefore quote the lines it forbids. Spans matter as
# much as fences: a table cannot hold a fenced block, and a table of forbidden
# forms is exactly how this rule gets written down. Blanked rather than
# removed, so a reported line number is the one in FILE.
#
# It costs nothing real. The credit this exists to catch is appended to a
# message or a body by a tool, never wrapped in backticks by it.

set -eu

label=${1:?usage: tests/attribution.sh LABEL FILE}
file=${2:?usage: tests/attribution.sh LABEL FILE}

[ -r "$file" ] || { echo "attribution: cannot read $file" >&2; exit 2; }

# A credit is a credit because it names a tool. Matched case-insensitively,
# so this list is lower case.
tools='anthropic|claude|openai|chatgpt|gpt-[0-9]|copilot|gemini|codex|cursor|devin|aider|windsurf|cody|bard'

hits=$(
	awk '/^[[:space:]]*```/ { f = !f; print ""; next }
	     f                        { print ""; next }
	                              { gsub(/`[^`]*`/, ""); print }' "$file" |
	grep -n -i -E \
		-e "^[[:space:]]*(co-authored-by|co-authored-with|assisted-by|ai-assisted-by|generated-by|written-by|suggested-by|reviewed-by)[[:space:]]*:.*($tools)" \
		-e "(generated|written|created|authored)[[:space:]]+(with|by)[[:space:]]+\[?($tools)" \
		-e "(claude\.com/claude-code|anthropic\.com/claude)" \
	|| true
)

if [ -n "$hits" ]; then
	echo "FAIL: $label credits an AI tool:" >&2
	echo >&2
	printf '%s\n' "$hits" | sed 's/^/    /' >&2
	echo >&2
	echo "AGENTS.md: do not credit an AI tool in anything that lands here -- no" >&2
	echo "Co-Authored-By naming a model or an assistant, no \"Generated with ...\"" >&2
	echo "line, no \"reviewed by\" or \"suggested by\" credit. End the text with its" >&2
	echo "own content and stop there. Use whatever tools you like; if one of them" >&2
	echo "found a real problem, report the problem in your own words." >&2
	exit 1
fi

echo "ok: $label"
