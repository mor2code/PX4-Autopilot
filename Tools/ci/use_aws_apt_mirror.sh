#!/bin/sh
# Rewrite the container's apt sources to prefer the AWS regional Ubuntu
# mirror that is local to the runs-on instance, while keeping the canonical
# archive.ubuntu.com as a fallback.
#
# The regional EC2 mirrors are fast and sync aggressively, but can briefly
# serve a stale package index that references a .deb version no longer on the
# mirror (e.g. mid-security-update), causing 404s.  Retaining the canonical
# archive as a fallback URI lets apt recover automatically.
#
# deb822 format (Noble/24.04+): supports space-separated fallback URIs on a
# single URIs: line — apt tries them in order.
# Legacy sources.list format (Jammy/22.04): no fallback URI support; we
# prepend a parallel deb line so both mirrors are consulted.
#
# This script is a no-op outside runs-on, so it is safe to call from any CI
# job (forks, self-hosted runners, local docker runs, etc.) without changing
# behavior there.
#
# Usage (from a workflow step running inside the container):
#   ./Tools/ci/use_aws_apt_mirror.sh

set -e

if [ -z "$RUNS_ON_AWS_REGION" ]; then
    echo "use_aws_apt_mirror: not running on runs-on (RUNS_ON_AWS_REGION unset), skipping"
    exit 0
fi

MIRROR="http://${RUNS_ON_AWS_REGION}.ec2.archive.ubuntu.com/ubuntu"
echo "use_aws_apt_mirror: preferring ${MIRROR} with canonical archive as fallback"

# Noble (24.04+) uses the deb822 format at /etc/apt/sources.list.d/ubuntu.sources.
# Space-separated URIs are tried in order; the canonical archive is kept as fallback.
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    sed -i \
        -e "s|URIs: http://archive.ubuntu.com/ubuntu|URIs: ${MIRROR} http://archive.ubuntu.com/ubuntu|g" \
        -e "s|URIs: http://security.ubuntu.com/ubuntu|URIs: ${MIRROR} http://security.ubuntu.com/ubuntu|g" \
        /etc/apt/sources.list.d/ubuntu.sources
fi

# Jammy (22.04) and earlier use the legacy /etc/apt/sources.list.
# The legacy format has no fallback URI syntax, so prepend EC2 mirror deb
# lines before the original entries.  apt prefers sources listed earlier,
# so EC2 is tried first; the canonical archive acts as fallback for 404s.
if [ -f /etc/apt/sources.list ]; then
    EC2_LINES=$(sed \
        -e "s|http://archive.ubuntu.com/ubuntu|${MIRROR}|g" \
        -e "s|http://security.ubuntu.com/ubuntu|${MIRROR}|g" \
        /etc/apt/sources.list)
    ORIG_LINES=$(cat /etc/apt/sources.list)
    printf '%s\n\n# canonical archive (fallback)\n%s\n' \
        "$EC2_LINES" "$ORIG_LINES" > /etc/apt/sources.list
fi
