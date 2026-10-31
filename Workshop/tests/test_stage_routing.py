"""Stage/taxonomy collision from the supplied dump; actual LSL ASTs, mocked SL."""
import json
import unittest
import test_workshop_split as t


def dump_rules(w):
    # Relevant records from the 00:56 dump, including plant in mint's ancestry.
    for obj, key in list(w.storage):
        if obj == t.BENCH and key.startswith(('tok:', 'tax:', 'law:')):
            del w.storage[obj, key]
    tokens = {'meta.taxonomy': 14, 'meta.stage': 10, 'meta.organ': 56,
              'mint': 16, 'leaf_plant': 15, 'plant': 23, 'cuttable': 27,
              'leaf': 11, 'root': 17, 'chopped': 28, 'minced': 29, 'powder': 12,
              'kanda': 57, 'flower': 63, 'grindable': 69, 'fab.grind': 22,
              'act.thermal': 3, 'act.fluidifying': 4}
    for name, number in tokens.items():
        w.storage[t.BENCH, 'tok:' + name] = str(number)
        w.storage[t.BENCH, 'tok:#' + str(number)] = name
    w.storage[t.BENCH, 'tax:16:toks'] = '16^15^23^26^27'
    w.storage[t.BENCH, 'tax:57:toks'] = '57^16^15^23^26^27'
    w.storage[t.BENCH, 'tax:57:organs'] = '11^17^63'
    w.storage[t.BENCH, 'tax:57:organ:11:tags'] = '68^69^70'
    rules = [('harvest', '10=23^14=27', 0, 0, 'give'),
             ('harvest_leaf', '10=23^14=27', 2, 1, 'give=11'),
             ('harvest_root', '10=23^14=27', 2, 2, 'give=17'),
             ('chop', '14=15^10=11', 0, 3, '10=28^qty*5'),
             ('mince', '14=15^10=28', 0, 5, '10=29')]
    for name, when, verdict, seq, action in rules:
        for field, value in [('when', when), ('verdict', verdict), ('seq', seq), ('do', action)]:
            w.storage[t.BENCH, f'law:cutting_board:{name}:{field}'] = str(value)


class StageRoutingTests(unittest.TestCase):
    def setUp(self):
        self.w = t.World()
        dump_rules(self.w)
        self.script = t.Script(self.w, 'Workshop_Eval.lsl', t.BENCH)
        self.w.drain(20000)

    def group(self, stage='leaf', taxonomy='mint', organ='', count=1):
        return ['Kanda leaf', count, taxonomy, stage,
                'act.thermal=-6^act.fluidifying=5^org.taste=4', 604800, 996, organ]

    def evaluate(self, group):
        self.w.storage[t.BENCH, 'ws:input'] = json.dumps([t.RUN, 'READY', 1, 1, 0, ''])
        self.w.storage[t.BENCH, 'ws:in:group:0'] = '|'.join(map(str, group))
        self.script.call('link_message', [1, 970202, '', t.RUN])
        self.w.drain(20000)
        return json.loads(self.w.storage[t.BENCH, 'ws:eval:result'])[1]

    def test_leaf_without_mesh_produces_container_dna_instead_of_give(self):
        fields = self.evaluate(self.group()).split('|')
        self.assertEqual(fields[0], '1')
        self.assertEqual(fields[7], 'chopped')  # Existing loaded chop law unchanged.
        self.assertEqual(fields[3], '5')
        self.assertEqual(self.script.global_vars['rLid'], 'chop')

    def test_chopped_leaf_uses_mince_instead_of_harvest_or_chop(self):
        fields = self.evaluate(self.group(stage='chopped', count=5)).split('|')
        self.assertEqual(fields[0], '1')
        self.assertEqual(fields[7], 'minced')
        self.assertEqual(fields[3], '5')
        self.assertEqual(self.script.global_vars['rLid'], 'mince')

    def test_whole_plant_keeps_legacy_mesh_delivery(self):
        self.assertEqual(self.evaluate(self.group(stage='plant')), '2')

    def test_whole_species_keeps_multi_organ_mesh_delivery(self):
        self.assertEqual(self.evaluate(self.group(stage='plant', taxonomy='kanda')), '2|leaf^root')

    def test_organ_leaf_and_its_tags_do_not_change_stage_or_taxonomy(self):
        self.script.call('buildAggregate', [self.group(stage='powder', taxonomy='kanda', organ='leaf')])
        for condition, expected in [('10=11', 0), ('10=23', 0), ('10=12', 1),
                                    ('14=11', 0), ('14=23', 1), ('56=11', 1), ('56=69', 1), ('23', 1)]:
            with self.subTest(condition=condition):
                self.assertEqual(self.script.call('evalWhen', [condition]), expected)

    def test_stage_leaf_does_not_invent_an_organ(self):
        self.script.call('buildAggregate', [self.group()])
        self.assertEqual(self.script.call('evalWhen', ['10=11']), 1)
        self.assertEqual(self.script.call('evalWhen', ['56=11']), 0)

    def test_new_aggregate_does_not_keep_previous_plant_stage(self):
        self.script.call('buildAggregate', [self.group(stage='plant')])
        self.script.call('buildAggregate', [self.group()])
        self.assertEqual(self.script.call('evalWhen', ['10=23']), 0)
        self.assertEqual(self.script.call('evalWhen', ['10=11']), 1)


class PhysicalRoutingTests(unittest.TestCase):
    def setUp(self):
        self.base = t.SplitTests()
        self.base.setUp()
        dump_rules(self.base.w)
        self.base.bind()

    def submit(self, stage, mesh=''):
        b = self.base
        here = (f'HERE|{t.SOURCE}|Kanda leaf|3|1|604800|mint|{stage}|'
                f'act.thermal=-6^act.fluidifying=5|5|996|{mesh}|')
        b.w.emit(t.HUD, 918300, here, t.SOURCE); b.w.drain(20000)
        b.selected.call('basketAction', ['CRAFT_STARTED', t.RUN]); b.w.drain(20000)
        b.submit(); b.advance(1)

    def test_leaf_uses_config_to_selected_recipient_and_closes_stock(self):
        b = self.base
        self.submit('leaf')
        self.assertEqual(b.output.global_vars['gPhase'], 'WAIT_CONTAINER')
        self.assertEqual(b.w.physical, [])
        b.w.containers[t.CONTAINER] = 0
        b.collect()
        self.assertEqual(len(b.w.physical), 1)
        self.assertTrue(b.w.physical[0].startswith(f'CONFIG|{t.CONTAINER}|'))
        self.assertEqual(b.w.stock[t.SOURCE], [9, 0])
        self.assertEqual(b.link.global_vars['gPhase'], 'IDLE')

    def test_plant_still_uses_give_without_container_config(self):
        b = self.base
        self.submit('plant', 'KandaLeafMesh')
        self.assertEqual(b.w.physical, [f'GIVE|{t.SOURCE}'])
        self.assertEqual(b.w.stock[t.SOURCE], [9, 0])


if __name__ == '__main__':
    unittest.main(verbosity=2)
