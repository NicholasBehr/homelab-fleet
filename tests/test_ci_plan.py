"""Selection follows evaluated dependencies, not manually maintained file rules."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest


def load_source(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


planner = load_source('planner', Path(__file__).resolve().parents[1] / 'scripts/ci-plan')

class Selection(unittest.TestCase):
    def test_identical_outputs_select_none(self):
        plan = {'images': {'immich': 'a', 'home-assistant': 'b'}, 'checks': {'guard': 'c'}}
        self.assertEqual(planner.changed(plan, plan), {'images': [], 'checks': []})
    def test_service_change_does_not_build_other_service(self):
        old = {'images': {'immich': 'a', 'home-assistant': 'b'}, 'checks': {'guard': 'c'}}
        new = {'images': {'immich': 'new', 'home-assistant': 'b'}, 'checks': {'guard': 'c'}}
        self.assertEqual(planner.changed(new, old), {'images': ['immich'], 'checks': []})
    def test_shared_change_selects_affected_outputs(self):
        old = {'images': {'immich': 'a', 'home-assistant': 'b'}, 'checks': {'guard': 'c'}}
        new = {'images': {'immich': 'new-a', 'home-assistant': 'new-b'}, 'checks': {'guard': 'new-c'}}
        self.assertEqual(planner.changed(new, old), {'images': ['home-assistant', 'immich'], 'checks': ['guard']})
    def test_missing_or_old_schema_builds_all(self):
        new = {'images': {'immich': 'a'}, 'checks': {'guard': 'c'}}
        self.assertEqual(planner.changed(new, {}), {'images': ['immich'], 'checks': ['guard']})
    def test_new_output_selected_removed_output_not_built(self):
        old = {'images': {'old': 'a'}, 'checks': {}}
        new = {'images': {'new': 'b'}, 'checks': {}}
        self.assertEqual(planner.changed(new, old), {'images': ['new'], 'checks': []})

if __name__ == '__main__': unittest.main()
