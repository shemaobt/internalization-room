export const meta = {
  name: 'merge-the-stacks',
  description: 'Review, fix, gate on CI and land two stacked PR trains, bottom-up',
  whenToUse:
    'Landing a long stack of PRs unattended. Reviews each PR with the joao-review rubric, refutes its own findings before acting on any, fixes what survives, waits for every check, and only then merges. Stops the train rather than guessing. Every run picks up at whatever is now the front of each stack, so re-running it is how you resume — pair it with /loop to carry through a usage window on its own.',
  phases: [
    { title: 'Prepare', detail: 'find the front of the stack and freshen it' },
    { title: 'Review', detail: 'one reviewer per PR, joao-review rubric' },
    { title: 'Refute', detail: 'two skeptics per finding' },
    { title: 'Fix', detail: 'apply what survived, run the repo gates' },
    { title: 'Land', detail: 'wait for checks, then merge bottom-up' },
  ],
}

const STYLE = '/Users/joao/.claude/skills/joao-review/reference/review-style.md'

const TRAINS = (args && args.trains) || [
  {
    repo: 'shemaobt/shema-api',
    dir: '/Users/joao/Desktop/work/shema/shemaobt/tripod-backend',
    author: 'joaocarvoli',
    gates:
      'cd DIR && source /Users/joao/Desktop/work/shema/shemaobt/tripod-backend/.venv/bin/activate && ' +
      'ruff check app tests && ruff format --check app tests && mypy app/ && ' +
      'JWT_SECRET_KEY=test DATABASE_URL=sqlite+aiosqlite:///:memory: ' +
      'python -c "import os,pytest; os._exit(pytest.main([\'tests\',\'-q\',\'-k\',\'internalization_room\']))"',
    rules:
      'Python 3.11, FastAPI, SQLAlchemy async, Pydantic v2. Docstrings are required by ' +
      'this repo CLAUDE.md and are NOT code comments. Never add `#` comments.',
  },
  {
    repo: 'shemaobt/internalization-room',
    dir: '/Users/joao/Desktop/work/shema/shemaobt/internalization-room',
    author: null,
    gates: 'cd DIR && flutter analyze && flutter test',
    rules:
      'Flutter. CI also greps for `Text(` under lib/features/sala/presentation/ (the room ' +
      'is wordless) and for `skip:` under test/. Never add `//` or `///` comments to code ' +
      'you write; explanation belongs in the commit message.',
  },
]

// Which trains to work this run. A train that has stalled twice is not worth another
// session — the driver drops it from here and keeps the healthy one moving.
const ONLY = (args && args.only) || null
const LAND = (args && args.land) === true
const MAX_PER_TRAIN = (args && args.maxPrs) || 100
const RESERVE = (args && args.reserveTokens) || 250000
const LEDGER = '/Users/joao/.claude/merge-the-stacks.log'
const MERGE_METHOD = (args && args.mergeMethod) || 'default'

const FRONT = {
  type: 'object',
  additionalProperties: false,
  required: ['found', 'reason'],
  properties: {
    found: { type: 'boolean' },
    number: { type: 'integer' },
    title: { type: 'string' },
    branch: { type: 'string' },
    headSha: { type: 'string' },
    ready: { type: 'boolean', description: 'true when the branch is clean against main' },
    resolved: {
      type: 'array',
      items: { type: 'string' },
      description: 'files whose conflicts were settled in the PR\'s favour',
    },
    reason: { type: 'string', description: 'why not found, or what had to be done to freshen it' },
  },
}

const CHAIN = {
  type: 'object',
  additionalProperties: false,
  required: ['ok', 'prs', 'reason'],
  properties: {
    ok: { type: 'boolean' },
    reason: { type: 'string' },
    prs: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['number', 'title', 'branch'],
        properties: {
          number: { type: 'integer' },
          title: { type: 'string' },
          branch: { type: 'string' },
        },
      },
    },
  },
}

const FINDINGS = {
  type: 'object',
  additionalProperties: false,
  required: ['verdict', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['approve', 'request changes'] },
    rationale: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['file', 'line', 'comment', 'lens', 'why_in_scope'],
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          comment: { type: 'string' },
          lens: { type: 'integer', minimum: 1, maximum: 5 },
          why_in_scope: { type: 'string' },
        },
      },
    },
  },
}

const REFUTED = {
  type: 'object',
  additionalProperties: false,
  required: ['refuted', 'reasoning'],
  properties: {
    refuted: { type: 'boolean' },
    reasoning: { type: 'string' },
  },
}

const FIXED = {
  type: 'object',
  additionalProperties: false,
  required: ['applied', 'gatesGreen', 'pushed', 'notes'],
  properties: {
    applied: { type: 'array', items: { type: 'string' } },
    left: { type: 'array', items: { type: 'string' } },
    gatesGreen: { type: 'boolean' },
    pushed: { type: 'boolean' },
    notes: { type: 'string' },
  },
}

const LANDED = {
  type: 'object',
  additionalProperties: false,
  required: ['merged', 'checksGreen', 'notes'],
  properties: {
    merged: { type: 'boolean' },
    checksGreen: { type: 'boolean' },
    repaired: { type: 'boolean' },
    notes: { type: 'string' },
  },
}

function prepare(train) {
  const who = train.author ? `--author ${train.author}` : ''
  return `You are moving one stacked PR train forward, in ${train.repo}.

The local clone is at ${train.dir}. The GitHub MCP tools are NOT connected — use the \`gh\`
CLI for everything.

FIND THE FRONT OF THE STACK. Every PR in this train targets the one below it; only the
bottom one targets \`main\`. List the open PRs and pick the single one whose baseRefName is
exactly \`main\`:

  gh pr list -R ${train.repo} --state open --limit 200 ${who} \\
    --json number,title,headRefName,baseRefName,isDraft,mergeable,mergeStateStatus

- If NONE target main, the train is almost certainly NOT done — check before you say so.
  This workflow deliberately keeps merged branches (deleting them would close the PR
  above), and GitHub only auto-retargets a child PR when its base branch is deleted. So
  after every merge the new root is left pointing at a branch whose PR is already merged.
  Expect exactly that at the start of most runs. Find it: take each open PR in this train
  whose baseRefName is not main, and check whether that base branch belongs to a PR that
  is already MERGED (\`gh pr list -R ${train.repo} --state merged --limit 20 --json
  number,headRefName\`). The one that does is the root — retarget it and treat it as the
  front:

    gh pr edit <n> -R ${train.repo} --base main

  Retargeting usually surfaces conflicts; resolve them under the rules below. Only return
  found=false with reason "stack empty" when there is genuinely no open PR left in the
  chain — never merely because nothing currently points at main.
- If exactly one does, that is the front.
- If SEVERAL do, they are not a fork — they are the stack root plus standalone PRs that
  happen to sit on main. Pick the root: the one whose headRefName is the baseRefName of
  another still-open PR in the same list. A PR on main that nothing is stacked on is not
  part of this train; leave it alone and never merge it. (Today that is #140 in shema-api,
  which is deliberately out of scope.) Only if TWO of them are each carrying a chain is it
  a real fork — then return found=false naming both, because that is a human decision.

FRESHEN IT. With the front PR chosen:
- \`gh pr view <n> -R ${train.repo} --json mergeable,mergeStateStatus,headRefOid\`
- If it is merely behind main, bring main into the branch WITHOUT rewriting history —
  \`gh pr update-branch <n> -R ${train.repo}\` — then re-read headRefOid. Never rebase,
  never force-push: every branch above this one is built on these exact commits, and
  rewriting them detaches the whole stack.

- If mergeable is CONFLICTING, resolve it. The owner's standing rule for this run: **the
  PR wins**. It carries the newer work, and \`main\` only has what earlier PRs in this same
  train put there. Work in a throwaway worktree so the user's own checkout is untouched:

    git -C ${train.dir} fetch origin
    git -C ${train.dir} worktree add /tmp/land-<n>-merge <branch>
    cd /tmp/land-<n>-merge
    git merge origin/main            # conflicts expected
    # for every conflicted path, keep the branch's version:
    git checkout --ours -- <path>    # "ours" IS this PR's branch during a merge
    git add <path>
    git commit --no-edit
    ${train.gates.replace('DIR', '/tmp/land-<n>-merge')}
    git push                          # never --force
    git -C ${train.dir} worktree remove --force /tmp/land-<n>-merge

  Two hard limits on that. If the gates go RED after resolving, stop: return ready=false
  with the failing gate named — a resolution that breaks the build is not a resolution. And
  if a conflicted file is one that a lower PR in this same train already fixed — in this
  run OR in any earlier run of this workflow — then main's side is the reviewed one and
  taking the PR's side would silently undo it. This train lands across many runs, so
  assume that is the common case, not the rare one. Read the two sides before choosing:
  where main is stricter (a narrower type, a required argument, a removed fallback), keep
  MAIN's version and re-apply the PR's own new work on top of it. "The PR wins" settles
  work the PR actually authored, never a fix that already landed below it.

  Known case in shema-api right now: \`app/services/platform/tts.py\` conflicts because
  #157 landed a squashed fix (\`c437b884 refactor(platform): _synthesize takes the model it
  is already given\`) that made \`_synthesize\`'s \`model\` a required \`str\`. The branch
  still has the older \`model: str | None = None\` with a \`cfg.elevenlabs_tts_model\`
  fallback. Keep main's required-\`str\` signature. The gates will NOT catch this one — the
  only call site passes \`model\` explicitly — so it is on you to get it right.

  Every path you settled this way goes in \`resolved\`, so a person can read them later.

- Otherwise ready=true with an empty \`resolved\`.

Return the front PR's number, title, branch, head SHA, whether it is ready, what you
resolved, and one line on what you did.`
}

function chainOf(train) {
  const who = train.author ? `--author ${train.author}` : ''
  return `Work out the whole merge order of one stacked PR train in ${train.repo}, in a
single pass. The GitHub MCP tools are NOT connected — use \`gh\`.

  gh pr list -R ${train.repo} --state open --limit 200 ${who} \\
    --json number,title,headRefName,baseRefName,isDraft

Every PR in the train targets the one below it; only the root targets \`main\`. Build the
order by walking the links: find the root, then repeatedly find the PR whose baseRefName is
the current one's headRefName.

A PR whose base branch was already MERGED counts as being on main too. The land step keeps
merged branches alive for the stack above, and GitHub only retargets dependants when the
base branch is deleted — so the front of a train is very often a PR still pointing at a
branch that is already in main. Check any candidate base with
\`gh api repos/${train.repo}/compare/main...<base> --jq .status\`: "identical" or "behind"
means that base is already in main, and the PR sitting on it is the real front. Retarget it:
\`gh pr edit <n> -R ${train.repo} --base main\`.

- If NO PR is on main and none sits on an already-merged base, the train is done: ok=false,
  reason "stack empty".
- If SEVERAL do, they are the root plus standalone PRs that merely sit on main. The root is
  the one another open PR is stacked on. A PR nothing is stacked on is not part of this
  train — leave it out entirely and never merge it. (Today that is #140 in shema-api.) Only
  if TWO of them each carry a chain is it a real fork: ok=false naming both.

Return the PRs in merge order, bottom first. Do not touch anything, do not merge anything.`
}

function review(train, pr) {
  return `Review ${train.repo}#${pr.number} — "${pr.title}" — as a stand-in for João
(@joaocarvoli).

FIRST read these in full. They are the spec, not background:
- ${STYLE}
- ${train.dir}/CLAUDE.md if it exists

The GitHub MCP tools are NOT connected. Use \`gh\`:
  gh pr view ${pr.number} -R ${train.repo} --json title,body,files
  gh pr diff ${pr.number} -R ${train.repo}
Open specific files under ${train.dir} only to verify a finding.

RULE 0 — CRITICAL, BUT NEVER OUT OF SCOPE. Overrides everything.
Be genuinely critical about the diff AS WRITTEN — never grow it.
- Never design architecture in a comment. No "consider extracting", no new base classes,
  no generic helpers, no speculative extensibility.
- Never demand fixes to pre-existing code the PR merely touches.
- Never request features, flags, config toggles or cannot-happen guards the PR did not set
  out to add.
- If something real is out of scope, name it as out of scope and let it go.
- Match review length to PR size. If the diff is clean, say so and add nothing. NEVER
  invent a finding to look thorough — a false finding costs more than a missed nit.
- Every finding must point at a line and name a concrete defect or violated convention.

BEFORE opening any finding, check it against §6 of the style reference — the rules João
states that his own code breaks. If it is on that list, drop it.

THIS RUN HAS A HIGHER BAR THAN A NORMAL REVIEW. Whatever survives will be acted on
automatically and then merged, unattended, with nobody reading it first. So raise only
findings you would be willing to have a machine fix without asking. Anything you would
want to discuss first is not a finding here — leave it out and say so in the rationale.

LENSES, in priority order (details in the reference): 1 typed contracts; 2 domain
invariants and prompts-as-code; 3 consistency (layer discipline, migrations, sync I/O in
async paths); 4 real-world latency; 5 intent against the PR's stated purpose.

${train.rules}

Return the verdict, a one-line rationale, and the findings. Returning zero findings is a
valid and good answer. Do not post anything. Do not edit any file.`
}

function refute(train, pr, finding, lens) {
  return `Try hard to REFUTE this review finding on ${train.repo}#${pr.number}. Default to
refuted=true when the evidence is thin — this finding will otherwise be fixed by a machine
and merged with nobody watching.

FINDING
  file: ${finding.file}:${finding.line}
  lens: ${finding.lens}
  claim: ${finding.comment}
  why the reviewer says it is in scope: ${finding.why_in_scope}

Read ${STYLE} (especially §6, the rules João's own code breaks) and check the real code in
${train.dir} and the real diff (\`gh pr diff ${pr.number} -R ${train.repo}\`).

Refute it if ANY of these hold:
- the line does not say what the finding claims;
- it is on the §6 list of false findings;
- it asks to grow the diff: architecture, extraction, a new abstraction, a guard for
  something that cannot happen, a feature the PR never set out to add;
- it demands a change to pre-existing code the PR merely touches;
- it is a matter of taste with no concrete defect behind it;
- fixing it mechanically could plausibly change behaviour the PR intends.

${lens}

Return refuted plus one short paragraph of reasoning citing what you actually read.`
}

function fix(train, pr, keep) {
  const list = keep
    .map((f, i) => `${i + 1}. ${f.file}:${f.line} — ${f.comment}`)
    .join('\n')
  return `Apply these confirmed review findings to ${train.repo}#${pr.number}, branch
\`${pr.branch}\`, then prove the repo's own gates still pass.

${list}

WORK IN A THROWAWAY WORKTREE — never disturb the checkout the user has open:
  git -C ${train.dir} fetch origin
  git -C ${train.dir} worktree add /tmp/land-${pr.number} ${pr.branch}
  cd /tmp/land-${pr.number}
...and when you are finished, whatever happened:
  git -C ${train.dir} worktree remove --force /tmp/land-${pr.number}

RULES
- Fix ONLY what is listed. Do not tidy anything else, do not reformat untouched code, do
  not rename, do not add tests for behaviour nobody asked about.
- ${train.rules}
- Never add code comments. The explanation goes in the commit message: say what was wrong
  and what it cost, in the voice the surrounding commits already use.
- Never rebase, never amend, never force-push. Every branch above this one is built on
  these commits. Add new commits only.
- If a finding cannot be fixed without a judgment call — it needs a design decision, or the
  fix would change what the PR is for — LEAVE IT, list it in \`left\`, and say why. That is
  a good outcome, not a failure.

GATES — run them in the worktree and do not push until they pass:
  ${train.gates.replace('DIR', '/tmp/land-' + pr.number)}

Then commit and \`git push\` the branch (no force). Return what you applied, what you left,
whether the gates went green, and whether you pushed.`
}

function land(train, pr) {
  return `Land ${train.repo}#${pr.number} — branch \`${pr.branch}\` — but only if every
check passes. The GitHub MCP tools are not connected; use \`gh\`.

1. CONFIRM IT IS ACTUALLY THE FRONT, and freshen it. \`gh pr view ${pr.number} -R ${train.repo}
   --json baseRefName,mergeable,mergeStateStatus,headRefOid\`. Its base must be \`main\` — if it
   is not, the train moved under you: stop, merged=false, and say so. If it is merely behind
   main, \`gh pr update-branch ${pr.number} -R ${train.repo}\`. If it is CONFLICTING, resolve
   it the owner's way — the PR wins, it carries the newer work — in a throwaway worktree:
     git -C ${train.dir} worktree add /tmp/land-${pr.number}-merge ${pr.branch}
     cd /tmp/land-${pr.number}-merge && git merge origin/main
     git checkout --ours -- <each conflicted path> && git add -A && git commit --no-edit
     ${train.gates.replace('DIR', '/tmp/land-' + pr.number + '-merge')}
     git push   # never --force
   and remove the worktree afterwards. If the gates go red after resolving, stop.

2. WAIT FOR THE CHECKS. \`gh pr checks ${pr.number} -R ${train.repo} --watch --interval 30\`
   blocks until they conclude. If it exits non-zero, read which check failed:
   \`gh pr checks ${pr.number} -R ${train.repo}\` and
   \`gh run view <id> -R ${train.repo} --log-failed\`.

3. ONE REPAIR ATTEMPT, and only for a failure you can name. Work in a throwaway worktree:
     git -C ${train.dir} worktree add /tmp/land-${pr.number}-ci ${pr.branch}
   fix, run \`${train.gates.replace('DIR', '/tmp/land-' + pr.number + '-ci')}\`, commit,
   push, remove the worktree, and wait for the checks again. Never force-push. If it is red
   a second time, STOP: return merged=false with the failing check named. Do not try again.

4. MERGE, only on green:
   ${
     LAND
       ? `   gh pr ready ${pr.number} -R ${train.repo}     # these PRs are drafts

   Use the repository's own default merge method. \`gh pr merge\` refuses to pick one for
   you outside a terminal, so read it and pass the matching flag:

     gh repo view ${train.repo} --json viewerDefaultMergeMethod --jq .viewerDefaultMergeMethod
     # MERGE -> --merge   SQUASH -> --squash   REBASE -> --rebase

   ${MERGE_METHOD === 'default' ? '' : 'The run overrode this: use --' + MERGE_METHOD + '.'}

   ${
     train.repo === 'shemaobt/shema-api'
       ? `This repository requires a bypass and the owner authorised it, verbatim:

       "I authorise merging my own PRs on shemaobt/shema-api using gh pr merge --admin,
        bypassing the required approving review on main."

   The need is structural, not a shortcut: main requires one approving review and GitHub
   does not let an author approve their own pull request, so he cannot satisfy the rule on
   his own stack. enforce_admins is false, so an admin may proceed. Merge with:

     gh pr merge ${pr.number} -R ${train.repo} <that flag> --admin`
       : `This repository has NO branch protection on main — nothing requires a review and
   there is nothing to bypass. Merge plainly, and never pass --admin here; asking to bypass
   a rule that does not exist is both pointless and alarming to anything watching:

     gh pr merge ${pr.number} -R ${train.repo} <that flag>`
   }

   Do NOT pass --delete-branch. On a stacked train the merged head branch is the
   base of the PR above it, and deleting it makes GitHub CLOSE that PR rather than
   retarget it to main — which detaches every branch above. Leave the branch.
`
       : `   DO NOT MERGE. This run was started without \`land: true\`, so stop here and
   report that the PR is green and would have been merged.`
   }

5. HAND THE TRAIN FORWARD. The branch you just merged is kept, not deleted, so GitHub will
   NOT retarget the PR above it — it would still point at a branch that is already in main,
   and the next pass would find no front at all. Retarget it yourself:
     next=$(gh pr list -R ${train.repo} --state open --limit 200 --json number,baseRefName \\
       --jq '[.[] | select(.baseRefName=="${pr.branch}")] | .[0].number')
     [ -n "$next" ] && gh pr edit "$next" -R ${train.repo} --base main

6. WRITE IT DOWN, whatever happened — this is the trail a person reads in the morning,
   and the only record that survives a run that is cut short:

     printf '%s\\t${train.repo}#${pr.number}\\t%s\\t%s\\n' "$(date -u +%FT%TZ)" \\
       "<merged|green-not-merged|stopped>" "<one short reason>" >> ${LEDGER}

Return whether the checks went green, whether you repaired anything, whether you merged,
and one line of notes.`
}

async function runTrain(train) {
  const landed = []
  const notes = []

  // The whole order, once. It used to be a scout agent per PR — three gh calls dressed up
  // as a session, and the measurement said the agents, not CI, were what the night was
  // spent on.
  const chain = await agent(chainOf(train), {
    label: `chain:${train.repo}`,
    phase: 'Prepare',
    schema: CHAIN,
    effort: 'low',
  })
  if (!chain || !chain.ok || !chain.prs.length) {
    return { repo: train.repo, landed, notes: [chain ? chain.reason : 'no chain'] }
  }

  const queue = chain.prs.slice(0, MAX_PER_TRAIN)
  log(`${train.repo}: ${queue.length} na fila — #${queue.map((p) => p.number).join(' → #')}`)

  // Read the next PR while this one is landing. A review does not depend on the PR below
  // it having merged — the diff is the same either way — so the expensive stage and the
  // waiting stage overlap instead of queueing.
  const readOf = (pr) =>
    agent(review(train, pr), {
      label: `review:#${pr.number}`,
      phase: 'Review',
      schema: FINDINGS,
      effort: 'high',
    })

  let ahead = readOf(queue[0])

  for (let i = 0; i < queue.length; i++) {
    if (budget.total && budget.remaining() < RESERVE) {
      notes.push(`paused on budget after ${landed.length} PRs — run it again to carry on`)
      break
    }

    const pr = queue[i]
    const read = await ahead
    ahead = i + 1 < queue.length ? readOf(queue[i + 1]) : null

    const raised = (read && read.findings) || []
    const judged = await parallel(
      raised.map((finding) => () =>
        parallel([
          () =>
            agent(
              refute(train, pr, finding, 'Judge it as a reviewer who has to live with this codebase.'),
              { label: `refute:#${pr.number}`, phase: 'Refute', schema: REFUTED }
            ),
          () =>
            agent(
              refute(train, pr, finding, 'Judge it as the author: would this comment have grown your diff?'),
              { label: `scope:#${pr.number}`, phase: 'Refute', schema: REFUTED }
            ),
        ]).then((votes) => ({
          finding,
          survives: votes.filter(Boolean).filter((v) => !v.refuted).length >= 2,
        }))
      )
    )

    const keep = judged.filter(Boolean).filter((j) => j.survives).map((j) => j.finding)
    log(`  #${pr.number}: ${raised.length} levantados, ${keep.length} sobreviveram`)

    if (keep.length) {
      const fixed = await agent(fix(train, pr, keep), {
        label: `fix:#${pr.number}`,
        phase: 'Fix',
        schema: FIXED,
        effort: 'high',
      })
      if (!fixed || !fixed.gatesGreen) {
        notes.push(`#${pr.number} stopped: fixes did not go green — ${fixed ? fixed.notes : 'no answer'}`)
        break
      }
      if (fixed.left && fixed.left.length) {
        notes.push(`#${pr.number} left for a person: ${fixed.left.join('; ')}`)
      }
    }

    const done = await agent(land(train, pr), {
      label: `land:#${pr.number}`,
      phase: 'Land',
      schema: LANDED,
      effort: 'medium',
    })
    if (!done || !done.checksGreen) {
      notes.push(`#${pr.number} stopped on checks: ${done ? done.notes : 'no answer'}`)
      break
    }
    if (LAND && !done.merged) {
      notes.push(`#${pr.number} green but not merged: ${done.notes}`)
      break
    }

    landed.push({
      number: pr.number,
      title: pr.title,
      raised: raised.length,
      fixed: keep.length,
      merged: done.merged === true,
    })
  }

  return { repo: train.repo, landed, notes }
}

const chosen = ONLY ? TRAINS.filter((t) => ONLY.indexOf(t.repo) !== -1) : TRAINS
const trains = await parallel(chosen.map((train) => () => runTrain(train)))

return {
  landed: trains.filter(Boolean),
  mode: LAND ? 'landing' : 'rehearsal (no merges)',
  mergeMethod: MERGE_METHOD,
}
