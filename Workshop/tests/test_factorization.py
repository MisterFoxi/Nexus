"""Real LSL modules: startup ordering, single-writer state, and async mapping failures."""
import json
import unittest
import uuid
import test_workshop_split as t


class FactorizationTests(unittest.TestCase):
    setUp = t.SplitTests.setUp
    bind = t.SplitTests.bind
    add = t.SplitTests.add
    here = t.SplitTests.here
    prepare = t.SplitTests.prepare
    submit = t.SplitTests.submit
    advance = t.SplitTests.advance
    restart = t.SplitTests.restart

    def begin(self, request=None, seconds='4.75'):
        request = request or t.h.Key(str(uuid.uuid4()))
        wire = f'MCW|BEGIN|{t.BENCH}|{self.core.global_vars["gSession"]}|{request}|CONTAINER|{seconds}|0'
        self.w.chat(t.HUD, -918275, wire); self.w.drain(20000)
        return request, wire

    def begin_acks(self):
        return [wire for _, _, _, wire in self.w.radio if wire.startswith('MCW|ACK|') and wire.endswith('|BEGIN')]

    def test_missing_configuration_module_blocks_association(self):
        self.w.scripts.remove(self.config)
        self.restart('core', 'Workshop.lsl')
        self.core.call('touch_start', [1]); self.w.drain(20000)
        self.assertFalse(self.core.global_vars['gConfigReady'])
        self.assertEqual(self.core.global_vars['gPhase'], 'FREE')
        self.assertEqual(self.link.global_vars['gSession'], t.h.NULL)

    def test_modules_can_start_before_the_coordinator(self):
        world = t.World()
        t.Script(world, 'Workshop_Config.lsl', t.BENCH)
        t.Script(world, 'Workshop_Interface.lsl', t.BENCH)
        core = t.Script(world, 'Workshop.lsl', t.BENCH)
        for name in ['Workshop_HUD.lsl', 'Workshop_Eval.lsl', 'Workshop_Output.lsl', 'Workshop_Storage.lsl']:
            t.Script(world, name, t.BENCH)
        world.drain(20000)
        self.assertEqual(core.global_vars['gReady'], 31)
        self.assertTrue(core.global_vars['gConfigReady'])

    def test_missing_interface_blocks_association_until_it_announces_ready(self):
        self.w.scripts.remove(self.interface)
        self.restart('core', 'Workshop.lsl')
        self.core.call('touch_start', [1]); self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'], 'FREE')
        self.assertEqual(self.core.global_vars['gReady'], 15)
        self.interface = t.Script(self.w, 'Workshop_Interface.lsl', t.BENCH)
        self.w.drain(20000); self.bind()

    def test_config_restart_recovers_without_changing_pending_product_or_stock(self):
        self.bind(); self.prepare(); self.submit()
        product = self.w.storage[t.BENCH, 'ws:output']
        run = self.core.global_vars['gRun']
        stock = list(self.w.stock[t.SOURCE])
        self.restart('config', 'Workshop_Config.lsl')
        self.assertTrue(self.core.global_vars['gConfigReady'])
        self.assertEqual(self.core.global_vars['gRun'], run)
        self.assertEqual(self.w.storage[t.BENCH, 'ws:output'], product)
        self.assertEqual(self.w.stock[t.SOURCE], stock)
        self.assertEqual(self.w.physical, [])

    def test_stale_configuration_reply_cannot_publish_over_a_new_load(self):
        self.w.pause_codes.add(970251)
        self.core.call('loadConfig', []); self.w.drain(20000)
        old = self.core.global_vars['gConfigTicket']
        self.core.call('loadConfig', []); self.w.drain(20000)
        current = self.core.global_vars['gConfigTicket']
        snapshot = self.config.call('snapshot', [])
        self.w.emit(t.BENCH, 970251, snapshot, old); self.w.drain(20000)
        self.assertFalse(self.core.global_vars['gConfigReady'])
        self.assertEqual(self.core.global_vars['gConfigTicket'], current)
        self.w.emit(t.BENCH, 970251, snapshot, current); self.w.drain(20000)
        self.assertTrue(self.core.global_vars['gConfigReady'])

    def test_only_the_correlated_mapping_reply_can_begin_and_ack(self):
        self.bind(); self.prepare(); self.w.pause_codes.add(970255)
        first, wire = self.begin()
        second, _ = self.begin()
        self.assertEqual(self.core.global_vars['gPendingRun'], first)
        self.assertEqual(self.begin_acks(), [])
        payload = json.dumps(['CONTAINER', 4.75, -1, 'fab.grind=5'])
        self.w.emit(t.BENCH, 970255, payload, second); self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'], 'BOUND')
        self.w.pause_codes.remove(970255)
        self.config.call('prepare', [wire, first]); self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'], 'RECEIVING')
        self.assertEqual(len(self.begin_acks()), 1)
        self.config.call('prepare', [wire, first]); self.w.drain(20000)
        self.assertEqual(len(self.begin_acks()), 1)
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])

    def test_mapping_timeout_and_late_result_cannot_start_treatment(self):
        self.bind(); self.prepare(); self.w.pause_codes.add(970255)
        request, wire = self.begin()
        self.advance(15)
        self.w.pause_codes.remove(970255)
        self.config.call('prepare', [wire, request]); self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'], 'BOUND')
        self.assertEqual(self.core.global_vars['gPendingRun'], t.h.NULL)
        self.assertEqual(self.begin_acks(), [])
        self.assertNotIn((t.BENCH, 'ws:inputs'), self.w.storage)
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])

    def test_core_reset_does_not_replay_an_unacknowledged_mapping(self):
        self.bind(); self.prepare(); self.w.pause_codes.add(970255)
        request, wire = self.begin()
        self.restart('core', 'Workshop.lsl')
        self.w.pause_codes.remove(970255)
        self.config.call('prepare', [wire, request]); self.w.drain(20000)
        self.assertEqual(self.begin_acks(), [])
        self.assertEqual(self.core.global_vars['gPhase'], 'BOUND')
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])

    def test_storage_failure_cannot_ack_a_mapped_input(self):
        self.bind(); self.prepare()
        self.w.fail_storage.add((t.BENCH, 'ws:inputs'))
        self.begin()
        self.assertTrue(self.core.global_vars['gFault'])
        self.assertEqual(self.begin_acks(), [])
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])

    def test_foreign_menu_reply_cannot_change_session_or_hover(self):
        self.bind()
        self.core.call('touch_start', [1]); self.w.drain(20000)
        core = self.w.storage[t.BENCH, 'ws:core']
        channel = self.interface.global_vars['gSessionMenu']
        for choice in ['Exit', 'Text: ON']:
            self.interface.call('listen', [channel, '', t.SOURCE, choice]); self.w.drain(20000)
        self.assertEqual(self.w.storage[t.BENCH, 'ws:core'], core)
        self.assertEqual(self.w.storage[t.BENCH, 'ws:hover'], '1')

    def test_stale_provision_request_cannot_give_or_rez_a_hud(self):
        self.bind()
        class TrackProvision(t.Script):
            def builtin(inner, name, args):
                if name in ('llRezObject', 'llGiveInventory'):
                    self.fail('A stale lease must not provision a HUD')
                return super().builtin(name, args)
        self.w.scripts.remove(self.interface)
        self.interface = TrackProvision(self.w, 'Workshop_Interface.lsl', t.BENCH)
        self.w.drain(20000)
        config = json.loads(self.w.storage[t.BENCH, 'ws:config'])
        config[5] = 0
        self.w.storage[t.BENCH, 'ws:config'] = json.dumps(config)
        old = t.h.Key(str(uuid.uuid4()))
        self.interface.call('link_message', [1, 970260, f'PROVISION|{old}', t.h.OWNER])
        self.w.drain(20000)

    def test_current_lease_provisions_owner_and_visitor_via_existing_paths(self):
        self.bind()
        deliveries = []
        class TrackProvision(t.Script):
            def constant(inner, text):
                if text.startswith('quaternion constant:'):
                    return (0.0, 0.0, 0.0, 1.0)
                return super().constant(text)
            def builtin(inner, name, args):
                if name == 'llGetPos':
                    return (0.0, 0.0, 0.0)
                if name in ('llRezObject', 'llGiveInventory'):
                    deliveries.append((name, args)); return
                return super().builtin(name, args)
        self.w.scripts.remove(self.interface)
        self.interface = TrackProvision(self.w, 'Workshop_Interface.lsl', t.BENCH)
        self.w.drain(20000)
        config = json.loads(self.w.storage[t.BENCH, 'ws:config'])
        config[2] = 'Dedicated HUD'; config[5] = 0
        self.w.storage[t.BENCH, 'ws:config'] = json.dumps(config)
        session = self.core.global_vars['gSession']
        self.interface.call('link_message', [1, 970260, f'PROVISION|{session}', t.h.OWNER])
        self.w.drain(20000)
        self.assertEqual(deliveries[0][0], 'llRezObject')
        self.core.global_vars['gUser'] = t.SOURCE
        self.core.call('save', [])
        self.interface.call('link_message', [1, 970260, f'PROVISION|{session}', t.SOURCE])
        self.w.drain(20000)
        self.assertEqual(deliveries[1], ('llGiveInventory', [t.SOURCE, 'Dedicated HUD']))


if __name__ == '__main__':
    unittest.main()
