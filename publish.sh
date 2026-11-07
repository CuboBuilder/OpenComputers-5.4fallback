#!/usr/bin/env bash
#
# Publish oc-lua54-fallback to GitHub.
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx ./publish.sh
#
# Optional overrides:
#   REPO_NAME=oc-lua54-fallback   # repository name
#   VISIBILITY=public             # public | private
#   TAG=v1.0.0
#
# Requires: git, curl. The token needs "Contents: read/write" (fine-grained,
# scoped to the target repo) or classic "repo" scope.
#
set -euo pipefail

# -------------------------------------------------------------------------__
# Configuration
# ---------------------------------------------------------------------------
OWNER="${GITHUB_OWNER:-CuboBuilder}"
REPO_NAME="${REPO_NAME:-oc-lua54-fallback}"
VISIBILITY="${VISIBILITY:-public}"
TAG="${TAG:-v1.0.0}"
JAR="build/libs/oc-lua54-fallback-1.0.0.jar"
API="https://api.github.com"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "error: GITHUB_TOKEN is not set" >&2
    echo "usage: GITHUB_TOKEN=ghp_xxx ./publish.sh" >&2
    exit 1
fi

AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}"
      -H "Accept: application/vnd.github+json"
      -H "X-GitHub-Api-Version: 2022-11-28")

log() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
log "Checking prerequisites"
command -v git  >/dev/null || { echo "error: git not found"  >&2; exit 1; }
command -v curl >/dev/null || { echo "error: curl not found" >&2; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: run this from the repository root" >&2
    exit 1
fi

log "Building"
if [[ -x ./gradlew ]]; then
    ./gradlew build --console=plain -q
fi
[[ -f "${JAR}" ]] || { echo "error: ${JAR} not found (build failed?)" >&2; exit 1; }
echo "jar: ${JAR} ($(stat -c%s "${JAR}") bytes)"

# ---------------------------------------------------------------------------
# Verify the token and find the account it belongs to
# ---------------------------------------------------------------------------
log "Verifying token"
VERIFY_JSON="$(curl -sS -f "${AUTH[@]}" "${API}/user" 2>/dev/null)" || {
    echo "error: token rejected by GitHub (check it is valid and not expired)" >&2
    exit 1
}
LOGIN="$(printf '%s' "${VERIFY_JSON}" | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' | head -1)"
echo "authenticated as: ${LOGIN}"

if [[ "${LOGIN}" != "${OWNER}" ]]; then
    echo "warning: token belongs to '${LOGIN}', not '${OWNER}'." >&2
    echo "         Set GITHUB_OWNER=${LOGIN} to publish under that account." >&2
fi

# ---------------------------------------------------------------------------
# Create the repository if it does not exist yet
# ---------------------------------------------------------------------------
log "Checking whether ${OWNER}/${REPO_NAME} exists"
HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
    "${API}/repos/${OWNER}/${REPO_NAME}")"

if [[ "${HTTP_CODE}" == "404" ]]; then
    log "Creating repository ${OWNER}/${REPO_NAME}"
    PAYLOAD=$(printf '{"name":"%s","private":%s,"description":"Server-side crash workaround for the Lua 5.4 bug in OpenComputers (unofficial, AI-generated, unmaintained)","has_issues":true,"has_wiki":false}' \
        "${REPO_NAME}" \
        "$([[ "${VISIBILITY}" == "private" ]] && echo true || echo false)")
    curl -sS -f "${AUTH[@]}" -X POST "${API}/user/repos" \
        -d "${PAYLOAD}" >/dev/null
    echo "created"
elif [[ "${HTTP_CODE}" == "200" ]]; then
    echo "already exists, will push into it"
else
    echo "error: unexpected HTTP ${HTTP_CODE} when checking the repository" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Push the source
# ---------------------------------------------------------------------------
log "Pushing source to ${OWNER}/${REPO_NAME}"
REMOTE="https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER}/${REPO_NAME}.git"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${CURRENT_BRANCH}" == "HEAD" ]]; then
    CURRENT_BRANCH="main"
    git branch -M main
fi

if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "${REMOTE}"
else
    git remote add origin "${REMOTE}"
fi

git push -u origin "${CURRENT_BRANCH}"

# Drop the token from the stored remote; never leave it in .git/config.
git remote set-url origin "https://github.com/${OWNER}/${REPO_NAME}.git"
echo "pushed branch ${CURRENT_BRANCH}"

# ---------------------------------------------------------------------------
# Create the release and attach the jar
# ---------------------------------------------------------------------------
log "Creating release ${TAG}"
EXISTING_TAG="$(curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
    "${API}/repos/${OWNER}/${REPO_NAME}/releases/tags/${TAG}")"

if [[ "${EXISTING_TAG}" == "200" ]]; then
    echo "release ${TAG} already exists; skipping creation"
else
    RELEASE_BODY=$(cat <<'EOF'
Server-side crash workaround for the Lua 5.4 bug in OpenComputers.

**Unmaintained, AI-generated, no warranty.** Its only purpose is to keep your
world accessible instead of losing it to a hard JVM crash. Back up your world
before installing. This does not fix the upstream defect.

Makes every CPU configured for Lua 5.4 run Lua 5.3 instead.
EOF
)
    RELEASE_JSON=$(printf '{"tag_name":"%s","name":"%s","body":%s,"draft":false,"prerelease":false}' \
        "${TAG}" "${TAG}" "$(printf '%s' "${RELEASE_BODY}" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g;s/^/"/;s/$/"/')")

    RELEASE_RESPONSE="$(curl -sS -f "${AUTH[@]}" -X POST \
        "${API}/repos/${OWNER}/${REPO_NAME}/releases" -d "${RELEASE_JSON}")" || {
        echo "error: failed to create the release" >&2
        exit 1
    }
    echo "release created"
fi

log "Uploading ${JAR}"
UPLOAD_URL="https://uploads.github.com/repos/${OWNER}/${REPO_NAME}/releases/tags/${TAG}/assets?name=$(basename "${JAR}")"
curl -sS -f "${AUTH[@]}" \
    -H "Content-Type: application/java-archive" \
    -X POST "${UPLOAD_URL}" --data-binary "@${JAR}" >/dev/null && echo "asset uploaded"

log "Done"
echo "repository: https://github.com/${OWNER}/${REPO_NAME}"
echo "release:    https://github.com/${OWNER}/${REPO_NAME}/releases/tag/${TAG}"
