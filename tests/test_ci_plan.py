"""Selection follows evaluated dependencies, not manually maintained file rules."""
import importlib.machinery
from pathlib import Path
import unittest

planner = importlib.machinery.SourceFileLoader('planner', str(Path(__file__).resolve().parents[1]/'scripts/ci-plan')).load_module()

class Selection(unittest.TestCase):
    def test_identical_outputs_select_none(self):
        plan = {'images': {'immich': 'a', 'other': 'b'}, 'checks': {'guard': 'c'}}
        self.assertEqual(planner.changed(plan, plan), {'images': [], 'checks': []})
    def test_service_change_does_not_build_other_service(self):
        old = {'images': {'immich': 'a', 'other': 'b'}, 'checks': {'guard': 'c'}}
        new = {'images': {'immich': 'new', 'other': 'b'}, 'checks': {'guard': 'c'}}
        self.assertEqual(planner.changed(new, old), {'images': ['immich'], 'checks': []})
    def test_shared_change_selects_affected_outputs(self):
        old = {'images': {'immich': 'a', 'other': 'b'}, 'checks': {'guard': 'c'}}
        new = {'images': {'immich': 'new-a', 'other': 'new-b'}, 'checks': {'guard': 'new-c'}}
        self.assertEqual(planner.changed(new, old), {'images': ['immich', 'other'], 'checks': ['guard']})
    def test_missing_or_old_schema_builds_all(self):
        new = {'images': {'immich': 'a'}, 'checks': {'guard': 'c'}}
        self.assertEqual(planner.changed(new, {}), {'images': ['immich'], 'checks': ['guard']})
    def test_new_output_selected_removed_output_not_built(self):
        old = {'images': {'old': 'a'}, 'checks': {}}
        new = {'images': {'new': 'b'}, 'checks': {}}
        self.assertEqual(planner.changed(new, old), {'images': ['new'], 'checks': []})

if __name__ == '__main__': unittest.main()
