#!/usr/bin/env bash
#
# Land both stacked PR trains overnight, unattended.
#
# Runs the `merge-the-stacks` workflow through headless Claude Code, over and over,
# until there is nothing left at the front of either stack. Re-running is what makes it
# survive a usage window: every attempt re-reads the front of each stack from GitHub, so
# an attempt that dies costs nothing but the time it had spent.
#
#   ./merge-the-stacks.sh              # land everything
#   DRY=1 ./merge-the-stacks.sh        # rehearse: review, fix, wait for CI, never merge
#   MAX_PRS=2 ./merge-the-stacks.sh    # two PRs per train, to calibrate
#
set -uo pipefail

APP=/Users/joao/Desktop/work/shema/shemaobt/internalization-room
API=/Users/joao/Desktop/work/shema/shemaobt/tripod-backend
LEDGER="$HOME/.claude/merge-the-stacks.log"
RUNLOG="$HOME/.claude/merge-the-stacks.run.log"

# A short session per handful of PRs, not one session for ninety. The workflow's agents
# already start clean for every PR, but the session that drives them does not: over a
# ninety-PR turn it accumulates every result it ever saw and eventually auto-compacts,
# which is exactly where the tail of a long run gets worse than its head. Landing a few
# and exiting keeps every session small, and makes a session that dies cost three PRs
# instead of the night.
MAX_PRS=${MAX_PRS:-6}
MAX_ATTEMPTS=${MAX_ATTEMPTS:-60}
SLEEP_PROGRESS=${SLEEP_PROGRESS:-20}   # it is working — straight into the next session
SLEEP_STALLED=${SLEEP_BETWEEN:-1800}   # nothing moved: probably a usage window, wait it out
DRY=${DRY:-0}

# Keep the machine awake for as long as this runs. Without it the Mac sleeps around 1am
# and both trains stop wherever they stood.
if [[ "${CAFFEINATED:-}" != "1" ]]; then
  export CAFFEINATED=1
  exec caffeinate -ims "$0" "$@"
fi

say() { printf '%s  %s\n' "$(date '+%F %T')" "$*" | tee -a "$RUNLOG"; }
die() { say "STOP: $*"; exit 1; }

preflight() {
  command -v claude   >/dev/null || die "claude não está no PATH"
  command -v gh       >/dev/null || die "gh não está no PATH"
  command -v flutter  >/dev/null || die "flutter não está no PATH"
  gh auth status >/dev/null 2>&1 || die "gh não está autenticado — rode: gh auth login"
  [[ -d "$APP/.git" ]] || die "não encontrei o repo da Sala em $APP"
  [[ -d "$API/.git" ]] || die "não encontrei o backend em $API"
  [[ -f "$API/.venv/bin/activate" ]] || die "o venv do backend não existe em $API/.venv"
  [[ -f "$APP/.claude/workflows/merge-the-stacks.js" ]] || die "workflow não encontrado"
  mkdir -p "$(dirname "$LEDGER")"
  say "preflight ok"
}

# How many PRs are sitting at the front of a stack — base main, still open.
front_of() {
  local repo="$1" author="${2:-}"
  local filter='.[] | select(.baseRefName=="main")'
  [[ -n "$author" ]] && filter=".[] | select(.baseRefName==\"main\" and .author.login==\"$author\")"
  gh pr list -R "$repo" --state open --limit 200 \
     --json number,baseRefName,author --jq "[$filter] | length" 2>/dev/null || echo "?"
}

remaining() {
  local a b
  a=$(front_of shemaobt/shema-api joaocarvoli)
  b=$(front_of shemaobt/internalization-room)
  echo "${a:-?} ${b:-?}"
}

open_each() {
  local a b
  a=$(gh pr list -R shemaobt/shema-api --state open --limit 200 \
        --json number,author --jq '[.[] | select(.author.login=="joaocarvoli")] | length' 2>/dev/null)
  b=$(gh pr list -R shemaobt/internalization-room --state open --limit 200 \
        --json number --jq 'length' 2>/dev/null)
  echo "${a:-0} ${b:-0}"
}

open_total() {
  local a b
  a=$(gh pr list -R shemaobt/shema-api --state open --limit 200 \
        --json number,author --jq '[.[] | select(.author.login=="joaocarvoli")] | length' 2>/dev/null)
  b=$(gh pr list -R shemaobt/internalization-room --state open --limit 200 \
        --json number --jq 'length' 2>/dev/null)
  echo $(( ${a:-0} + ${b:-0} ))
}

build_prompt() {
  local only="$1"
  PROMPT="+3M ultracode: run the saved workflow \`merge-the-stacks\` with args \
{\"land\": $( [[ "$DRY" == "1" ]] && echo false || echo true ), \"maxPrs\": $MAX_PRS, \"only\": $only}.

Launch it and then WAIT for it to finish before you end your turn — block on the task and
report what came back. Do not end the turn while the workflow is still running: this is a
headless session and the process exits with the turn, which would kill it.

Nobody is awake. Do not ask questions, do not ask for confirmation, do not stop to check
anything with me. If a train stops, that is a correct outcome — report where and why."
}

main() {
  preflight
  say "PRs abertos no começo: $(open_total)   |   frente das pilhas: $(remaining)"
  [[ "$DRY" == "1" ]] && say "MODO ENSAIO — nada será mergeado"

  local before after stuck=0
  local api_stuck=0 sala_stuck=0 api_live=1 sala_live=1
  local api_before sala_before api_after sala_after only
  for (( attempt=1; attempt<=MAX_ATTEMPTS; attempt++ )); do
    before=$(open_total)
    read -r api_before sala_before <<< "$(open_each)"
    if [[ "$(remaining)" == "0 0" ]]; then
      say "nada na frente de nenhuma pilha — acabou"
      break
    fi
    (( api_live || sala_live )) || { say "os dois trilhos travaram — precisam de uma pessoa"; break; }

    only='["shemaobt/shema-api","shemaobt/internalization-room"]'
    (( api_live )) || only='["shemaobt/internalization-room"]'
    (( sala_live )) || only='["shemaobt/shema-api"]'
    build_prompt "$only"

    say "tentativa $attempt/$MAX_ATTEMPTS — restam $before PRs abertos — trilhos: $only"
    claude -p "$PROMPT" \
      --model opus \
      --permission-mode bypassPermissions \
      --add-dir "$API" \
      --output-format text \
      >>"$RUNLOG" 2>&1
    say "tentativa $attempt terminou com código $?"

    after=$(open_total)
    read -r api_after sala_after <<< "$(open_each)"
    # A dead train must not hide behind a healthy one. Counting both repos together is
    # what let one impossible merge be retried eight times while the other train advanced.
    if (( api_live )); then
      if (( api_after < api_before )); then api_stuck=0; else (( api_stuck++ )); fi
      if (( api_stuck >= 2 )); then api_live=0; say "trilho shema-api travado — deixando de tentar"; fi
    fi
    if (( sala_live )); then
      if (( sala_after < sala_before )); then sala_stuck=0; else (( sala_stuck++ )); fi
      if (( sala_stuck >= 2 )); then sala_live=0; say "trilho internalization-room travado — deixando de tentar"; fi
    fi
    local pause=$SLEEP_STALLED
    if (( after < before )); then
      say "avançou: $((before - after)) PR(s) mergeado(s) nesta tentativa"
      stuck=0
      pause=$SLEEP_PROGRESS
    else
      (( stuck++ ))
      say "nenhum avanço nesta tentativa (${stuck}ª seguida)"
      if (( stuck >= 2 )); then
        say "duas tentativas sem avançar — as pilhas precisam de uma pessoa. Parando."
        break
      fi
    fi

    if [[ "$(remaining)" == "0 0" ]]; then
      say "as duas pilhas chegaram ao fim"
      break
    fi
    say "dormindo ${pause}s antes da próxima sessão"
    sleep "$pause"
  done

  say "FIM — PRs abertos agora: $(open_total)"
  if [[ -f "$LEDGER" ]]; then
    say "--- o que aconteceu, PR a PR ---"
    tail -n 200 "$LEDGER" | tee -a "$RUNLOG"
  fi
}

main "$@"
