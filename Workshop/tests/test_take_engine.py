"""Take routing with the real preparation engine, not a fabricated SNAPSHOT reply."""
import unittest
import test_take_routing as r

t = r.t

class EngineScript(r.Script):
    def builtin(self, name, a):
        if name == 'llDetectedLinkNumber': return self.world.take_link
        result = super().builtin(name, a)
        if name == 'llMessageLinked' and self.file == 'MC_P1_Animation.lsl':
            # Cosmetic player ACKs only; the real engine owns elapsed time and SNAPSHOT.
            if a[1] == 918330: self.world.emit(t.HUD, 918333, 'LOADED', a[3])
            elif a[1] in (918331, 918335): self.world.emit(t.HUD, 918333, 'PLAYING', a[3])
            elif a[1] == 918334: self.world.emit(t.HUD, 918333, 'PAUSED', a[3])
            elif a[1] == 918332: self.world.emit(t.HUD, 918333, 'REST', a[3])
        return result

class EngineTakeTests(unittest.TestCase):
    def setUp(self):
        self.base = r.TakeRoutingTests(); self.base.setUp()
        self.w = self.base.w
        emit = self.w.emit
        # Disable test_workshop_split's synthetic SNAPSHOT response. The real
        # engine sends its own linked response via llMessageLinked instead.
        self.w.emit = lambda obj, code, text='', ticket=t.h.NULL: None if code == 918373 else emit(obj, code, text, ticket)
        self.engine = EngineScript(self.w, 'MC_P1_Animation.lsl', t.HUD)
        self.w.drain(20000)

    def prepare(self, stage='plant'):
        self.base.base.add(stage=stage)
        self.engine.call('button', ['p1_action1']); self.w.drain(20000)
        self.assertTrue(self.engine.global_vars['gStarted'])
        self.w.now += 3

    def test_take_inventory_with_real_engine_playing(self):
        self.prepare(); self.base.take()
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])
        self.assertEqual(self.base.base.link.global_vars['gPhase'], 'IDLE')

    def test_take_inventory_after_stop(self):
        self.prepare(); self.engine.call('button', ['p1_action1']); self.w.drain(20000)
        self.base.take()
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])

    def test_take_container_with_real_engine_playing(self):
        self.prepare('leaf'); self.base.take()
        self.assertTrue(self.base.p3.global_vars['gOpen'])
        self.assertEqual(self.base.base.link.global_vars['gPhase'], 'OUTPUT')

    def test_take_container_after_stop(self):
        self.prepare('leaf'); self.engine.call('button', ['p1_action1']); self.w.drain(20000)
        self.base.take()
        self.assertTrue(self.base.p3.global_vars['gOpen'])

    def test_take_after_engine_reset(self):
        self.prepare(); self.engine.call('button', ['p1_action1']); self.w.drain(20000)
        self.w.scripts.remove(self.engine)
        self.engine = EngineScript(self.w, 'MC_P1_Animation.lsl', t.HUD); self.w.drain(20000)
        self.base.take()
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])

    def test_take_repeated_preparations(self):
        for _ in range(2):
            self.prepare(); self.base.take()
            self.assertEqual(self.base.base.link.global_vars['gPhase'], 'IDLE')
        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'] * 2)

    def test_physical_take_names_reach_the_workshop_in_normal_use(self):
        for name in ('P1_ACTION2', 'P1_TAKE', ' p1_take '):
            for stage in ('plant', 'leaf'):
                with self.subTest(name=name, stage=stage):
                    self.setUp()
                    self.w.names[2] = name
                    self.w.take_link = 2
                    self.w.scripts.remove(self.base.p1)
                    self.base.p1 = EngineScript(self.w, 'MC_P1_Controller.lsl', t.HUD)
                    self.w.drain(20000)
                    self.prepare(stage)
                    self.base.p1.call('touch_start', [1]); self.w.drain(20000)
                    if stage == 'plant':
                        self.assertEqual(self.w.physical, [f'GIVE|{t.SOURCE}'])
                    else:
                        self.assertTrue(self.base.p3.global_vars['gOpen'])

if __name__ == '__main__': unittest.main(verbosity=2)
