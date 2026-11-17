"""Startup/reload status using the real loader and workshop script ASTs."""
import unittest
import uuid
import test_workshop_split as t
from test_observation_transport import Script


class Loader(Script):
    def builtin(self,name,args):
        if name=='llGetInventoryNumber': return 2
        if name=='llGetInventoryName': return ['bench_config','world'][args[1]]
        if name=='llGetNotecardLine':
            query=t.h.Key(str(uuid.uuid4()))
            lines=getattr(self.world,'world_lines',['tok:example = 123','law:observations:count = 0'])
            data=lines[args[1]] if args[1]<len(lines) else '\n\n\n'
            self.world.queue.append((self,'dataserver',[query,data]))
            return query
        return super().builtin(name,args)


class Readiness(unittest.TestCase):
    def setUp(self):
        self.base=t.SplitTests(); self.base.setUp(); self.w=self.base.w
        self.core=self.base.core

    def messages(self):
        return [text for obj,text in self.w.logs if obj==t.BENCH and text.startswith('[Workshop] READY:')]

    def observe_module(self):
        self.observer=Script(self.w,'Workshop_Observe.lsl',t.BENCH)
        self.w.drain(20000)

    def world_loader(self):
        self.loader=Loader(self.w,'World_Loader.lsl',t.BENCH)
        self.w.drain(20000)

    def test_no_ready_before_world_and_observation_service(self):
        self.assertEqual(self.messages(),[])
        self.observe_module()
        self.assertEqual(self.messages(),[])
        self.world_loader()
        self.assertEqual(len(self.messages()),1)
        self.assertIn('Observations available.',self.messages()[0])

    def test_world_alone_does_not_hide_missing_observation_module(self):
        self.world_loader()
        self.assertEqual(self.messages(),[])
        self.assertIn('observation service',self.core.global_vars['gReadyMessage'])
        self.observe_module()
        self.assertEqual(len(self.messages()),1)

    def test_reload_waits_for_eof_and_announces_once(self):
        self.observe_module(); self.world_loader()
        self.loader.call('startLoad',[])
        # Process just the first signal: the notecard has not reached EOF yet.
        script,event,args=self.w.queue.popleft(); script.call(event,args)
        self.assertFalse(self.core.global_vars['gWorldReady'])
        self.assertEqual(len(self.messages()),1)
        self.w.drain(20000)
        self.assertEqual(len(self.messages()),2)
        for _ in range(3):
            self.w.emit(t.BENCH,970298,'READY?'); self.w.drain(20000)
        self.assertEqual(len(self.messages()),2)

    def test_failed_world_write_never_announces_ready(self):
        self.observe_module()
        self.w.fail_storage.add((t.BENCH,'tok:example'))
        self.world_loader()
        self.assertEqual(self.messages(),[])
        self.assertFalse(self.core.global_vars['gWorldReady'])
        self.assertTrue(any("key='tok:example', write code=1" in text for obj,text in self.w.logs))

    def test_unchanged_world_write_does_not_mark_loading_failed(self):
        self.w.world_lines=['tok:example = 123','tok:example = 123','law:observations:count = 0']
        self.observe_module(); self.world_loader()
        self.assertFalse(self.loader.global_vars['gFailed'])
        self.assertEqual(len(self.messages()),1)
        self.assertTrue(any("notecard='world'; observations=0" in text for obj,text in self.w.logs))

    def test_loader_reports_missing_observation_index_in_the_loaded_notecard(self):
        self.w.world_lines=['tok:example = 123']
        self.world_loader()
        self.assertTrue(any("notecard='world'; observations=MISSING" in text for obj,text in self.w.logs))

    def test_complete_compiled_world_is_loaded_key_for_key(self):
        from pathlib import Path
        lines=(Path(__file__).resolve().parents[2]/'compiler/monde_observations.nc').read_text(encoding='utf-8').splitlines()
        root=Path(__file__).resolve().parents[2]
        self.assertEqual((root/'monde.nc').read_bytes(),(root/'compiler/monde_observations.nc').read_bytes())
        self.assertEqual((root/'compiler/monde.nc').read_bytes(),(root/'monde.nc').read_bytes())
        self.w.world_lines=lines
        self.w.storage[t.BENCH,'dom:st:obsolete']='medical'
        expected={}
        for line in lines:
            line=line.strip()
            if line and not line.startswith('#') and '=' in line:
                key,value=line.split('=',1)
                expected[key.strip()]=value.strip() or '1'
        self.world_loader()
        actual={key:value for (obj,key),value in self.w.storage.items()
                if obj==t.BENCH and key.startswith(('tok:','tax:','law:','idx:','dom:'))}
        self.assertEqual(actual,expected)
        self.assertEqual(actual['law:observations:count'],'30')
        self.assertEqual(actual['law:cutting_board:observe_leaf:observe_when'],'10=11^22~0~2')

    def test_core_restart_queries_already_loaded_world(self):
        self.observe_module(); self.world_loader()
        self.base.restart('core','Workshop.lsl'); self.core=self.base.core
        self.assertTrue(self.core.global_vars['gWorldReady'])
        self.assertEqual(len(self.messages()),2)

    def test_evaluator_reload_withholds_ready_until_config_is_loaded(self):
        self.observe_module(); self.world_loader()
        self.base.evaluator.call('loadConfig',[])
        script,event,args=self.w.queue.popleft(); script.call(event,args)
        self.assertIn('evaluator',self.core.global_vars['gReadyMessage'])
        self.assertEqual(len(self.messages()),1)
        self.w.drain(20000)
        self.assertEqual(len(self.messages()),2)


    def test_world_completion_revalidates_configuration_after_a_clean_reset(self):
        self.w.config=['Genre=cauldron','HUDKind=cutting_board','HeatAction=fab.thermal']
        self.core.call('loadConfig',[]); self.base.evaluator.call('loadConfig',[]); self.w.drain(20000)
        self.assertFalse(self.core.global_vars['gConfigReady'])
        self.w.world_lines=['tok:fab.thermal = 90','law:observations:count = 0']
        self.observe_module(); self.world_loader()
        self.assertTrue(self.core.global_vars['gConfigReady'])
        self.assertTrue(self.base.evaluator.global_vars['gConfigReady'])
        self.assertEqual(len(self.messages()),1)


if __name__=='__main__': unittest.main()
