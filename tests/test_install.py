"""Exercise the installer in isolated directories; no real user config is edited."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='prompt-review-install-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.skills = self.base / 'skills with spaces'
        self.config = self.base / 'codex config'
        self.target = self.skills / 'prompt-review-gate'

    def install(self, *args, source=True, env=None, success=True):
        command = ['bash', str(ROOT / 'install.sh'), '--skills-dir', str(self.skills),
                   '--codex-dir', str(self.config)]
        if source:
            command += ['--source-dir', str(ROOT)]
        result = subprocess.run(command + list(args), text=True, capture_output=True,
                                env=env, timeout=30)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def seed(self, text='old skill'):
        self.target.mkdir(parents=True)
        (self.target / 'SKILL.md').write_text(text)

    def test_fresh_install_does_not_enable_defaults(self):
        self.install()
        self.assertEqual((self.target / 'SKILL.md').read_bytes(), (ROOT / 'SKILL.md').read_bytes())
        self.assertTrue((self.target / 'agents/openai.yaml').is_file())
        self.assertFalse((self.config / 'AGENTS.md').exists())

    def test_upgrade_preserves_original_in_backup(self):
        self.seed()
        self.install()
        saved = list((self.config / 'backups').rglob('skill/SKILL.md'))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_text(), 'old skill')

    def test_defaults_preserve_unrelated_rules_and_are_idempotent(self):
        self.config.mkdir()
        agents = self.config / 'AGENTS.md'
        original = 'Existing instructions with no final newline'
        agents.write_text(original)
        self.install('--enable-default')
        once = agents.read_bytes()
        self.assertTrue(once.startswith(original.encode()))
        self.assertEqual(once.count(b'<!-- prompt-review-gate:begin -->'), 1)
        saved = list((self.config / 'backups').rglob('AGENTS.md'))
        self.assertEqual(saved[0].read_text(), original)
        self.install('--enable-default')
        self.assertEqual(once, agents.read_bytes())

    def test_nonempty_override_is_updated_instead_of_base(self):
        self.config.mkdir()
        agents = self.config / 'AGENTS.md'
        override = self.config / 'AGENTS.override.md'
        agents.write_text('base rule')
        override.write_text('override rule')
        self.install('--enable-default')
        self.assertEqual(agents.read_text(), 'base rule')
        self.assertTrue(override.read_text().startswith('override rule'))
        self.assertIn('prompt-review-gate:begin', override.read_text())

    def test_discovery_symlink_is_preserved_and_real_skill_is_backed_up(self):
        self.skills.mkdir()
        real = self.base / 'real old skill'
        real.mkdir()
        (real / 'SKILL.md').write_text('linked original')
        self.target.symlink_to(Path('..') / real.name, target_is_directory=True)
        self.install()
        self.assertTrue(self.target.is_symlink())
        self.assertEqual((real / 'SKILL.md').read_bytes(), (ROOT / 'SKILL.md').read_bytes())
        saved = list((self.config / 'backups').rglob('skill/SKILL.md'))
        self.assertEqual(saved[0].read_text(), 'linked original')

    def test_invalid_payload_does_not_change_existing_install(self):
        self.seed()
        bad = self.base / 'invalid payload'
        (bad / 'agents').mkdir(parents=True)
        (bad / 'SKILL.md').write_text('<html>error</html>')
        (bad / 'agents/openai.yaml').write_text('interface: {}')
        self.install('--source-dir', str(bad), source=False, success=False)
        self.assertEqual((self.target / 'SKILL.md').read_text(), 'old skill')

    def test_broken_managed_rule_stops_before_changing_skill(self):
        self.seed()
        self.config.mkdir()
        agents = self.config / 'AGENTS.md'
        original = '<!-- prompt-review-gate:begin -->\nunfinished'
        agents.write_text(original)
        self.install('--enable-default', success=False)
        self.assertEqual(agents.read_text(), original)
        self.assertEqual((self.target / 'SKILL.md').read_text(), 'old skill')

    def test_download_failure_does_not_change_existing_install(self):
        self.seed()
        fake_bin = self.base / 'fake-bin'
        fake_bin.mkdir()
        curl = fake_bin / 'curl'
        curl.write_text('#!/bin/sh\nexit 22\n')
        curl.chmod(0o755)
        env = dict(os.environ)
        env['PATH'] = str(fake_bin) + os.pathsep + env['PATH']
        self.install(source=False, env=env, success=False)
        self.assertEqual((self.target / 'SKILL.md').read_text(), 'old skill')

    def test_empty_override_does_not_hide_base_rule(self):
        self.config.mkdir()
        (self.config / 'AGENTS.override.md').write_text('')
        self.install('--enable-default')
        self.assertIn('prompt-review-gate:begin', (self.config / 'AGENTS.md').read_text())
        self.assertEqual((self.config / 'AGENTS.override.md').read_text(), '')


if __name__ == '__main__':
    unittest.main()
