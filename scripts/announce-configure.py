#!/usr/bin/env python3
"""Keep tracker defaults from its pinned upstream template; configure local transport."""
import os
import sys
from pathlib import Path
source = Path(sys.argv[1])
mode = sys.argv[2]
values = {
    'DATABASE_URL': 'mysql://unit3d:' + os.environ['DB_PASSWORD'] + '@' + ('mysql' if mode == 'docker' else '127.0.0.1') + ':3306/unit3d',
    'APIKEY': os.environ['TRACKER_KEY'],
    'LISTENING_IP_ADDRESS': '0.0.0.0' if mode == 'docker' else '127.0.0.1',
    'LISTENING_PORT': '6969',
    'REVERSE_PROXY_CLIENT_IP_HEADER_NAME': 'X-Real-IP',
}
lines = []
for line in (source/'.env.example').read_text().splitlines():
    key = line.split('=', 1)[0].strip()
    if key in values:
        lines.append(key + '=' + values.pop(key))
    else:
        lines.append(line)
lines += [key + '=' + value for key, value in values.items()]
(source/'.env').write_text('\n'.join(lines) + '\n')
(source/'.env').chmod(0o640)
