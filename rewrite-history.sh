#!/usr/bin/env bash
# Replace the five guide screenshots with redacted copies in every commit of master.
# Run from Git Bash in a clean clone of canfield-deployment-toolkit:
#   bash rewrite-history.sh /path/to/redaction/images
# It only rewrites your local master. Review, then push yourself with
#   git push --force-with-lease origin master
set -euo pipefail

IMG_DIR="$(cd "${1:?usage: rewrite-history.sh <redacted images dir>}" && pwd)"
ADDED=a227115          # "Add a basic user guide" - the only commit that adds images/
FILES="01-computer 02-remote-access 03-canfield-capture 04-users 06-summary"
SIGN="${SIGN:--S}"     # set SIGN= to skip signing (e.g. for a dry run)

git fetch origin master
git checkout master
git merge --ff-only origin/master
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean"; exit 1; }
git tag -f pre-redaction-backup master   # local safety net

# Stop at the commit that added the images, swap them in, re-sign everything after it.
GIT_SEQUENCE_EDITOR="sed -i 's/^pick $ADDED/edit $ADDED/'" \
  git rebase -i $SIGN "$ADDED^"
for f in $FILES; do cp "$IMG_DIR/$f.png" "images/$f.png"; done
git add images
git commit --amend --no-edit $SIGN
git rebase --continue

# Verify: none of the original image blobs are reachable from the new master.
OLD="dde26a9e4b197150e3e61a17c7813d6c8b753f5f 469def9c1545fc80a8270c1beca83d8301e3ebd2 81b856d79371631157298910040f7f763407e87e 1a92943ec9374b62b23db32b031dddae27f9dd26 cf007ba9ac06c20fd28868a4ac210393976097ab"
LEFT=$(git rev-list --objects master | grep -F -f <(tr ' ' '\n' <<<"$OLD") || true)
if [ -n "$LEFT" ]; then echo "Original image still reachable:"; echo "$LEFT"; exit 1; fi
echo "OK: master rewritten, old screenshots gone. Diff vs backup (should be images only):"
git diff --stat pre-redaction-backup master
echo "Push when happy:  git push --force-with-lease origin master"
