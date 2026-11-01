"""Prevent private working files from returning to the published source tree."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

class PublicBoundaryTests(unittest.TestCase):
    def check_tree(self, names):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'tools/release/check_package.py'
            script.parent.mkdir(parents=True)
            shutil.copy2(Path(__file__).with_name('check_package.py'), script)
            shutil.copy2(Path(__file__).with_name('public_examples.txt'), script.with_name('public_examples.txt'))
            (root / 'README.md').write_text('# Library\n')
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('local working content\n')
            return subprocess.run([sys.executable, str(script)], capture_output=True, text=True)

    def test_source_and_teaching_material_are_allowed(self):
        self.assertEqual(self.check_tree(['src/control.jl', 'docs/src/concepts.md', 'examples/release_smoke.jl']).returncode, 0)

    def test_private_working_files_are_rejected(self):
        for name in ['ARCHITECTURE.md', 'ROADMAP.md', 'AGENTS.md', 'RELEASE_NOTES_UNRELEASED.md',
                     'docs/src/research.md', 'docs/src/milestones.md', 'notes/open.md',
                     'Volt_VAR_Research.docx', 'controller_agenda.txt', 'open_discussion.md',
                     'discussions/controller.md', 'experiments/pilot.jl',
                     'docs/src/assets/validation/catalog.json']:
            with self.subTest(name=name):
                result = self.check_tree([name])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('private working material', result.stdout)

    def test_unapproved_campaign_driver_is_rejected(self):
        result = self.check_tree(['examples/private_campaign.jl'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unapproved public example', result.stdout)

    def test_generated_study_outputs_are_rejected(self):
        for name in ['artifacts/report.json', 'outputs/result.json']:
            with self.subTest(name=name):
                self.assertNotEqual(self.check_tree([name]).returncode, 0)

if __name__ == '__main__':
    unittest.main()
