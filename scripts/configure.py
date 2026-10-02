#!/usr/bin/env python3
"""Generate app configuration from upstream's template without evaluating input."""
import json
import os
import sys
from pathlib import Path
app = Path(sys.argv[1])
mode = sys.argv[2]
def env(key):
    return os.environ[key]
def quote(value):
    # Single quoted dotenv values keep dollar signs literal (including Compose).
    if "\n" in value or "\r" in value or "'" in value or "\\" in value:
        raise ValueError("Unsupported character in configuration value")
    return "'" + value + "'"
values = dict(APP_ENV='production', APP_DEBUG='false', APP_KEY=env('APP_KEY'),
    APP_URL='https://' + env('DOMAIN'), VITE_ECHO_ADDRESS='https://' + env('DOMAIN'),
    DB_HOST='mysql' if mode == 'docker' else '127.0.0.1', DB_DATABASE='unit3d',
    DB_USERNAME='unit3d', DB_PASSWORD=env('DB_PASSWORD'),
    REDIS_HOST='redis' if mode == 'docker' else '127.0.0.1', REDIS_PASSWORD=env('REDIS_PASSWORD'),
    DEFAULT_OWNER_NAME=env('OWNER_NAME'), DEFAULT_OWNER_EMAIL=env('OWNER_EMAIL'),
    DEFAULT_OWNER_PASSWORD=env('OWNER_PASSWORD'),
    MEILISEARCH_HOST='http://' + ('meilisearch' if mode == 'docker' else '127.0.0.1') + ':7700',
    MEILISEARCH_KEY=env('MEILISEARCH_KEY'), MAIL_MAILER='log', SESSION_SECURE_COOKIE='true',
    LOG_LEVEL='warning', SCOUT_DRIVER='meilisearch')
if os.environ.get('INSTALL_ANNOUNCE', 'false') == 'true':
    values.update(TRACKER_ENABLED='true', TRACKER_HOST='announce' if mode == 'docker' else '127.0.0.1',
                  TRACKER_PORT='6969', TRACKER_UNIX_SOCKET='null', TRACKER_KEY=env('TRACKER_KEY'))
    config_path = app/'config/announce.php'
    config = config_path.read_text()
    original = "'is_enabled' => false,"
    replacement = "'is_enabled' => env('TRACKER_ENABLED', false),"
    if original not in config:
        raise ValueError('External tracker configuration has changed upstream; review before enabling')
    config_path.write_text(config.replace(original, replacement, 1))
lines=[]
for line in (app/'.env.example').read_text().splitlines():
    key=line.split('=',1)[0]
    if key in values:
        value = values.pop(key)
        lines.append(key+'='+('null' if key == 'TRACKER_UNIX_SOCKET' else quote(value)))
    else:
        lines.append(line)
lines += [k+'='+('null' if k == 'TRACKER_UNIX_SOCKET' else quote(v)) for k,v in values.items()]
(app/'.env').write_text('\n'.join(lines)+'\n')
(app/'.env').chmod(0o640)
echo = dict(authHost='http://web' if mode == 'docker' else 'https://'+env('DOMAIN'),
    authEndpoint='/broadcasting/auth', clients=[], database='redis',
    databaseConfig={'redis': {'host': 'redis' if mode == 'docker' else '127.0.0.1',
        'port':6379, 'password':env('REDIS_PASSWORD'), 'db':3, 'keyPrefix':''}},
    devMode=False, host='0.0.0.0' if mode == 'docker' else '127.0.0.1', port=6001,
    protocol='http', socketio={}, apiOriginAllow={'allowCors':False})
(app/'laravel-echo-server.json').write_text(json.dumps(echo,indent=2)+'\n')
(app/'laravel-echo-server.json').chmod(0o640)
