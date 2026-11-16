import importlib.util
from pathlib import Path
import io
import json
import copy
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('nexus_compiler', ROOT / 'compiler.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class Observations(unittest.TestCase):
    def setUp(self):
        compiler.errors.clear()
        compiler.warnings.clear()
        axis = compiler.Axis('fab.thermal', 0, 5, 200, 'C', 0, 30)
        axis.zone_int['boiling'] = (14, 24)
        self.dims = {'fab.thermal': axis}

    def parse(self, source):
        with patch('builtins.open', return_value=io.StringIO('@cauldron\n' + source)):
            return compiler.load_laws('laws.src', self.dims, {'cauldron': set()})

    def emit(self, laws):
        rows = []
        compiler.emit(self.dims, None, None, {}, {'groups': {}}, laws, {}, {}, rows)
        return dict(row.split(' = ', 1) for row in rows if ' = ' in row)

    def test_observation_is_safe_for_existing_evaluator(self):
        laws = self.parse('law boiling\n when fab.thermal is boiling\n observe\n describe "The mixture is boiling."\n')
        self.assertEqual(compiler.errors, [])
        rows = self.emit(laws)
        self.assertEqual(rows['law:cauldron:boiling:observe_when'], '0~14~24')
        self.assertEqual(rows['law:cauldron:boiling:description'], 'The mixture is boiling.')
        self.assertEqual(rows['law:observations:count'], '1')
        self.assertEqual(rows['law:observations:0'], 'cauldron|boiling')
        for suffix in ('when', 'verdict', 'do', 'cap'):
            self.assertNotIn('law:cauldron:boiling:' + suffix, rows)
        self.assertFalse(any(key.startswith('idx:') for key in rows))

    def test_multiple_observations_do_not_shift_recipe_order(self):
        laws = self.parse('law first\n react\n keep\n'
                          'law view_a\n observe\n describe "A"\n'
                          'law second\n react\n describe "Result"\n'
                          'law view_b\n observe\n describe "B"\n')
        self.assertEqual(compiler.errors, [])
        rows = self.emit(laws)
        self.assertEqual(rows['law:cauldron:first:seq'], '0')
        self.assertEqual(rows['law:cauldron:second:seq'], '1')
        self.assertEqual(rows['law:cauldron:view_a:observe_seq'], '0')
        self.assertEqual(rows['law:cauldron:view_b:observe_seq'], '1')
        self.assertEqual(rows['law:cauldron:second:description'], 'Result')
        self.assertEqual(rows['law:cauldron:view_a:observe_when'], '*')
        self.assertEqual(rows['law:observations:0'], 'cauldron|view_a')
        self.assertEqual(rows['law:observations:1'], 'cauldron|view_b')

    def test_quoted_text_preserves_hash_quotes_and_unicode(self):
        text = 'The aroma #1: "caf\u00e9" = strong.'
        laws = self.parse('law view\n observe\n DESCRIBE\t' + json.dumps(text, ensure_ascii=False) + ' # comment\n')
        self.assertEqual(compiler.errors, [])
        self.assertEqual(laws[0].description, text)

    def test_observation_requires_text(self):
        self.parse('law view\n observe\n')
        self.assertTrue(any('describe is required' in error for error in compiler.errors))

    def test_observations_cannot_transform(self):
        for action in ('scale eff x0.5', 'keep', 'cap 10'):
            with self.subTest(action=action):
                compiler.errors.clear()
                self.parse('law view\n observe\n describe "View"\n ' + action + '\n')
                self.assertTrue(any('forbidden' in error for error in compiler.errors))

    def test_invalid_descriptions_are_rejected(self):
        for text in ('unquoted text', '""', '"   "', '"line\\nline"', '"View" extra', '"\\ud800"'):
            with self.subTest(text=text):
                compiler.errors.clear()
                self.parse('law view\n observe\n describe ' + text + '\n')
                self.assertTrue(any('invalid describe' in error for error in compiler.errors))

    def test_duplicate_names_descriptions_and_verdicts_are_rejected(self):
        for source in ('law view\n observe\n describe "A"\n describe "B"\n',
                       'law view\n observe\n react\n describe "A"\n',
                       'law view\n react\n law view\n observe\n describe "A"\n'):
            compiler.errors.clear()
            self.parse(source)
            self.assertTrue(compiler.errors)

    def test_real_world_preserves_existing_recipe_records(self):
        registry = compiler.IdRegistry(ROOT / 'ids.lock')
        dims, stations, tax, organ, domains, aliases = compiler.load_vocab(ROOT / 'axes.src', registry)
        for dimension, values in compiler.scan_set_targets(ROOT / 'laws.src').items():
            for value in sorted(values):
                if dims[dimension].kind == 'cat' and value not in dims[dimension].vals:
                    dims[dimension].vals[value] = registry.id(value)
        nodes, tree = compiler.load_tree(ROOT / 'taxonomy.src', registry, dims, tax, organ, set())
        laws = compiler.load_laws(ROOT / 'laws.src', dims, stations)
        self.assertEqual(compiler.errors, [])
        rows = []
        compiler.emit(dims, tax, organ, nodes, tree, laws, aliases, stations, rows)
        actual = dict(row.split(' = ', 1) for row in rows if ' = ' in row)
        legacy = copy.deepcopy([law for law in laws if law.verdict != 'observe'])
        for law in legacy:
            law.description = None
        old_rows = []
        compiler.emit(dims, tax, organ, nodes, tree, legacy, aliases, stations, old_rows)
        baseline = dict(row.split(' = ', 1) for row in old_rows
                        if ' = ' in row and not row.startswith('law:observations:'))
        filtered = {key: value for key, value in actual.items()
                    if not key.endswith((':description', ':observe_when', ':observe_seq'))
                    and not key.startswith('law:observations:')}
        self.assertEqual(filtered, baseline)
        self.assertTrue(any(key.endswith(':observe_when') for key in actual))
        self.assertEqual(registry.map, compiler.IdRegistry(ROOT / 'ids.lock').map)


if __name__ == '__main__':
    unittest.main()
