#!/bin/sh
# Records one model trial through a local Ollama server. No account or API
# key is involved.
#
#   scripts/record-ollama-trial.sh write  LABEL MODEL
#   scripts/record-ollama-trial.sh digits LABEL MODEL
#   scripts/record-ollama-trial.sh revise LABEL MODEL write/BASE-LABEL
#
# Writes trials/TASK/LABEL/ with the exact prompt sent (prompt.txt), the
# model's answer as Ollama returned it (reply.txt), its separate thinking
# trace when it has one (thinking.txt), the model digest and token counts
# (response.json), module.sha256, and fixture.config labelled with the
# verdict the runner gave.
#
# PROMPT=guided sends the guided prompt of a write or digits task.
# OLLAMA_HOST picks the server (http://127.0.0.1:11434 by default). THINK
# sets the thinking level (true, false, low, high...); unset, the model uses
# its own default. Sampling is Ollama's default for the model.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TASK=$1 LABEL=$2 MODEL=$3 BASE=${4:-}
DIR="$ROOT/trials/$TASK/$LABEL"
SYSTEM="You are a helpful assistant."
HOST=${OLLAMA_HOST:-http://127.0.0.1:11434}
case "$HOST" in http://*|https://*) ;; *) HOST="http://$HOST" ;; esac
THINK=${THINK:-default}

if [ -e "$DIR" ]; then echo "$DIR exists" >&2; exit 2; fi
mkdir -p "$DIR"
case $TASK in
    write|digits|pan|ui)
        case ${PROMPT:-baseline} in
            baseline) "$ROOT/bin/wasm-bytes" prompt "$TASK" > "$DIR/prompt.txt" ;;
            guided) "$ROOT/bin/wasm-bytes" prompt "$TASK" --guided > "$DIR/prompt.txt" ;;
            *) echo "PROMPT is baseline or guided" >&2; exit 2 ;;
        esac ;;
    revise|reverse)
        [ -n "$BASE" ] || { echo "$TASK needs a base, such as write/LABEL or pan/LABEL" >&2; exit 2; }
        "$ROOT/bin/wasm-bytes" prompt "$TASK" --base "$ROOT/trials/$BASE/reply.txt" > "$DIR/prompt.txt" ;;
    *) echo "task is write, digits, pan, ui, revise or reverse" >&2; exit 2 ;;
esac

WORK=$(mktemp -d)
curl -sS --fail "$HOST/api/version" > "$WORK/version.json"
curl -sS --fail "$HOST/api/tags" > "$WORK/tags.json"

# The request, encoded by Erlang's json module so the prompt goes as it is.
erl -noshell -eval '
    [PromptFile, Model, System, Think, Out] = init:get_plain_arguments(),
    {ok, Prompt} = file:read_file(PromptFile),
    Req0 = #{model => list_to_binary(Model), stream => false,
             messages => [#{role => ~"system", content => list_to_binary(System)},
                          #{role => ~"user", content => Prompt}]},
    Req = case Think of
              "default" -> Req0;
              "true" -> Req0#{think => true};
              "false" -> Req0#{think => false};
              Level -> Req0#{think => list_to_binary(Level)}
          end,
    ok = file:write_file(Out, json:encode(Req)),
    halt().' -extra "$DIR/prompt.txt" "$MODEL" "$SYSTEM" "$THINK" "$WORK/request.json"

curl -sS --fail --max-time 3600 "$HOST/api/chat" -H 'Content-Type: application/json' \
    --data-binary @"$WORK/request.json" > "$WORK/out.json"

# The reply is the answer field, written as it is; the thinking trace, which
# Ollama returns apart from the answer, is kept beside it.
erl -noshell -eval '
    [Out, Tags, Version, Dir, Think] = init:get_plain_arguments(),
    Read = fun(P) -> {ok, B} = file:read_file(P), json:decode(B) end,
    R = Read(Out),
    #{<<"message">> := Msg, <<"model">> := Model} = R,
    [Digest] = [D || #{<<"name">> := N, <<"digest">> := D} <- maps:get(<<"models">>, Read(Tags)),
                     N =:= Model],
    ok = file:write_file(filename:join(Dir, "reply.txt"), maps:get(<<"content">>, Msg)),
    case maps:get(<<"thinking">>, Msg, <<>>) of
        <<>> -> ok;
        T -> ok = file:write_file(filename:join(Dir, "thinking.txt"), T)
    end,
    Keep = #{model => Model, digest => Digest,
             ollama_version => maps:get(<<"version">>, Read(Version)),
             think => list_to_binary(Think),
             created_at => maps:get(<<"created_at">>, R),
             done_reason => maps:get(<<"done_reason">>, R, null),
             prompt_eval_count => maps:get(<<"prompt_eval_count">>, R, null),
             eval_count => maps:get(<<"eval_count">>, R, null),
             total_duration_ns => maps:get(<<"total_duration">>, R, null),
             result => maps:get(<<"content">>, Msg)},
    ok = file:write_file(filename:join(Dir, "response.json"), [json:format(Keep, #{indent => 2}), $\n]),
    io:format("~s~n~s~n~s", [Model, Digest, maps:get(<<"version">>, Read(Version))]),
    halt().' -extra "$WORK/out.json" "$WORK/tags.json" "$WORK/version.json" "$DIR" "$THINK" > "$WORK/identity"

MODEL_NAME=$(sed -n 1p "$WORK/identity")
DIGEST=$(sed -n 2p "$WORK/identity")
OLLAMA_VERSION=$(sed -n 3p "$WORK/identity")

if "$ROOT/bin/wasm-bytes" trace "$DIR" --wasm "$WORK/module.wasm" >/dev/null 2>&1; then
    (cd "$WORK" && shasum -a 256 module.wasm) > "$DIR/module.sha256"
fi

case $TASK in
    revise|reverse)
        OUT=$("$ROOT/bin/wasm-bytes" check "$TASK" "$DIR/reply.txt" --base "$ROOT/trials/$BASE/reply.txt" || true) ;;
    *)
        OUT=$("$ROOT/bin/wasm-bytes" check "$TASK" "$DIR/reply.txt" || true) ;;
esac
VERDICT=$(printf '%s\n' "$OUT" | awk '$1 == "verdict" {print $2}' | tail -1)

case $THINK in
    default) THINKING="the model's default thinking level" ;;
    *) THINKING="thinking set to $THINK" ;;
esac
{
    echo "{source, model_trial}."
    echo "{model, \"$MODEL_NAME, digest sha256:$DIGEST\"}."
    echo "{interface, \"Ollama $OLLAMA_VERSION on this machine, /api/chat with stream false, system prompt \\\"$SYSTEM\\\", $THINKING, default sampling; the answer field is reply.txt and the separate thinking trace is thinking.txt. One sample.\"}."
    echo "{recorded_on, \"$(date +%F)\"}."
    echo "{expect, $VERDICT}.          % the verdict the runner gave when this was recorded"
    case $TASK in revise|reverse) echo "{base, \"$BASE\"}." ;; esac
    if [ "${PROMPT:-baseline}" = guided ]; then echo "{prompt_variant, guided}."; fi
} > "$DIR/fixture.config"
rm -rf "$WORK"

printf '%s\n' "$OUT"
