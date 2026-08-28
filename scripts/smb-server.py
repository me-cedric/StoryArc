#!/usr/bin/env python3
"""A real SMB2 server over the fixture corpus.

The same shape as `opds-server.mjs` and `kavita-server.mjs`, for the same
reason: a capability nobody can re-run is a capability nobody can trust. This
one is Python because impacket is the only SMB server that installs without
Docker or an administrator.

    python3 scripts/smb-server.py [corpus] [--port 4445] [--guest]

The default port is 4445 rather than 445, because binding 445 needs root and
macOS may already be using it.
"""

import argparse
import logging
import os
import sys

from impacket import smbserver
from impacket.ntlm import compute_lmhash, compute_nthash

SHARE = "Comics"
USER = "ada"
PASSWORD = "lovelace"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", nargs="?",
                        default=os.path.expanduser("~/StoryArcCorpus"))
    parser.add_argument("--port", type=int, default=4445)
    parser.add_argument("--guest", action="store_true",
                        help="accept anyone, for the guest-access path")
    arguments = parser.parse_args()

    if not os.path.isdir(arguments.corpus):
        print(f"no corpus at {arguments.corpus} — run: node scripts/corpus.mjs",
              file=sys.stderr)
        return 2

    logging.basicConfig(level=logging.INFO, format="%(message)s")

    server = smbserver.SimpleSMBServer(listenAddress="0.0.0.0",
                                       listenPort=arguments.port)
    server.addShare(SHARE, arguments.corpus, "the StoryArc fixture corpus")
    # SMB2 only. `network-share` requires the app to refuse SMB 1, and a server
    # that still offers it would let a broken refusal pass unnoticed.
    server.setSMB2Support(True)

    if arguments.guest:
        server.setSMBChallenge("")
    else:
        server.addCredential(USER, 0,
                             compute_lmhash(PASSWORD), compute_nthash(PASSWORD))

    print(f"smb mock: //localhost:{arguments.port}/{SHARE}")
    print(f"  serving {arguments.corpus}")
    print("  guest access" if arguments.guest else f"  {USER} / {PASSWORD}")
    server.start()
    return 0


if __name__ == "__main__":
    sys.exit(main())
