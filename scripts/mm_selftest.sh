#!/bin/bash
# =========================================================
# mm_selftest.sh
# Negative tests for the managed git identity hooks.
#
# 'mm doctor' checks that this machine is configured correctly. This checks the
# opposite: that the hooks actually REFUSE the states the policy forbids. A
# green doctor plus a green selftest is the full picture; doctor alone only
# proves the happy path.
#
# Runs entirely in a temporary directory and never touches a real repository.
# Forge URLs and the expected identity are read from the installed profile, so
# no address or internal hostname is hard-coded here.
#
# Policy: ~/Repositories/GIT.md
# =========================================================

set -o pipefail
set -u

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/mm_common.sh"
trap 'record_script_result "mm_selftest.sh" "$?"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
ZERO_SHA="0000000000000000000000000000000000000000"

if [[ ! -f "$GIT_PROFILE_CONF" ]]; then
    echo "❌ No git profile at $GIT_PROFILE_CONF — run 'mm restore --git-profile --apply'"
    exit 1
fi
if [[ ! -x "$LOCAL_GIT_HOOKS_DIR/pre-commit" || ! -x "$LOCAL_GIT_HOOKS_DIR/pre-push" ]]; then
    echo "❌ Managed hooks are not installed — run 'mm install'"
    exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mm-selftest.XXXXXX")" || exit 1
cleanup_work() { rm -rf "$WORK_DIR"; }
trap 'status=$?; cleanup_work; record_script_result "mm_selftest.sh" "$status"' EXIT

echo "── 🧪 mm selftest ──"
echo
echo "Sandbox: $WORK_DIR"
echo

# ── Helpers ─────────────────────────────────────────────

# Turns a forge url pattern from the profile into a usable clone URL.
concrete_url() {
    local pattern="$1"
    printf '%s\n' "${pattern%\*\*}example/selftest.git"
}

first_url_for_forge() {
    git config --file "$GIT_PROFILE_CONF" --get-all "forge.$1.url" 2>/dev/null | head -n 1
}

identity_for_forge() {
    git config --file "${LOCAL_GIT_IDENTITY_PREFIX}-$1" --get "user.$2" 2>/dev/null
}

# Creates a repo with the given remote and one commit. Hooks are skipped and the
# identity is passed in the environment, so setup never depends on the very
# behaviour under test.
new_repo() {
    local name="$1" remote="${2:-}" ident_name="${3:-selftest}" ident_email="${4:-selftest@example.com}"
    local dir="$WORK_DIR/$name"

    mkdir -p "$dir"
    git -C "$dir" init -q
    [[ -n "$remote" ]] && git -C "$dir" remote add origin "$remote"
    GIT_AUTHOR_NAME="$ident_name" GIT_AUTHOR_EMAIL="$ident_email" \
    GIT_COMMITTER_NAME="$ident_name" GIT_COMMITTER_EMAIL="$ident_email" \
        git -C "$dir" commit -q --no-verify --allow-empty -m "selftest base"
    printf '%s\n' "$dir"
}

# expect <exit-code> <description> <repo> [stdin-for-pre-push]
expect() {
    local want="$1" desc="$2" repo="$3" push_line="${4:-}"
    local hook="pre-commit" got=0 output=""

    if [[ -n "$push_line" ]]; then
        hook="pre-push"
        output="$(cd "$repo" && printf '%s\n' "$push_line" | "$LOCAL_GIT_HOOKS_DIR/pre-push" 2>&1)"
        got=$?
    else
        output="$(cd "$repo" && "$LOCAL_GIT_HOOKS_DIR/pre-commit" 2>&1)"
        got=$?
    fi

    if [[ "$got" -eq "$want" ]]; then
        printf '✅ %-46s %s\n' "$desc" "($hook exit $got)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf '❌ %-46s expected exit %s, got %s\n' "$desc" "$want" "$got"
        printf '%s\n' "$output" | sed 's/^/     /'
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── Per-forge tests ─────────────────────────────────────

while IFS= read -r forge; do
    [[ -n "$forge" ]] || continue

    url_pattern="$(first_url_for_forge "$forge")"
    if [[ -z "$url_pattern" ]]; then
        printf '⚠️  %s\n' "forge '$forge' has no url in the profile; skipped"
        continue
    fi
    url="$(concrete_url "$url_pattern")"
    exp_name="$(identity_for_forge "$forge" name)"
    exp_email="$(identity_for_forge "$forge" email)"

    if [[ -z "$exp_email" ]]; then
        printf '❌ %s\n' "no identity file for forge '$forge'; run 'mm install'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo "── forge: $forge ──"

    repo="$(new_repo "$forge-clean" "$url" "$exp_name" "$exp_email")"
    expect 0 "$forge: clean repo commits" "$repo"

    repo="$(new_repo "$forge-local" "$url" "$exp_name" "$exp_email")"
    git -C "$repo" config user.email "override@example.com"
    expect 1 "$forge: per-repo identity override" "$repo"

    repo="$(new_repo "$forge-worktree" "$url" "$exp_name" "$exp_email")"
    git -C "$repo" config extensions.worktreeConfig true
    git -C "$repo" config --worktree user.email "override@example.com"
    expect 1 "$forge: per-worktree identity override" "$repo"

    # pre-push: a commit you made but attributed to somebody else.
    repo="$(new_repo "$forge-badauthor" "$url" "$exp_name" "$exp_email")"
    base="$(git -C "$repo" rev-parse HEAD)"
    GIT_COMMITTER_NAME="$exp_name" GIT_COMMITTER_EMAIL="$exp_email" \
        git -C "$repo" commit -q --no-verify --allow-empty \
            --author="Someone Else <someone@example.com>" -m "selftest bad author"
    head="$(git -C "$repo" rev-parse HEAD)"
    expect 1 "$forge: outgoing commit, wrong author" "$repo" \
        "refs/heads/main $head refs/heads/main $base"

    # pre-push: somebody else's commit that you merged must still push.
    repo="$(new_repo "$forge-bot" "$url" "$exp_name" "$exp_email")"
    base="$(git -C "$repo" rev-parse HEAD)"
    GIT_AUTHOR_NAME="some[bot]" GIT_AUTHOR_EMAIL="some[bot]@users.noreply.example.com" \
    GIT_COMMITTER_NAME="some[bot]" GIT_COMMITTER_EMAIL="some[bot]@users.noreply.example.com" \
        git -C "$repo" commit -q --no-verify --allow-empty -m "selftest bot commit"
    head="$(git -C "$repo" rev-parse HEAD)"
    expect 0 "$forge: merged foreign commit still pushes" "$repo" \
        "refs/heads/main $head refs/heads/main $base"

    # pre-push: git's hostname fallback address, the signature of a machine that
    # lost its identity configuration.
    repo="$(new_repo "$forge-fallback" "$url" "$exp_name" "$exp_email")"
    base="$(git -C "$repo" rev-parse HEAD)"
    GIT_AUTHOR_NAME="someone" GIT_AUTHOR_EMAIL="someone@somehost.(none)" \
    GIT_COMMITTER_NAME="someone" GIT_COMMITTER_EMAIL="someone@somehost.(none)" \
        git -C "$repo" commit -q --no-verify --allow-empty -m "selftest fallback"
    head="$(git -C "$repo" rev-parse HEAD)"
    expect 1 "$forge: hostname fallback address" "$repo" \
        "refs/heads/main $head refs/heads/main $base"

    # pre-push: a brand new branch has no remote sha to diff against.
    repo="$(new_repo "$forge-newbranch" "$url" "$exp_name" "$exp_email")"
    GIT_COMMITTER_NAME="$exp_name" GIT_COMMITTER_EMAIL="$exp_email" \
        git -C "$repo" commit -q --no-verify --allow-empty \
            --author="Someone Else <someone@example.com>" -m "selftest new branch"
    head="$(git -C "$repo" rev-parse HEAD)"
    expect 1 "$forge: new branch, wrong author" "$repo" \
        "refs/heads/topic $head refs/heads/topic $ZERO_SHA"

    # pre-push: deleting a branch pushes no commits at all.
    repo="$(new_repo "$forge-delete" "$url" "$exp_name" "$exp_email")"
    base="$(git -C "$repo" rev-parse HEAD)"
    expect 0 "$forge: branch deletion" "$repo" \
        "(delete) $ZERO_SHA refs/heads/gone $base"

    echo
done < <(git_profile_forges)

# ── Forge-independent tests ─────────────────────────────

echo "── no matching forge ──"

repo="$(new_repo "unknown-forge" "https://unknown.example.com/example/x.git")"
expect 1 "remote matching no include rule" "$repo"

repo="$(new_repo "no-remote" "")"
expect 1 "repository without a remote" "$repo"

# ── Summary ─────────────────────────────────────────────

echo
echo "── 📊 Summary ───────────────────────────────────"
echo "   Passed: $PASS_COUNT"
echo "   Failed: $FAIL_COUNT"
echo

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "   ❌ The identity guard does not refuse everything it should."
    echo "      Re-run 'mm install', then this test again."
    echo
    exit 1
fi

echo "   ✅ The identity guard refuses every forbidden state."
echo
