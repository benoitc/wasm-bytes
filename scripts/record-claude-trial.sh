#!/bin/sh
# Records one model trial through the Claude Code CLI, headless.
#
#   scripts/record-claude-trial.sh write  LABEL MODEL
#   scripts/record-claude-trial.sh digits LABEL MODEL
#   scripts/record-claude-trial.sh revise LABEL MODEL write/BASE-LABEL
#
# PROMPT=guided sends the guided prompt of a write or digits task.
#
# Writes trials/TASK/LABEL/ with the exact prompt sent (prompt.txt), the
# reply as the CLI returned it (reply.txt), the model and token counts the
# CLI reported (response.json), and fixture.config labelled with the verdict
# the runner gave. The session has no tools, no MCP servers and no settings,
# runs in an empty temporary directory, and has its system prompt replaced.
# Claude Code still adds some context of its own; the interface entry says so.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TASK=$1 LABEL=$2 MODEL=$3 BASE=${4:-}
DIR="$ROOT/trials/$TASK/$LABEL"
SYSTEM="You are a helpful assistant."

if [ -e "$DIR" ]; then echo "$DIR exists" >&2; exit 2; fi
mkdir -p "$DIR"
case $TASK in
    write|digits)
        case ${PROMPT:-baseline} in
            baseline) "$ROOT/bin/wasm-bytes" prompt "$TASK" > "$DIR/prompt.txt" ;;
            guided) "$ROOT/bin/wasm-bytes" prompt "$TASK" --guided > "$DIR/prompt.txt" ;;
            *) echo "PROMPT is baseline or guided" >&2; exit 2 ;;
        esac ;;
    revise)
        [ -n "$BASE" ] || { echo "revise needs a base, such as write/LABEL" >&2; exit 2; }
        "$ROOT/bin/wasm-bytes" prompt revise --base "$ROOT/trials/$BASE/reply.txt" > "$DIR/prompt.txt" ;;
    *) echo "task is write, digits or revise" >&2; exit 2 ;;
esac

EMPTY=$(mktemp -d)
VERSION=$(claude --version | awk '{print $1}')
(cd "$EMPTY" && claude -p --model "$MODEL" --tools "" --strict-mcp-config \
     --setting-sources "" --no-session-persistence --system-prompt "$SYSTEM" \
     --output-format json < "$DIR/prompt.txt") > "$EMPTY/out.json"

# The reply is the `result' field, written as it is. response.json keeps the
# model the API reported and the token counts, and leaves out the session's
# local paths and account details.
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
    halt().' -extra "$EMPTY/out.json" "$DIR" > "$EMPTY/model"
rm -f "$EMPTY/out.json"

# The hash of the module the reply decodes to, as shasum writes it, so any
# engine or platform can be checked against the exact bytes.
if "$ROOT/bin/wasm-bytes" trace "$DIR" --wasm "$EMPTY/module.wasm" >/dev/null 2>&1; then
    (cd "$EMPTY" && shasum -a 256 module.wasm) > "$DIR/module.sha256"
fi

if [ "$TASK" != revise ]; then
    OUT=$("$ROOT/bin/wasm-bytes" check "$TASK" "$DIR/reply.txt" || true)
else
    OUT=$("$ROOT/bin/wasm-bytes" check revise "$DIR/reply.txt" --base "$ROOT/trials/$BASE/reply.txt" || true)
fi
VERDICT=$(printf '%s\n' "$OUT" | awk '$1 == "verdict" {print $2}' | tail -1)

{
    echo "{source, model_trial}."
    echo "{model, \"$(cat "$EMPTY/model")\"}."
    echo "{interface, \"Claude Code $VERSION headless (claude -p --model $MODEL), built-in tools and MCP servers off, no settings loaded, system prompt replaced with \\\"$SYSTEM\\\", run from an empty directory; Claude Code still adds context of its own (environment and account details). Default sampling, one sample.\"}."
    echo "{recorded_on, \"$(date +%F)\"}."
    echo "{expect, $VERDICT}.          % the verdict the runner gave when this was recorded"
    if [ "$TASK" = revise ]; then echo "{base, \"$BASE\"}."; fi
    if [ "${PROMPT:-baseline}" = guided ]; then echo "{prompt_variant, guided}."; fi
} > "$DIR/fixture.config"
rm -rf "$EMPTY"

printf '%s\n' "$OUT"
