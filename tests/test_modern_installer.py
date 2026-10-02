"""Non-destructive configuration and OS gate regression checks."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class InstallerTests(unittest.TestCase):
    def test_os_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            release = Path(directory) / 'os-release'
            for distro, version, ok in [('debian','13',True), ('ubuntu','24.04',True),
                ('ubuntu','26.04',True), ('ubuntu','22.04',False), ('debian','12',False),
                ('ubuntu','26.10',False), ('fedora','43',False)]:
                with self.subTest(distro=distro, version=version):
                    release.write_text(f'ID={distro}\nVERSION_ID={version}\n')
                    result = subprocess.run(['bash','-c','source "$1"; check_os',
                        'test',str(ROOT/'scripts/common.sh')],
                        env={**os.environ,'OS_RELEASE_FILE':str(release)}, capture_output=True)
                    self.assertEqual(result.returncode == 0, ok)

    def test_configuration(self):
        settings = dict(DOMAIN='tracker.example.com', OWNER_NAME='Jake',
            OWNER_EMAIL='jake@example.com', OWNER_PASSWORD='a'*48,
            DB_PASSWORD='b'*48, REDIS_PASSWORD='c'*48, MEILISEARCH_KEY='d'*64,
            APP_KEY='base64:ExampleKey')
        for mode in ('native','docker'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                app=Path(directory)
                (app/'.env.example').write_text('APP_ENV=prod\nDB_USERNAME=root\nDEFAULT_OWNER_PASSWORD=UNIT3D\nMAIL_MAILER=log\nTMDB_API_KEY=\n')
                subprocess.run(['python3',str(ROOT/'scripts/configure.py'),directory,mode],
                    env={**os.environ,**settings},check=True)
                config=(app/'.env').read_text()
                self.assertIn("DB_USERNAME='unit3d'",config)
                self.assertIn("APP_ENV='production'",config)
                self.assertIn("SESSION_SECURE_COOKIE='true'",config)
                self.assertNotIn('DEFAULT_OWNER_PASSWORD=UNIT3D',config)
                self.assertNotIn('TRACKER_ENABLED=',config)
                self.assertEqual((app/'.env').stat().st_mode & 0o777,0o640)
                echo=json.loads((app/'laravel-echo-server.json').read_text())
                self.assertEqual(echo['databaseConfig']['redis']['db'],3)
                self.assertEqual(echo['databaseConfig']['redis']['password'],settings['REDIS_PASSWORD'])
                self.assertEqual(echo['protocol'],'http')
                self.assertEqual(echo['databaseConfig']['redis']['host'], 'redis' if mode=='docker' else '127.0.0.1')

    def test_optional_announce_configuration(self):
        settings = dict(DOMAIN='tracker.example.com', OWNER_NAME='Jake',
            OWNER_EMAIL='jake@example.com', OWNER_PASSWORD='a'*48,
            DB_PASSWORD='b'*48, REDIS_PASSWORD='c'*48, MEILISEARCH_KEY='d'*64,
            APP_KEY='base64:ExampleKey', INSTALL_ANNOUNCE='true', TRACKER_KEY='e'*64)
        for mode in ('native','docker'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                app=Path(directory)/'app'
                tracker=Path(directory)/'announce'
                (app/'config').mkdir(parents=True)
                tracker.mkdir()
                (app/'.env.example').write_text('APP_ENV=prod\n')
                (app/'config/announce.php').write_text("<?php return ['external_tracker'=>['is_enabled' => false,]];")
                (tracker/'.env.example').write_text('DATABASE_URL=mysql://placeholder\nAPIKEY=CHANGE_ME\nUPLOAD_FACTOR=100\nDOWNLOAD_FACTOR=100\n')
                subprocess.run(['python3',str(ROOT/'scripts/configure.py'),str(app),mode],
                    env={**os.environ,**settings},check=True)
                subprocess.run(['python3',str(ROOT/'scripts/announce-configure.py'),str(tracker),mode],
                    env={**os.environ,**settings},check=True)
                config=(app/'.env').read_text()
                self.assertIn("TRACKER_ENABLED='true'", config)
                self.assertIn('TRACKER_UNIX_SOCKET=null\n', config)
                self.assertIn("TRACKER_KEY='"+settings['TRACKER_KEY']+"'",config)
                self.assertIn("env('TRACKER_ENABLED', false)",(app/'config/announce.php').read_text())
                tracker_config=(tracker/'.env').read_text()
                self.assertNotIn('CHANGE_ME',tracker_config)
                self.assertIn('APIKEY='+settings['TRACKER_KEY'],tracker_config)
                self.assertIn('REVERSE_PROXY_CLIENT_IP_HEADER_NAME=X-Real-IP',tracker_config)
                self.assertIn('DOWNLOAD_FACTOR=100',tracker_config)
                host='mysql' if mode=='docker' else '127.0.0.1'
                self.assertIn('DATABASE_URL=mysql://unit3d:'+settings['DB_PASSWORD']+'@'+host+':3306/unit3d',tracker_config)
                self.assertIn('LISTENING_IP_ADDRESS='+('0.0.0.0' if mode=='docker' else '127.0.0.1'),tracker_config)

    def test_announce_choice_rejects_invalid_settings(self):
        for value, ref in [('yes','v9.2.0'), ('true','unreviewed')]:
            result=subprocess.run(['bash','-c','source "$1"; select_announce','test',
                str(ROOT/'scripts/common.sh')],env={**os.environ,'INSTALL_ANNOUNCE':value,
                'UNIT3D_REF':ref},capture_output=True)
            self.assertNotEqual(result.returncode,0)

    def test_preinstalled_docker_warning_and_guards(self):
        for mode in ('native','docker'):
            for state, ok in [('empty', True), ('containers', False), ('unavailable', False), ('list_error', False)]:
                with self.subTest(mode=mode, state=state):
                    script = r"""
source "$1"
docker() {
  case "$1" in
    info) [[ $MOCK_STATE != unavailable ]] ;;
    ps) case "$MOCK_STATE" in containers) echo existing-container ;; list_error) return 1 ;; *) return 0 ;; esac ;;
  esac
}
check_preinstalled_docker "$2"
"""
                    result=subprocess.run(['bash','-c',script,'test',str(ROOT/'scripts/common.sh'),mode],
                        env={**os.environ,'MOCK_STATE':state},capture_output=True)
                    self.assertEqual(result.returncode == 0, ok)
                    self.assertIn(b'WARNING: Docker is already installed',result.stderr)
                    self.assertIn(b'you are on your own',result.stderr)

    def test_other_installed_stack_is_rejected_even_when_stopped(self):
        script = r"""
source "$1"
systemctl() { return 1; }
dpkg-query() {
  if [[ $3 == redis-server ]]; then echo 'install ok installed'; return 0; fi
  return 1
}
check_existing_server_software
"""
        result=subprocess.run(['bash','-c',script,'test',str(ROOT/'scripts/common.sh')],capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn(b'redis-server is installed',result.stderr)
        self.assertIn(b'Only Docker may be preinstalled',result.stderr)

    def test_bad_arguments_do_not_install(self):
        for script in ('native.sh','docker.sh'):
            result=subprocess.run(['bash',str(ROOT/'scripts'/script),'--unexpected'],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn(b'Only --check',result.stderr)

    def test_help(self):
        result=subprocess.run(['bash',str(ROOT/'install.sh'),'--help'],capture_output=True)
        self.assertEqual(result.returncode,0)
        self.assertIn(b'native|docker',result.stdout)

if __name__ == '__main__':
    unittest.main()
