#!/usr/bin/env bash
# The zsh config in configs/home: every file parses, and the 1Password agent
# is exported only when its socket exists.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
Z="$REPO/configs/home"

echo "zsh config"
for f in "$Z/.zshenv" "$Z/.zprofile" "$Z/.zshrc" "$Z"/.config/zsh/*.zsh; do
  check "parses: ${f#"$Z"/}" zsh -n "$f"
done

new_sandbox
SOCK_DIR="$FAKE_HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t"
agent() { HOME="$FAKE_HOME" SSH_AUTH_SOCK=/tmp/launchd-agent zsh -fc "source '$Z/.config/zsh/50-tools.zsh' 2>/dev/null; print -r -- \$SSH_AUTH_SOCK"; }
check "without 1Password, SSH_AUTH_SOCK is left alone" test "$(agent)" = /tmp/launchd-agent
mkdir -p "$SOCK_DIR"
# Socket paths are capped at ~104 bytes on macOS and the sandbox path is
# longer, so make the socket somewhere short and link it into place.
SHORT=$(mktemp -d /tmp/omsock.XXXXXX)
/usr/bin/python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$SHORT/s"
ln -s "$SHORT/s" "$SOCK_DIR/agent.sock"
check "with 1Password's socket, it points there" test "$(agent)" = "$SOCK_DIR/agent.sock"
rm -rf "$SHORT"

finish
