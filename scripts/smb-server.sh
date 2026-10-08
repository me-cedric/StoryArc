#!/usr/bin/env bash
# A real SMB2/3 server over the fixture corpus.
#
# The same shape as `opds-server.mjs` and `kavita-server.mjs`, for the same reason: a
# capability nobody can re-run is a capability nobody can trust.
#
# Samba rather than impacket, because impacket derives its signing key without NTLM key
# exchange and every correct client then rejects its responses -- which left authenticated
# access unprovable. Samba signs correctly, so the authenticated path is the one under test.
#
#     scripts/smb-server.sh [--encrypted] [--writable] [corpus] [port]
#
# The default port is 4445: binding 445 needs root, and macOS is often already using it.
set -euo pipefail

# `--encrypted` serves with `smb encrypt = required`, on its own port, so the client's
# refusal of a server it cannot talk to is testable rather than assumed.
ENCRYPTED=no
# `--writable` adds a share named `Sync` that the client can write, on its own port, for the
# sync document of `library-sync` task 2.2. The share is an empty folder made at each start.
# The corpus share stays read only.
WRITABLE=no
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --encrypted) ENCRYPTED=yes ;;
    --writable) WRITABLE=yes ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

CORPUS="${1:-$HOME/StoryArcCorpus}"
PORT="${2:-}"
if [[ -z "$PORT" ]]; then
  case "$ENCRYPTED/$WRITABLE" in
    no/no) PORT=4445 ;;
    yes/no) PORT=4446 ;;
    no/yes) PORT=4448 ;;
    yes/yes) PORT=4449 ;;
  esac
fi
# Samba maps its own accounts onto Unix ones, so the login has to be a user this machine
# already has. The password below is Samba's, not the machine's.
USER_NAME="$(id -un)"
PASSWORD="lovelace"
SHARE="Comics"

SMBD="/opt/homebrew/sbin/samba-dot-org-smbd"
if [[ ! -x "$SMBD" ]]; then
  echo "no samba — run: brew install samba" >&2
  exit 2
fi
if [[ ! -d "$CORPUS" ]]; then
  echo "no corpus at $CORPUS — run: node scripts/corpus.mjs" >&2
  exit 2
fi

# One folder per port, so two servers running at once never share their state.
ROOT="${TMPDIR:-/tmp}/storyarc-smb-$PORT"
rm -rf "$ROOT"
mkdir -p "$ROOT/private" "$ROOT/lock" "$ROOT/state" "$ROOT/cache" "$ROOT/run" "$ROOT/sync"

cat > "$ROOT/smb.conf" <<CONF
[global]
   workgroup = WORKGROUP
   server string = StoryArc fixtures
   security = user
   # SMB 2 at the floor. \`network-share\` requires the app to refuse SMB 1, and a server
   # that still offered it would let a broken refusal pass unnoticed.
   server min protocol = SMB2_02
   server max protocol = SMB3_11
   server signing = mandatory
   smb encrypt = $( [[ "$ENCRYPTED" == yes ]] && echo required || echo default )
   smb ports = $PORT
   private dir = $ROOT/private
   lock directory = $ROOT/lock
   state directory = $ROOT/state
   cache directory = $ROOT/cache
   pid directory = $ROOT/run
   log file = $ROOT/log.%m
   passdb backend = tdbsam:$ROOT/private/passdb.tdb
   map to guest = Never
   disable spoolss = yes
   load printers = no
   printing = bsd
   printcap name = /dev/null

[$SHARE]
   path = $CORPUS
   read only = yes
   guest ok = no
CONF

if [[ "$WRITABLE" == yes ]]; then
  cat >> "$ROOT/smb.conf" <<CONF

[Sync]
   path = $ROOT/sync
   read only = no
   guest ok = no
CONF
fi

# The account the tests log in as. `-L` is local mode, which is what smbpasswd needs when
# it is not run by root; the password lives only in this fixture server's own database.
printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" |
  /opt/homebrew/bin/pdbedit -s "$ROOT/smb.conf" -a -u "$USER_NAME" -t >/dev/null

echo "smb mock: //localhost:$PORT/$SHARE"
[[ "$WRITABLE" == yes ]] && echo "  writable: //localhost:$PORT/Sync  ($ROOT/sync)"
echo "  serving $CORPUS"
echo "  $USER_NAME / $PASSWORD   (signing mandatory, SMB2 to SMB3.1.1)"

# `--foreground`, not `--interactive`: interactive mode serves a single connection and
# exits, so the second client of a test run finds nothing there. Stdin is closed because
# smbd otherwise reads it as an inetd-supplied socket and fails the first client with
# "get_remote_hostname failed".
exec "$SMBD" --configfile="$ROOT/smb.conf" --foreground --no-process-group --debuglevel=1 < /dev/null
