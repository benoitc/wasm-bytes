#!/bin/sh
# Records model replies to a track's cases through the Claude Code CLI,
# headless, one case at a time.
#
#   scripts/record-claude-cases.sh TRACK LABEL MODEL [CASE-ID ...]
#
# Without case ids it records every case of TRACK that `bin/wasm-bytes cases'
# lists. For each case it writes trials/cases/<case id>/LABEL/: the exact
# prompt (prompt.txt), the reply as the CLI returned it (reply.txt), the model
# and token counts the CLI reported (response.json), and fixture.config with
# the verdict `bin/wasm-bytes check case' gave. A case that already has a
# reply is left as it is, so an interrupted run can be started again.
#
# STEP=prompts writes only the prompts, STEP=ask only sends prompts that are
# already written, and STEP=label only checks saved replies; the default does
# all three. `ask' runs nothing from this repository, so the runner can be
# rebuilt while replies arrive. CASES=DIRECTORY reads the cases from a corpus
# run, such as _build/cases, instead of cases/.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TRACK=$1 LABEL=$2 MODEL=$3
shift 3
SYSTEM="You are a helpful assistant."
STEP=${STEP:-all}
CASES_OPT=""
if [ -n "${CASES:-}" ]; then
    CASES_OPT="--cases $CASES"
fi

if [ $# -eq 0 ]; then
    # shellcheck disable=SC2086
    set -- $("$ROOT/bin/wasm-bytes" cases "$TRACK" $CASES_OPT | awk '$1 ~ /\// {print $1}')
fi

for ID in "$@"; do
    DIR="$ROOT/trials/cases/$ID/$LABEL"
    mkdir -p "$DIR"
    case $STEP in all|prompts)
        # shellcheck disable=SC2086
        [ -f "$DIR/prompt.txt" ] || "$ROOT/bin/wasm-bytes" prompt case "$ID" $CASES_OPT > "$DIR/prompt.txt" ;;
    esac
    case $STEP in all|ask)
        if [ ! -f "$DIR/reply.txt" ]; then
            EMPTY=$(mktemp -d)
            VERSION=$(claude --version | awk '{print $1}')
            (cd "$EMPTY" && claude -p --model "$MODEL" --tools "" --strict-mcp-config \
                 --setting-sources "" --no-session-persistence --system-prompt "$SYSTEM" \
                 --output-format json < "$DIR/prompt.txt") > "$EMPTY/out.json"
            # The reply is the `result' field, written as it is.
            erl -noshell -eval '
                [In, Dir] = init:get_plain_arguments(),
                {ok, Bin} = file:read_file(In),
                Events = json:decode(Bin),
                [R] = [E || #{<<"type">> := <<"result">>} = E <- Events],
                [Model] = maps:keys(maps:get(<<"modelUsage">>, R)),
                [Init] = [E || #{<<"type">> := <<"system">>, <<"subtype">> := <<"init">>} = E <- Events],
                Keep = #{model => Model,
                         claude_code_version => maps:get(<<"claude_code_version">>, Init),
                         tools => maps:get(<<"tools">>, Init),
                         mcp_servers => maps:get(<<"mcp_servers">>, Init),
                         num_turns => maps:get(<<"num_turns">>, R),
                         is_error => maps:get(<<"is_error">>, R),
                         usage => maps:with([<<"input_tokens">>, <<"cache_creation_input_tokens">>,
                                             <<"cache_read_input_tokens">>, <<"output_tokens">>,
                                             <<"output_tokens_details">>], maps:get(<<"usage">>, R)),
                         result => maps:get(<<"result">>, R)},
                ok = file:write_file(filename:join(Dir, "reply.txt"), maps:get(<<"result">>, R)),
                ok = file:write_file(filename:join(Dir, "response.json"),
                                     [json:format(Keep, #{indent => 2}), $\n]),
                io:format("~s", [Model]),
                halt().' -extra "$EMPTY/out.json" "$DIR" > "$DIR/.model"
            echo "$VERSION" > "$DIR/.cli-version"
            rm -rf "$EMPTY"
            echo "asked    $ID"
        fi ;;
    esac
    case $STEP in all|label)
        if [ -f "$DIR/reply.txt" ] && [ ! -f "$DIR/fixture.config" ]; then
            # shellcheck disable=SC2086
            OUT=$("$ROOT/bin/wasm-bytes" check case "$ID" "$DIR/reply.txt" $CASES_OPT || true)
            VERDICT=$(printf '%s\n' "$OUT" | awk '$1 == "verdict" {print $2}' | tail -1)
            {
                echo "{source, model_trial}."
                echo "{model, \"$(cat "$DIR/.model")\"}."
                echo "{interface, \"Claude Code $(cat "$DIR/.cli-version") headless (claude -p --model $MODEL), built-in tools and MCP servers off, no settings loaded, system prompt replaced with \\\"$SYSTEM\\\", run from an empty directory; Claude Code still adds context of its own (environment and account details). Default sampling, one sample.\"}."
                echo "{recorded_on, \"$(date -r "$DIR/reply.txt" +%F)\"}."
                echo "{expect, $VERDICT}.          % the verdict the runner gave when this was recorded"
            } > "$DIR/fixture.config"
            rm -f "$DIR/.model" "$DIR/.cli-version"
            echo "labelled $ID: $VERDICT"
        fi ;;
    esac
done
