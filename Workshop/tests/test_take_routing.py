"""Actual P1 -> Workshop -> P3/return-to-P0 AST flow. SL services are simulated."""
import json
import math
import unittest
from unittest.mock import patch
from pathlib import Path
import test_workshop_split as t
from test_stage_routing import dump_rules

h = t.h
for name, tree in json.loads((Path(__file__).resolve().parents[2] / 'Hud/tests/lsl_asts.json').read_text()).items():
    # Tailslide names LSL rotations "quaternion"; the harness calls them rotation.
    h.TREES[name] = h.tree(tree.replace('[quaternion]', '[rotation]'))

class Script(t.Script):
    def eval(self, n, env):
        if n.kind.startswith('lvalue expression') and len(n.children) == 2 and n.children[1].kind.startswith('identifier'):
            return self.eval(n.children[0], env)['xyzs'.index(n.children[1].name)]
        if n.kind == 'while':
            for _ in range(1000):
                if not self.eval(n.children[0], env): return
                self.eval(n.children[1], env)
            raise AssertionError('Unbounded loop')
        return super().eval(n, env)

    def builtin(self, name, a):
        w = self.world
        if name == 'llGetNumberOfPrims': return len(w.names)
        if name == 'llGetLinkName': return w.names.get(a[0], '')
        if name == 'llGetLinkNumberOfSides': return 6
        if name == 'llGetObjectDetails': return ['Vial'] if a[0] in w.containers else ['Source']
        if name == 'llGetLocalRot': return (*w.angles, 1.)
        if name == 'llRot2Euler': return a[0][:3]
        if name == 'llEuler2Rot': return (*a[0], 1.)
        if name == 'llSetLinkPrimitiveParamsFast':
            w.params.append(a)
            if len(a[1]) == 2:
                w.angles = a[1][1][:3]
                w.rotations.append(w.angles[2])
            return
        if name == 'llSetLinkAlpha': w.alpha[a[0], a[2]] = a[1]; return
        return super().builtin(name, a)

class TakeRoutingTests(unittest.TestCase):
    def setUp(self):
        self.base = t.SplitTests()
        with patch.object(t, 'Script', Script):
            self.base.setUp()
        self.w = self.base.w
        self.w.angles = (0., 0., 0.); self.w.rotations = []; self.w.alpha = {}
        names = ['ROOT', 'P1_ACTION2']
        for prefix in ('P3_QTY_', 'P3_Icon_', 'P3_Sel_QTY_', 'P3_Sel_Icon_'):
            names += [prefix + str(i) for i in range(4)]
        self.w.names = dict(enumerate(names, 1))
        self.p1 = Script(self.w, 'MC_P1_Controller.lsl', t.HUD)
        self.p3 = Script(self.w, 'MC_P3_Controller.lsl', t.HUD)
        self.scan = Script(self.w, 'MC_Scan.lsl', t.HUD)
        self.render = Script(self.w, 'MC_Render_P3_NEAR.lsl', t.HUD)
        self.turn = Script(self.w, 'MC_Turn_Z.lsl', t.HUD)
        self.w.drain(20000)
        dump_rules(self.w)
        self.base.bind()

    def prepare(self, stage='plant'):
        self.base.add(stage=stage)
        self.base.selected.call('basketAction', ['CRAFT_STARTED', t.RUN]); self.w.drain(20000)
        self.w.emit(t.HUD, 918310, 'CONTINUE', t.RUN); self.w.drain(20000)
        self.assertAlmostEqual(self.w.angles[2], -math.pi / 2, delta=0.00001)

    def take(self):
        self.p1.call('button', ['p1_action2']); self.w.drain(20000)

    def finish_scan(self):
        self.w.now += 2
        self.scan.call('timer', []); self.w.drain(20000)

    def notices(self):
        return [text for obj, text in self.w.logs if obj == t.HUD and 'Objet remis' in text]

    def table(self):
        return [r[3] for r in self.w.replies if r[0] == t.HUD and r[4] == 'fw_data:P3_Table1'][-1]

    def test_take_direct_inventory_skips_p3_notifies_and_closes_once(self):
        self.prepare(); self.take()
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])
        self.assertEqual(len(self.notices()), 1)
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.assertFalse(self.p3.global_vars['gScanning'])
        self.assertNotIn(self.turn.global_vars['P3_Z'], self.w.rotations)
        self.assertEqual(self.w.angles[2], 0.)
        self.assertEqual(self.base.link.global_vars['gPhase'], 'IDLE')
        self.assertEqual(self.w.stock[t.SOURCE], [9, 0])
        run = self.base.link.global_vars['gRun']
        for _ in range(2):
            self.w.chat(t.BENCH, -918275, f'MCW|RESULT|{t.HUD}|{self.base.link.global_vars["gSession"]}|{run}|OK|GIVE')
            self.w.drain(20000)
        self.assertEqual(len(self.notices()), 1)
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])

    def test_container_output_opens_p3_only_after_evaluation_with_empty_guidance(self):
        self.prepare('leaf')
        self.w.pause_codes.add(970202)
        self.take()
        self.assertEqual(self.base.core.global_vars['gPhase'], 'EVALUATING')
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.assertAlmostEqual(self.w.angles[2], -math.pi / 2, delta=0.00001)
        run = self.base.core.global_vars['gRun']
        self.w.pause_codes.remove(970202)
        self.w.emit(t.BENCH, 970202, 'fab.grind:hud', run); self.w.drain(20000)
        self.assertTrue(self.p3.global_vars['gOpen'])
        self.assertEqual(self.w.angles[2], self.turn.global_vars['P3_Z'])
        self.assertIn('Recherche en cours', self.table())
        self.finish_scan()
        self.assertIn('Aucun conteneur vide.', self.table())
        self.assertIn('Placez-en a proximite', self.table())
        self.assertIn('Actualiser', self.table())
        self.assertEqual(self.w.physical, [])
        self.assertFalse(self.notices())
        self.assertEqual(self.w.stock[t.SOURCE], [9, 0])
        self.p3.call('button', ['p3_sel_0']); self.w.drain(20000)
        self.assertEqual(self.p3.global_vars['gSelected'], [])
        self.p3.call('button', ['p3_action2']); self.w.drain(20000)
        self.assertEqual(self.base.link.global_vars['gPhase'], 'OUTPUT')

    def test_direct_result_recovery_repeats_notice_without_redelivering_objects(self):
        self.prepare(); self.w.pause_codes.add(970202); self.take()
        run = self.base.core.global_vars['gRun']
        self.w.pause_codes.remove(970202)
        self.w.pause_codes.add(970211) # lose Workshop's final RESULT
        self.w.emit(t.BENCH, 970202, 'fab.grind:hud', run); self.w.drain(20000)
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])
        self.assertEqual(self.base.link.global_vars['gPhase'], 'WAIT_RESULT')
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])
        self.assertFalse(self.notices())
        self.w.pause_codes.remove(970211)
        self.base.core.call('resume', []); self.w.drain(20000)
        self.assertEqual(len(self.notices()), 1)
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])
        self.assertEqual(self.base.link.global_vars['gPhase'], 'IDLE')
        self.assertEqual(self.w.stock[t.SOURCE], [9, 0])
        self.assertNotIn(self.turn.global_vars['P3_Z'], self.w.rotations)

    def test_multi_organ_inventory_delivery_also_skips_p3(self):
        self.w.storage[t.BENCH, 'tax:16:organs'] = '11^17'
        self.prepare(); self.take()
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}|leaf^root'])
        self.assertEqual(len(self.notices()), 1)
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.assertNotIn(self.turn.global_vars['P3_Z'], self.w.rotations)
        self.assertEqual(self.w.angles[2], 0.)

    def test_add_container_refresh_transfer_and_return_to_p0(self):
        self.prepare('leaf'); self.take(); self.finish_scan()
        self.w.containers[t.CONTAINER] = 0
        self.p3.call('button', ['p3_action1']); self.w.drain(20000); self.finish_scan()
        self.assertNotIn('Aucun conteneur', self.table())
        self.assertIn('Vial', self.table())
        self.p3.call('button', ['p3_sel_0']); self.w.drain(20000)
        self.assertEqual(self.p3.global_vars['gSelected'][0], t.CONTAINER)
        self.assertIn('Cliquez Transferer.', self.table())
        self.p3.call('button', ['p3_action2']); self.w.drain(20000)
        self.base.advance(2)
        self.assertEqual(len(self.w.physical), 1)
        self.assertTrue(self.w.physical[0].startswith(f'CONFIG|{t.CONTAINER}|'))
        self.assertEqual(self.w.angles[2], 0.)
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.assertFalse(self.table().strip())
        self.assertEqual(self.w.stock[t.SOURCE], [9, 0])
        self.assertEqual(self.base.link.global_vars['gPhase'], 'IDLE')
        self.assertFalse(self.notices())

    def test_refusal_retains_preparation_and_p1(self):
        self.prepare('powder'); self.take()
        self.assertEqual(self.base.link.global_vars['gPhase'], 'IDLE')
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.assertNotIn(self.turn.global_vars['P3_Z'], self.w.rotations)
        self.assertAlmostEqual(self.w.angles[2], -math.pi / 2, delta=0.00001)
        self.assertEqual(self.w.stock[t.SOURCE], [9, 1])
        self.assertEqual(self.w.physical, [])

    def test_double_take_does_not_submit_a_second_preparation(self):
        self.prepare(); self.w.pause_codes.add(970202)
        self.take(); run = self.base.core.global_vars['gRun']
        self.take()
        self.assertEqual(self.base.core.global_vars['gRun'], run)
        begins = [wire for obj, target, channel, wire in self.w.radio if obj == t.HUD and wire.startswith('MCW|BEGIN|')]
        self.assertEqual(len(begins), 1)
        self.assertFalse(self.p3.global_vars['gOpen'])

    def test_obsolete_preselection_saved_state_does_not_open_p3(self):
        self.prepare(); self.w.pause_codes.add(970202); self.take()
        self.w.storage[t.HUD, 'mc:p3:selection'] = json.dumps([str(h.NULL), '[]', str(h.NULL), str(h.NULL), 1, str(h.NULL)])
        self.w.scripts.remove(self.p3)
        self.p3 = Script(self.w, 'MC_P3_Controller.lsl', t.HUD); self.w.drain(20000)
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.w.emit(t.HUD, 918391, 'SELECTING|0|', h.NULL); self.w.drain(20000)
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.assertNotIn(self.turn.global_vars['P3_Z'], self.w.rotations)

    def test_p3_reset_recovers_real_container_output(self):
        self.prepare('leaf'); self.take(); self.finish_scan()
        self.w.scripts.remove(self.p3)
        self.p3 = Script(self.w, 'MC_P3_Controller.lsl', t.HUD); self.w.drain(20000)
        self.assertTrue(self.p3.global_vars['gOpen'])
        self.assertEqual(self.p3.global_vars['gProduct'], self.base.core.global_vars['gRun'])
        self.finish_scan()
        self.assertIn('Aucun conteneur vide.', self.table())

    def test_unrelated_output_phases_cannot_open_recipient_page(self):
        self.prepare()
        for phase in ('GIVING', 'DONE', 'SELECTING', 'HOLD'):
            self.w.emit(t.HUD, 918391, phase + '|0|', t.RUN); self.w.drain(20000)
        self.assertFalse(self.p3.global_vars['gOpen'])
        self.assertNotIn(self.turn.global_vars['P3_Z'], self.w.rotations)

if __name__ == '__main__': unittest.main(verbosity=2)
