"""Execute the actual evaluator AST; consultation never performs a craft."""
import copy
import unittest
from urllib.parse import unquote
import test_workshop_split as t


class ObservingScript(t.Script):
    def builtin(self, name, args):
        if name == 'llFrand':
            self.world.random_draws += 1
        return super().builtin(name, args)


class ObservationTests(unittest.TestCase):
    def setUp(self):
        self.w = t.World()
        self.w.random_draws = 0
        self.e = ObservingScript(self.w, 'Workshop_Eval.lsl', t.BENCH)
        self.w.drain(20000)
        self.w.storage[t.BENCH, 'tok:fab.thermal'] = '90'
        self.w.storage[t.BENCH, 'tok:org.smell'] = '91'
        self.w.storage[t.BENCH, 'law:observations:count'] = '0'
        self.rows = 'Mint|1|mint|leaf|org.smell=5|86400|950|leaf'

    def observation(self, index, name, condition, text, genre='cutting_board'):
        storage = self.w.storage
        storage[t.BENCH, 'law:observations:' + str(index)] = genre + '|' + name
        storage[t.BENCH, 'law:observations:count'] = str(index + 1)
        base = 'law:' + genre + ':' + name
        storage[t.BENCH, base + ':observe_when'] = condition
        storage[t.BENCH, base + ':description'] = text

    def consult(self, action='fab.thermal=12', rows=None):
        self.w.emit(t.BENCH, 970204, action + '\n\n' + (self.rows if rows is None else rows), t.RUN)
        self.w.drain(20000)
        replies = [reply[3] for reply in self.w.replies if reply[2] == 970205]
        return unquote(replies[-1])

    def test_matching_observations_accumulate_in_source_order(self):
        self.observation(0, 'z_simmer', '90~10~13', 'The mixture is gently simmering.')
        self.observation(1, 'a_putrid', '91>=3', 'It gives off a putrid smell.')
        self.assertEqual(self.consult(), 'OBSERVATIONS|The mixture is gently simmering. It gives off a putrid smell.')

    def test_specific_rule_does_not_replace_general_observation(self):
        self.observation(0, 'general', '90>=10', 'Warm.')
        self.observation(1, 'specific', '90>=10^91>=3', 'Warm and putrid.')
        self.assertEqual(self.consult(), 'OBSERVATIONS|Warm. Warm and putrid.')
        self.assertEqual(self.consult(action='fab.thermal=2'), 'NO_OBSERVATIONS')

    def test_all_conditions_must_match_and_other_genres_are_ignored(self):
        self.observation(0, 'wrong_heat', '90>=20^91>=3', 'Too hot.')
        self.observation(1, 'other', '*', 'Other station.', genre='mortar')
        self.observation(2, 'valid', '90<=13^91>=3', 'Simmering and putrid.')
        self.assertEqual(self.consult(), 'OBSERVATIONS|Simmering and putrid.')

    def test_consultation_preserves_stocks_state_result_cache_and_randomness(self):
        self.observation(0, 'simmer', '90>=10', 'Warm.')
        self.w.storage[t.BENCH, 'ws:eval:result'] = '["previous","cached"]'
        storage = copy.deepcopy(self.w.storage)
        stocks = copy.deepcopy(self.w.stock)
        self.e.global_vars['FLUX_ABS'] = 3
        self.e.global_vars['N_MAX'] = 1
        self.e.global_vars['BATCH_MULT'] = [950, 1050]
        first = self.consult()
        self.assertEqual(self.consult(), first)
        self.assertEqual(self.w.random_draws, 0)
        self.assertEqual(self.w.storage, storage)
        self.assertEqual(self.w.stock, stocks)
        self.assertEqual(self.w.physical, [])
        self.assertFalse(self.e.global_vars['gObserving'])
        self.assertEqual(self.e.global_vars['gAxId'], [])

    def test_inert_axes_and_identity_dimensions_keep_existing_semantics(self):
        self.observation(0, 'wrong_stage', '10=23', 'Whole plant.')
        self.observation(1, 'leaf', '10=11', 'Leaves.')
        self.observation(2, 'heat', '90>=1', 'Warm.')
        self.w.storage[t.BENCH, 'tax:16:inert'] = '90'
        self.assertEqual(self.consult(), 'OBSERVATIONS|Leaves.')

    def test_always_observation_survives_loader_empty_value_convention(self):
        self.observation(0, 'always', '*', 'Visible material.')
        self.assertEqual(self.consult(), 'OBSERVATIONS|Visible material.')

    def test_missing_numeric_axis_does_not_match_zero_but_explicit_zero_does(self):
        for condition in ('22~0~2','22<=0','22>=0'):
            with self.subTest(condition=condition):
                self.observation(0,'light',condition,'The leaves are whole.')
                self.assertEqual(self.consult(action=''),'NO_OBSERVATIONS')
                self.assertEqual(self.consult(action='fab.grind=0'),'OBSERVATIONS|The leaves are whole.')

    def test_missing_numeric_axis_keeps_legacy_recipe_semantics(self):
        self.w.storage[t.BENCH,'law:cutting_board:fixture:when']='14=15^10=11^22<=0'
        self.w.emit(t.BENCH,970200,'\n\n'+self.rows,t.RUN)
        self.w.drain(20000)
        result=[reply[3] for reply in self.w.replies if reply[2]==970201][-1]
        self.assertTrue(result.startswith('1|'),result)
        self.assertIn('|chopped|',result)

    def test_missing_or_incomplete_data_returns_an_error(self):
        del self.w.storage[t.BENCH, 'law:observations:count']
        self.assertTrue(self.consult().startswith('ERROR|Observation data not loaded.'))
        self.w.storage[t.BENCH, 'law:observations:count'] = '1'
        self.assertTrue(self.consult().startswith('ERROR|Incomplete observation index.'))
        self.assertFalse(self.e.global_vars['gObserving'])
        self.observation(0, 'missing', '90>=1', 'Warm.')
        del self.w.storage[t.BENCH, 'law:cutting_board:missing:observe_when']
        self.assertTrue(self.consult().startswith('ERROR|Missing observation conditions.'))

    def test_invalid_snapshot_is_rejected_and_later_consultation_still_works(self):
        self.observation(0, 'always', '*', 'Visible.')
        for rows in ('', 'Mint|1|mint|leaf||86400|950', 'Mint|0|mint|leaf||86400|950|leaf'):
            with self.subTest(rows=rows):
                self.assertTrue(self.consult(rows=rows).startswith('ERROR|Invalid observation snapshot.'))
        self.assertEqual(self.consult(), 'OBSERVATIONS|Visible.')

    def test_active_craft_evaluation_cannot_be_interrupted(self):
        self.e.global_vars['gStreamRun'] = t.RUN
        self.e.global_vars['gAxId'] = [5]
        self.e.global_vars['gAxVal'] = [42]
        self.assertTrue(self.consult().startswith('ERROR|Evaluator busy'))
        self.assertEqual(self.e.global_vars['gAxVal'], [42])

    def test_oversized_text_returns_explicit_error_without_partial_description(self):
        self.observation(0, 'long', '*', 'x' * 4100)
        self.assertTrue(self.consult().startswith('ERROR|Observation text exceeds'))

    def test_reaction_output_is_unchanged_after_consultation(self):
        self.observation(0, 'always', '*', 'Visible.')
        self.e.global_vars['FLUX_ABS'] = 2
        self.consult()
        self.w.emit(t.BENCH, 970200, '\n\n' + self.rows, t.RUN)
        self.w.drain(20000)
        after = [reply[3] for reply in self.w.replies if reply[2] == 970201][-1]
        other = t.World()
        other_e = t.Script(other, 'Workshop_Eval.lsl', t.BENCH)
        other.drain(20000)
        other_e.global_vars['FLUX_ABS'] = 2
        other.emit(t.BENCH, 970200, '\n\n' + self.rows, t.RUN)
        other.drain(20000)
        before = [reply[3] for reply in other.replies if reply[2] == 970201][-1]
        self.assertEqual(after, before)


if __name__ == '__main__':
    unittest.main()
