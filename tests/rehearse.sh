#!/usr/bin/env bash
# rehearse.sh — Rehearse a new-Mac bootstrap in a throwaway UTM virtual machine.
#
# One-time: create a macOS VM named "omamas-base" in UTM (New → Virtualize →
# macOS, leave the installer empty to download the latest), let it install,
# then run `tests/rehearse.sh provision` to create your user and shut it down.
#
#   tests/rehearse.sh provision   first boot: create the account (asks for its
#                                 password), log in automatically, turn on SSH
#   tests/rehearse.sh start       boot a disposable copy: changes are thrown
#                                 away when it stops, so the base stays factory-fresh
#   tests/rehearse.sh stop        power off (and discard) the running copy
#   tests/rehearse.sh status      list UTM's VMs and their state
#
# Inside the VM, open Terminal and run the one-liner printed by `start`.
#
# Environment: OMAMAS_VM (default omamas-base), OMAMAS_VM_USER (default: you),
# OMAMAS_VM_FULL_NAME (default: your full name).

set -euo pipefail

VM="${OMAMAS_VM:-omamas-base}"
USER_NAME="${OMAMAS_VM_USER:-$(id -un)}"
FULL_NAME="${OMAMAS_VM_FULL_NAME:-$(id -F 2>/dev/null || id -un)}"
UTMCTL="${OMAMAS_UTMCTL:-/Applications/UTM.app/Contents/MacOS/utmctl}" # overridable for tests
# shellcheck disable=SC2088 # printed for the VM's shell to expand, not this one
REPO_DIR="~/Work/github.com/thebenwalther/omamas"
ONE_LINER="curl -fsSL https://raw.githubusercontent.com/thebenwalther/omamas/main/install.sh | OMAMAS_DIR=$REPO_DIR bash"

usage() { sed -n '2,/^$/{s/^# \{0,1\}//p;}' "$0"; }

die() {
  printf 'rehearse: %s\n' "$*" >&2
  exit 1
}

[[ -x $UTMCTL ]] || die "UTM's utmctl not found at $UTMCTL (UTM is in the Brewfile)."

case ${1:-} in
  provision)
    printf 'Password for %s in the VM (stays in the VM): ' "$USER_NAME" >&2
    read -rs password || true
    echo >&2
    [[ -n $password ]] || die "A password is required."
    printf '%s' "$password" | "$UTMCTL" start "$VM" \
      --provision-username "$USER_NAME" --provision-full-name "$FULL_NAME" \
      --provision-password-stdin --provision-auto-login --provision-ssh
    echo "Booting $VM to create $USER_NAME. Once you reach the desktop, shut the VM"
    echo "down from its Apple menu: that saved state is your clean base."
    ;;
  start)
    "$UTMCTL" start "$VM" --disposable
    echo "Disposable $VM is booting; nothing it does is saved."
    echo "In the VM, open Terminal and run:"
    echo
    echo "  $ONE_LINER"
    echo
    echo "Then run ./setup.sh again in $REPO_DIR; expect every module to report 0 changed."
    echo "Done? tests/rehearse.sh stop"
    ;;
  stop)
    "$UTMCTL" stop "$VM" --force
    echo "Stopped $VM; the disposable run's changes are gone."
    ;;
  status)
    "$UTMCTL" list
    ;;
  -h | --help | "")
    usage
    ;;
  *)
    die "Unknown command '$1' (provision, start, stop or status)."
    ;;
esac
