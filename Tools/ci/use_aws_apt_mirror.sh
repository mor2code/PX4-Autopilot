#!/bin/sh
# Switch the container's apt sources to the AWS regional Ubuntu mirror that is
# local to the runs-on instance (default), or restore the canonical archive
# sources that were saved on the way in (--restore).
#
# Why EC2-only on the happy path: the default archive.ubuntu.com round-robin
# sometimes serves out-of-sync index files mid-sync, breaking apt-get update
# with errors like:
#   File has unexpected size (25378 != 25381). Mirror sync in progress?
# The Canonical-operated EC2 mirrors are region-local and sync aggressively,
# eliminating that failure mode.
#
# The EC2 mirror can, however, briefly lag in the .deb pool during a package
# rollout: a freshly-synced index references a .deb not yet replicated to the
# pool, giving a 404 at install time. Listing both mirrors at once would fix
# that but re-expose apt-get update to the cross-mirror index skew above. So
# instead the CI step installs against EC2 and, only if that fails, calls this
# script with --restore to fall back to the canonical archive and retries --
# by which point the mirror has usually converged.
#
# This script is a no-op outside runs-on, so it is safe to call from any CI
# job (forks, self-hosted runners, local docker runs, etc.) without changing
# behavior there.
#
# Usage (from a workflow step running inside the container):
#   ./Tools/ci/use_aws_apt_mirror.sh            # switch to EC2 mirror
#   ./Tools/ci/use_aws_apt_mirror.sh --restore  # restore canonical archive

set -e

DEB822=/etc/apt/sources.list.d/ubuntu.sources
LEGACY=/etc/apt/sources.list

if [ -z "$RUNS_ON_AWS_REGION" ]; then
    echo "use_aws_apt_mirror: not running on runs-on (RUNS_ON_AWS_REGION unset), skipping"
    exit 0
fi

if [ "$1" = "--restore" ]; then
    echo "use_aws_apt_mirror: restoring canonical archive sources"
    [ -f "${DEB822}.canonical" ] && cp "${DEB822}.canonical" "$DEB822"
    [ -f "${LEGACY}.canonical" ] && cp "${LEGACY}.canonical" "$LEGACY"
    exit 0
fi

MIRROR="http://${RUNS_ON_AWS_REGION}.ec2.archive.ubuntu.com/ubuntu"
echo "use_aws_apt_mirror: rewriting apt sources to ${MIRROR}"

# Noble (24.04+) uses the deb822 format at /etc/apt/sources.list.d/ubuntu.sources
if [ -f "$DEB822" ]; then
    cp "$DEB822" "${DEB822}.canonical"
    sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|${MIRROR}|g" \
        -e "s|http://security.ubuntu.com/ubuntu|${MIRROR}|g" \
        "$DEB822"
fi

# Jammy (22.04) and earlier use the legacy /etc/apt/sources.list
if [ -f "$LEGACY" ]; then
    cp "$LEGACY" "${LEGACY}.canonical"
    sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|${MIRROR}|g" \
        -e "s|http://security.ubuntu.com/ubuntu|${MIRROR}|g" \
        "$LEGACY"
fi
