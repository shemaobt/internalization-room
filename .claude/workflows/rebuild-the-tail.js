export const meta = {
  name: 'rebuild-the-tail',
  description: 'Rebuild the last four stacked PRs onto main so they stop reverting it. Reviews and verifies; merges nothing.',
  whenToUse: 'When the PRs below a stack were squash-merged, so the branches above still carry the old content of everything beneath them and would revert main if merged. Rebuilds each branch as its own commits on top of current main and verifies nothing of main was lost.',
  phases: [
    { title: 'Rebuild', detail: 'cherry-pick each PR own commits onto main' },
    { title: 'Verify', detail: 'three lenses: did anything of main get reverted?' },
  ],
}

const REPO = 'shemaobt/shema-api'
const DIR = '/Users/joao/Desktop/work/shema/shemaobt/tripod-backend'

const TAIL = (args && args.prs) || [
  { number: 202, branch: 'feat/ir-the-room-writes-down-what-was-heard',
    range: '6e5c4ef..adbb792', expect: '5 files, +73 insertions, 0 deletions' },
  { number: 203, branch: 'feat/ir-the-release-refine-can-trust',
    range: 'adbb792..4e09b1a', expect: '4 files, +416 insertions, 1 deletion' },
  { number: 207, branch: 'feat/ir-the-wheel-tells-the-bead-count',
    range: '4e09b1a..0af2c47', expect: '7 files, +157 insertions, 3 deletions' },
  { number: 208, branch: 'feat/ir-the-opening-is-told-in-two-movements',
    range: '0af2c47..bbe4f3d', expect: '12 files, +523 insertions, 42 deletions' },
]

const REBUILT = {
  type: 'object', additionalProperties: false,
  required: ['ok', 'pushed', 'shortstat', 'notes'],
  properties: {
    ok: { type: 'boolean' }, pushed: { type: 'boolean' },
    shortstat: { type: 'string' },
    conflicts: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
}

const VERDICT = {
  type: 'object', additionalProperties: false,
  required: ['sound', 'reasoning'],
  properties: {
    sound: { type: 'boolean' }, reasoning: { type: 'string' },
    lost: { type: 'array', items: { type: 'string' } },
  },
}

function rebuild(pr) {
  return `Rebuild the branch of ${REPO}#${pr.number} onto current main, in ${DIR}. Use git and
the gh CLI. You are NOT merging anything and NOT touching any pull request's state — this
job ends at a pushed branch.

WHY. The 44 PRs below this one were squash-merged, so main holds their content under new
commits with no shared history. This branch still carries the OLD copy of all of it, 42
commits behind main. Merging it as-is would add its feature and silently revert about 500
lines of main's newer work — the review fixes made during each squash merge, plus the
regression tests guarding them. CI would not catch that, because the branch ships its own
older copies of those tests.

THE OWNER'S RULE: the most up-to-date version wins, and where two versions differ, prefer
the one that fixes bugs and carries more features. Here that means main wins for everything
that already exists, and this PR contributes only its own new work on top.

WHAT IS GENUINELY NEW: the commits in ${pr.range}, and nothing else.

  git -C ${DIR} fetch origin
  git -C ${DIR} worktree add /tmp/tail-${pr.number} origin/main
  cd /tmp/tail-${pr.number} && git checkout -B rebuild-${pr.number}
  git cherry-pick ${pr.range}

Resolve conflicts by the same rule: keep main's version of code that already exists, and add
only what the cherry-picked commit genuinely introduces. If a hunk merely restores an older
form of something main has since changed, drop it — that is the stale copy, not a change
this PR is making. Never take a whole file from the commit.

PROVE IT BEFORE PUSHING. Run:

  git diff --shortstat origin/main..HEAD

It must land close to: ${pr.expect}. Tens of files and hundreds of deletions means the
rebuild is wrong and you have carried the stale stack along — stop and report instead.

Then the repository's own gates, all of which must pass:

  cd /tmp/tail-${pr.number} && source ${DIR}/.venv/bin/activate 2>/dev/null; \\
  ruff check app tests && ruff format --check app tests && mypy app/ && \\
  JWT_SECRET_KEY=test DATABASE_URL=sqlite+aiosqlite:///:memory: \\
  python -m pytest tests -q -p no:cacheprovider

Only with both clean:

  git push --force-with-lease origin rebuild-${pr.number}:${pr.branch}

The rewrite is the point and the owner asked for it: the branch's history IS the stale
stack. Use --force-with-lease, never a plain force. Then remove the worktree:
  git -C ${DIR} worktree remove --force /tmp/tail-${pr.number}

Report the shortstat you measured, the conflicts you resolved, and whether you pushed.`
}

function verify(pr, lens) {
  return `Check one thing about ${REPO}#${pr.number}, adversarially: did rebuilding it onto
main LOSE any of main's work? Default to sound=false if you cannot convince yourself. You
are only reading — change nothing.

Branch ${pr.branch} was just rebuilt as current main plus the commits in ${pr.range}. In
${DIR}, fetch and then read:

  git diff origin/main..origin/${pr.branch}

It should contain only this PR's own contribution — close to ${pr.expect}. Anything beyond
that is a regression. Specifically:

- Deletions of lines that exist on main and are not part of what this PR sets out to change
  are the failure. Around 500 such deletions is the signature of the stale stack.
- Three places main is known to be ahead, which a bad rebuild reverts: run_turn.py (main
  replaced \`already_met: bool\` with \`opening_instruction: str\` for the verdict Speaker),
  comprehension/assessor.py (main dropped "no"/"ne" from _NEGATION_TOKENS to kill
  false-positive negation matches), and voice_handles.py (main ahead +38/-22). Confirm each
  still reads as main has it.
- tests/test_internalization_room_assessor_guards.py must not have lost a regression test.

${lens}

Return sound, short reasoning citing what you actually read, and any lost lines you found.`
}

const done = []

for (const pr of TAIL) {
  log(`#${pr.number} — reconstruindo sobre o main`)

  const built = await agent(rebuild(pr), {
    label: `rebuild:#${pr.number}`, phase: 'Rebuild', schema: REBUILT, effort: 'high',
  })
  if (!built || !built.ok || !built.pushed) {
    done.push({ number: pr.number, stopped: built ? built.notes : 'no answer' })
    break
  }
  log(`  #${pr.number}: ${built.shortstat}`)

  const lenses = [
    'Read it as the author of the fixes that live on main: is any of your work missing?',
    'Read it as a reviewer who trusts only the diff: does it contain anything this PR did not set out to do?',
    'Read it as the person running this in production tomorrow: what silently regressed?',
  ]
  const votes = await parallel(lenses.map((lens) => () =>
    agent(verify(pr, lens), {
      label: `verify:#${pr.number}`, phase: 'Verify', schema: VERDICT, effort: 'high',
    })
  ))
  const good = votes.filter(Boolean)
  const sound = good.filter((v) => v.sound).length >= 2
  const lost = good.flatMap((v) => v.lost || [])
  if (!sound) {
    done.push({ number: pr.number, stopped: `verificação reprovou: ${lost.join('; ')}` })
    break
  }
  done.push({ number: pr.number, rebuilt: true, shortstat: built.shortstat, lenses: good.length })
}

return { done, note: 'branches reconstruídas e verificadas; nada foi mergeado' }
