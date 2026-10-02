#!/usr/bin/env python3
"""Generate Caddy's optional announce route from validated installer settings."""
import os
import sys
from pathlib import Path
Path(sys.argv[1]).write_text("""{
    email EMAIL
}
DOMAIN {
    @peerAnnounce path_regexp ^/announce/[a-fA-F0-9]{32}$
    handle @peerAnnounce {
        reverse_proxy announce:6969 {
            header_up X-Real-IP {remote_host}
        }
    }
    handle /announce/* {
        respond 404
    }
    handle {
        reverse_proxy web:80
    }
}
""".replace('EMAIL', os.environ['OWNER_EMAIL']).replace('DOMAIN', os.environ['DOMAIN']))
