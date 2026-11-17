"""Real HUD -> Workshop -> evaluator -> P4 text; LSL services are test doubles."""
import copy
import json
import unittest
from unittest.mock import patch
import test_workshop_split as t


class Script(t.Script):
    def eval(self, node, env):
        if node.kind == "unary expression: '-- (pre)'":
            name=node.children[0].children[0].name
            target=env if name in env else self.global_vars
            target[name]-=1
            return target[name]
        if node.kind == 'while':
            for _ in range(10000):
                if not self.eval(node.children[0],env): return
                self.eval(node.children[1],env)
            raise AssertionError('Unbounded loop')
        return super().eval(node,env)

    def builtin(self,name,args):
        w=self.world
        if name == 'llFrand' and hasattr(w,'random_draws'): w.random_draws+=1
        if name == 'llGetNumberOfPrims': return len(w.names)
        if name == 'llGetLinkName': return w.names.get(args[0],'')
        if name == 'llGetLinkNumberOfSides': return 6
        if name == 'llSetLinkTextureAnim': return
        if name == 'llWhisper' and '|INSPECT_VERIFY|' in args[1]:
            callback=getattr(w,'on_verify',None)
            if callback:
                w.on_verify=None
                callback()
        return super().builtin(name,args)


class ClockScript(Script):
    def builtin(self,name,args):
        if name == 'llDetectedLinkNumber': return self.world.touch_link
        result=super().builtin(name,args)
        # Only visual player replies are simulated; the actual clock supplies INSPECT/SNAPSHOT.
        if name == 'llMessageLinked' and self.file == 'MC_P1_Animation.lsl':
            code=args[1]
            reply={918330:'LOADED',918331:'PLAYING',918335:'PLAYING',918334:'PAUSED',918332:'REST'}.get(code)
            if reply: self.world.emit(t.HUD,918333,reply,args[3])
        return result


class ObservationTransport(unittest.TestCase):
    def setUp(self):
        self.base=t.SplitTests()
        with patch.object(t,'Script',Script): self.base.setUp()
        self.w=self.base.w
        self.w.random_draws=0
        self.w.names={1:'ROOT',2:'P4_ACTION1',3:'P4_ACTION2',
            4:'FURWARE text mesh:P4_Table1:0:0:8',5:'FURWARE text mesh:P4_Name:0:0:8',
            6:'FURWARE text mesh:P4_Status:0:0:8'}
        self.adapter=Script(self.w,'Workshop_Observe.lsl',t.BENCH)
        self.view=Script(self.w,'MC_P4_Controller.lsl',t.HUD)
        self.w.drain(20000)
        self.base.bind(); self.base.add()
        self.w.storage[t.BENCH,'law:observations:count']='2'
        for index,name,condition,text in [(0,'leaves','10=11','The preparation contains leaves.'),
                                          (1,'working','22>=4','The leaves are being crushed.')]:
            self.w.storage[t.BENCH,f'law:observations:{index}']='cutting_board|'+name
            for field,value in [('observe_when',condition),('description',text)]:
                self.w.storage[t.BENCH,f'law:cutting_board:{name}:{field}']=value

    def observe(self, seconds='4.75', heat='-1'):
        if self.w.storage.get((t.HUD,'mc:simple:craft_started')) != '1':
            self.base.selected.call('basketAction',['CRAFT_STARTED',t.RUN]); self.w.drain(20000)
        self.view.call('openObservation',[t.RUN]); self.w.drain(20000)
        ticket=self.base.link.global_vars['gInspectTicket']
        self.w.emit(t.HUD,918399,f'OK|{seconds}|{heat}',ticket); self.w.drain(20000)
        return ticket

    def test_real_bridge_displays_concatenated_descriptions_and_product_name(self):
        self.base.selected.call('basketAction',['CRAFT_STARTED',t.RUN]); self.w.drain(20000)
        before=copy.deepcopy(self.w.storage)
        stock=copy.deepcopy(self.w.stock)
        self.observe()
        self.assertEqual(self.view.global_vars['gBody'],
            'The preparation contains leaves. The leaves are being crushed.')
        self.assertEqual(self.view.global_vars['gName'],'Mint')
        self.assertEqual(self.w.storage,before)
        self.assertEqual(self.w.stock,stock)
        self.assertEqual(self.w.physical,[])
        self.assertEqual(self.base.core.global_vars['gPhase'],'BOUND')
        self.assertTrue(any(reply[4]=='fw_data:P4_Table1' and 'crushed' in reply[3] for reply in self.w.replies))
        self.assertNotIn((t.BENCH,'ws:eval:result'),self.w.storage)
        self.assertEqual(self.w.random_draws,0)

    def test_no_match_is_explicit_and_has_a_name(self):
        self.w.storage[t.BENCH,'law:cutting_board:leaves:observe_when']='10=23'
        self.observe(seconds='0')
        self.assertEqual(self.view.global_vars['gName'],'Mint')
        self.assertIn('no observations',self.view.global_vars['gBody'])

    def test_same_name_stage_groups_use_total_held_quantity_and_first_metadata(self):
        self.base.add(t.SOURCE2)
        self.observe()
        self.assertIn('contains leaves',self.view.global_vars['gBody'])
        self.assertEqual(self.w.stock[t.SOURCE],[9,1])
        self.assertEqual(self.w.stock[t.SOURCE2],[9,1])
        self.assertEqual(self.w.physical,[])

    def test_snapshot_change_during_transfer_is_rejected(self):
        name='mc:simple:row:'+str(t.SOURCE)
        original=self.w.storage[t.HUD,name]
        self.w.on_verify=lambda: self.w.storage.__setitem__((t.HUD,name),original.replace('act.nervous','org.smell'))
        self.observe()
        self.assertIn('Basket changed',self.view.global_vars['gBody'])
        self.assertEqual(self.w.physical,[])
        self.assertNotIn((t.BENCH,'ws:eval:result'),self.w.storage)

    def test_pending_source_transaction_is_not_observed(self):
        name='mc:simple:row:'+str(t.SOURCE)
        row=self.w.storage[t.HUD,name].split('|'); row[2]='COMMIT'
        self.w.storage[t.HUD,name]='|'.join(row)
        self.observe()
        self.assertIn('update pending',self.view.global_vars['gBody'])
        self.assertEqual(self.w.stock[t.SOURCE],[9,1])

    def test_cancel_releases_both_ends_and_late_result_is_ignored(self):
        self.w.pause_codes.add(970240)
        ticket=self.observe()
        self.view.call('close',[True]); self.w.drain(20000)
        self.assertEqual(self.base.config.global_vars['gInspectTicket'],t.h.NULL)
        self.assertEqual(self.base.link.global_vars['gInspectTicket'],t.h.NULL)
        body=self.view.global_vars['gBody']
        self.w.emit(t.BENCH,970241,'OBSERVATIONS|late',ticket); self.w.drain(20000)
        self.assertEqual(self.view.global_vars['gBody'],body)
        self.w.pause_codes.clear()
        self.observe()
        self.assertIn('contains leaves',self.view.global_vars['gBody'])

    def test_description_too_large_for_radio_returns_error(self):
        self.w.storage[t.BENCH,'law:cutting_board:leaves:description']='word '*220
        self.observe()
        self.assertIn('too long for one reply',self.view.global_vars['gBody'])
        self.assertFalse(self.view.global_vars['gPending'])

    def test_finish_after_observation_still_crafts_normally(self):
        self.observe(); self.view.call('close',[True]); self.w.drain(20000)
        self.base.submit()
        self.assertEqual(self.base.core.global_vars['gPhase'],'PRODUCT')
        self.assertEqual(self.w.stock[t.SOURCE],[9,0])
        self.assertIn((t.BENCH,'ws:eval:result'),self.w.storage)

    def test_compiled_world_descriptions_and_configured_heat_reach_p4(self):
        from pathlib import Path
        lines=(Path(__file__).resolve().parents[2]/'compiler/monde_observations.nc').read_text(encoding='utf-8').splitlines()
        for line in lines:
            if ' = ' in line:
                key,value=line.split(' = ',1)
                self.w.storage[t.BENCH,key]=value or '1'
        self.w.config += ['Genre=cauldron','HUDKind=cutting_board','HeatAction=fab.thermal','InspectHandler=1']
        self.base.core.call('loadConfig',[])
        self.base.evaluator.call('loadConfig',[])
        self.w.drain(20000)
        self.observe(seconds='12.5',heat='12')
        self.assertIn('The mixture is gently simmering.',self.view.global_vars['gBody'])

    def test_foreign_snapshot_requests_cannot_read_the_basket(self):
        self.w.pause_codes.add(970240)
        ticket=self.observe()
        session=self.base.link.global_vars['gSession']
        before=len([wire for _,_,_,wire in self.w.radio if '|INSPECT_ROW|' in wire])
        self.w.chat(t.SOURCE,-918275,f'MCW|INSPECT_NEXT|{t.HUD}|{session}|{ticket}|0')
        self.w.chat(t.BENCH,-918275,f'MCW|INSPECT_NEXT|{t.HUD}|{t.RUN}|{ticket}|0')
        self.w.drain(20000)
        self.assertEqual(len([wire for _,_,_,wire in self.w.radio if '|INSPECT_ROW|' in wire]),before)

    def test_adapter_timeout_clears_transient_state(self):
        self.w.pause_codes.add(918414)
        self.observe()
        self.w.now+=11
        self.adapter.call('timer',[]); self.w.drain(20000)
        self.assertIn('No complete HUD basket reply',self.view.global_vars['gBody'])
        self.assertEqual(self.adapter.global_vars['gTicket'],t.h.NULL)
        self.assertEqual(self.adapter.global_vars['gGroups'],[])

    def test_missing_clock_response_identifies_the_local_stage(self):
        self.view.call('openObservation',[t.RUN]); self.w.drain(20000)
        self.w.now+=16
        self.base.link.call('timer',[]); self.w.drain(20000)
        self.assertIn('Preparation clock did not reply',self.view.global_vars['gBody'])
        self.assertFalse(self.view.global_vars['gPending'])

    def test_workshop_timeout_is_not_a_generic_unavailable(self):
        self.w.pause_codes.add(970240)
        self.observe()
        self.w.now+=11
        self.base.config.call('timer',[]); self.w.drain(20000)
        self.assertIn('Workshop_Observe did not acknowledge',self.view.global_vars['gBody'])

    def test_config_deadline_cannot_mask_adapter_timeout(self):
        self.w.pause_codes.add(918414)
        self.observe()
        self.w.now+=10
        self.base.config.call('timer',[]); self.w.drain(20000)
        self.assertTrue(self.view.global_vars['gPending'])
        self.adapter.call('timer',[]); self.w.drain(20000)
        self.assertIn('No complete HUD basket reply',self.view.global_vars['gBody'])
        self.assertFalse(self.view.global_vars['gPending'])

    def test_missing_evaluator_response_identifies_request_970204(self):
        self.w.pause_codes.add(970204)
        self.observe()
        self.assertEqual(self.adapter.global_vars['gPhase'],'EVALUATING')
        self.w.now+=10
        self.base.config.call('timer',[]); self.w.drain(20000)
        self.adapter.call('timer',[]); self.w.drain(20000)
        self.assertIn('Workshop_Eval did not answer observation request 970204',self.view.global_vars['gBody'])

    def test_missing_verification_response_identifies_verification_stage(self):
        def stop_verification(): self.w.pause_codes.add(918414)
        self.w.on_verify=stop_verification
        self.observe()
        self.assertEqual(self.adapter.global_vars['gPhase'],'VERIFY')
        self.w.now+=10
        self.adapter.call('timer',[]); self.w.drain(20000)
        self.assertIn('HUD basket verification did not reach',self.view.global_vars['gBody'])

    def test_no_workshop_reply_identifies_the_remote_stage(self):
        self.w.pause_codes.add(970256)
        self.observe()
        self.w.now+=16
        self.base.link.call('timer',[]); self.w.drain(20000)
        self.assertIn('Workshop did not start the observation',self.view.global_vars['gBody'])

    def test_back_does_not_print_product_test_cancelled(self):
        self.w.pause_codes.add(970240)
        self.observe(); self.view.call('close',[True]); self.w.drain(20000)
        self.assertFalse(any('[Product test]' in text or '[Observation]' in text
            for obj,text in self.w.logs if obj==t.HUD))

    def test_actual_pause_clock_observation_back_and_take_complete_the_craft(self):
        emit=self.w.emit
        self.w.emit=lambda obj,code,text='',ticket=t.h.NULL: None if code==918373 else emit(obj,code,text,ticket)
        self.w.names.update({7:'P1_ACTION1',8:'P1_ACTION2',9:'P1_ACTION3'})
        engine=ClockScript(self.w,'MC_P1_Animation.lsl',t.HUD); self.w.drain(20000)
        self.w.touch_link=7
        engine.call('touch_start',[1]); self.w.drain(20000)
        self.assertTrue(engine.global_vars['gClockActive'])
        self.w.now+=4.75; engine.call('timer',[]); self.w.drain(20000)
        self.w.touch_link=8
        engine.call('touch_start',[1]); self.w.drain(20000)
        self.assertEqual(engine.global_vars['gElapsed'],4.75)
        self.assertFalse(engine.global_vars['gClockActive'])
        self.assertIn('The leaves are being crushed.',self.view.global_vars['gBody'])
        self.assertEqual(self.w.stock[t.SOURCE],[9,1])
        self.assertEqual(self.w.physical,[])
        self.view.call('button',['p4_action1']); self.w.drain(20000)
        engine.call('touch_start',[1]); self.w.drain(20000)
        self.assertEqual(self.base.core.global_vars['gPhase'],'PRODUCT')
        self.assertEqual(self.w.stock[t.SOURCE],[9,0])


if __name__=='__main__': unittest.main()
