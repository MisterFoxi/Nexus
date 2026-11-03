"""Real WS/endpoint/evaluator and HUD endpoint, with controlled clock snapshots."""
import json
import unittest
import uuid
import test_workshop_split as t


class CookingWorkshopTests(unittest.TestCase):
    setUp = t.SplitTests.setUp
    bind = t.SplitTests.bind
    add = t.SplitTests.add
    here = t.SplitTests.here
    prepare = t.SplitTests.prepare
    submit = t.SplitTests.submit
    advance = t.SplitTests.advance
    restart = t.SplitTests.restart
    def cooking(self, heat=18, seconds=45.75, handler=0):
        for name, number in [('fab.thermal', 90), ('meta.heating_time', 91)]:
            self.w.storage[t.BENCH, 'tok:' + name] = str(number)
            self.w.storage[t.BENCH, 'tok:#' + str(number)] = name
        self.w.config += ['HeatAction=fab.thermal', 'DurationAction=meta.heating_time',
                          'DurationScale=1', 'DurationMax=3600', f'InspectHandler={handler}']
        self.w.gesture = f'OK|{seconds}|0|{heat}'
        self.core.call('loadConfig', []); self.w.drain(20000)

    def radio(self, verb, *parts, source=t.HUD, session=None, ticket=None):
        session = session or self.core.global_vars['gSession']
        ticket = ticket or t.h.Key(str(uuid.uuid4()))
        self.w.chat(source, -918275, '|'.join(map(str, ['MCW', verb, t.BENCH, session, ticket, *parts])))
        self.w.drain(20000)
        return ticket

    def inspections(self):
        return [a[3] for a in self.w.radio if '|INSPECT_REPLY|' in a[3]]

    def test_independent_values_reach_evaluator_and_survive_reset(self):
        self.cooking(); self.bind(); self.prepare(); self.submit()
        self.assertEqual(self.core.global_vars['gAction'], 'fab.grind=10^fab.thermal=18^meta.heating_time=46')
        self.assertEqual(json.loads(self.w.storage[t.BENCH, 'ws:inputs'])[1:], [45.75, 18])
        self.restart('core', 'Workshop.lsl')
        self.assertIn('fab.thermal=18^meta.heating_time=46', self.core.global_vars['gAction'])
        self.assertEqual(self.w.stock[t.SOURCE], [9, 0])

    def test_two_axis_law_requires_heat_and_duration_separately(self):
        self.cooking(heat=18, seconds=45.75)
        self.w.storage[t.BENCH, 'law:cutting_board:fixture:when'] = '14=15^10=11^90>=18^91>=40'
        self.bind(); self.prepare(); self.submit()
        self.assertEqual(self.core.global_vars['gPhase'], 'PRODUCT')
        self.assertEqual(self.w.stock[t.SOURCE], [9, 0])

    def test_duration_alone_cannot_satisfy_heat_condition(self):
        self.cooking(heat=3, seconds=100)
        self.w.storage[t.BENCH, 'law:cutting_board:fixture:when'] = '14=15^10=11^90>=18^91>=40'
        self.bind(); self.prepare(); self.submit()
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])
        self.assertEqual(self.w.physical, [])

    def test_heat_alone_cannot_satisfy_duration_condition(self):
        self.cooking(heat=25, seconds=2)
        self.w.storage[t.BENCH, 'law:cutting_board:fixture:when'] = '14=15^10=11^90>=18^91>=40'
        self.bind(); self.prepare(); self.submit()
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])
        self.assertEqual(self.w.physical, [])

    def test_duration_is_bounded_independently_from_legacy_grind(self):
        self.cooking(heat=7, seconds=10000)
        self.bind(); self.prepare(); self.submit()
        self.assertEqual(self.core.global_vars['gAction'], 'fab.grind=10^fab.thermal=7^meta.heating_time=3600')

    def test_missing_or_malformed_heat_never_acknowledges_or_consumes(self):
        self.cooking(); self.bind(); self.prepare()
        for extra in [[], ['31'], ['-1'], ['3.5'], ['x']]:
            self.radio('BEGIN', 'CONTAINER', '10', '0', *extra)
            self.assertEqual(self.core.global_vars['gPhase'], 'BOUND')
            self.assertEqual(self.w.stock[t.SOURCE], [9, 1])
            self.assertNotIn((t.BENCH, 'ws:inputs'), self.w.storage)

    def test_unknown_or_duplicate_input_axis_disables_configuration(self):
        self.cooking()
        self.w.config += ['DurationAction=missing.axis']
        self.core.call('loadConfig', []); self.w.drain(20000)
        self.assertFalse(self.core.global_vars['gConfigReady'])
        self.w.config[-1] = 'DurationAction=fab.thermal'
        self.core.call('loadConfig', []); self.w.drain(20000)
        self.assertFalse(self.core.global_vars['gConfigReady'])

    def test_hook_without_adapter_is_explicit_and_has_no_product_side_effect(self):
        self.cooking(); self.bind(); self.prepare()
        core = self.w.storage[t.BENCH, 'ws:core']
        self.radio('INSPECT', '12.5', '18')
        self.assertTrue(self.inspections()[-1].endswith('|NOT_IMPLEMENTED'))
        self.assertEqual(self.w.storage[t.BENCH, 'ws:core'], core)
        self.assertNotIn((t.BENCH, 'ws:eval:result'), self.w.storage)
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])

    def test_adapter_reply_is_correlated_authenticated_and_timeout_does_not_submit(self):
        self.cooking(handler=1); self.bind(); self.prepare()
        self.radio('INSPECT', '12.5', '18', source=t.SOURCE)
        self.assertEqual(self.inspections(), [])
        ticket = self.radio('INSPECT', '12.5', '18')
        self.assertTrue(any(a[2:4] == (970240, 'INPUTS|12.5|18') for a in self.w.replies))
        self.w.emit(t.BENCH, 970241, 'STATE|warm', t.RUN); self.w.drain(20000)
        self.assertEqual(self.inspections(), [])
        self.w.emit(t.BENCH, 970241, 'STATE|warm', ticket); self.w.drain(20000)
        self.assertTrue(self.inspections()[-1].endswith('|STATE%7Cwarm'))
        self.radio('INSPECT', '16', '18'); self.advance(15)
        self.assertTrue(self.inspections()[-1].endswith('|UNAVAILABLE'))
        self.assertEqual(self.core.global_vars['gPhase'], 'BOUND')
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])

    def test_late_adapter_reply_cannot_be_sent_to_a_different_session(self):
        self.cooking(handler=1); self.bind()
        ticket = self.radio('INSPECT', '12.5', '18')
        self.core.global_vars['gSession'] = t.h.Key(str(uuid.uuid4()))
        self.core.call('save', [])
        self.w.emit(t.BENCH, 970241, 'STATE|old', ticket); self.w.drain(20000)
        self.assertEqual(self.inspections(), [])


if __name__ == '__main__':
    unittest.main()
