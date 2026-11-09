"""Workshop 0.8: actual ASTs with simulated SL services, never a Mono validation."""
import json
import unittest
import uuid
import test_workshop_split as s
import test_p3_recovery as recovery

h=s.h

class CleanupTests(unittest.TestCase):
    setUp=s.SplitTests.setUp
    bind=s.SplitTests.bind
    here=s.SplitTests.here
    add=s.SplitTests.add
    prepare=s.SplitTests.prepare
    submit=s.SplitTests.submit
    advance=s.SplitTests.advance
    collect=s.SplitTests.collect
    restart=s.SplitTests.restart

    def ready(self):
        self.w.now=1800000000
        self.bind();self.prepare();self.submit()

    def test_result_ready_without_cook_timer_even_with_old_config(self):
        self.w.config.append('CookTime=1h')
        self.core.call('loadConfig',[]);self.w.drain(20000)
        self.ready()
        self.assertEqual(self.core.global_vars['gPhase'],'PRODUCT')
        self.assertEqual(self.output.global_vars['gPhase'],'WAIT_CONTAINER')
        self.assertEqual(self.w.stock[s.SOURCE],[9,0])
        self.assertNotIn('gCookTime',self.output.global_vars)

    def test_partial_transfers_and_reset_keep_exact_lot_expiry(self):
        self.ready();expiry=self.output.global_vars['gExpiry']
        self.w.containers={s.CONTAINER:2};self.collect()
        self.assertEqual(self.output.global_vars['gQuantity'],3)
        first=self.w.physical[-1].split('|')
        self.advance(500);self.restart('output','Workshop_Output.lsl')
        self.assertEqual(self.output.global_vars['gExpiry'],expiry)
        self.w.containers={s.SOURCE2:0};self.collect()
        second=self.w.physical[-1].split('|')
        self.assertEqual(int(first[11]),expiry)
        self.assertEqual(int(second[11]),expiry)
        self.assertLess(int(second[10]),int(first[10]))
        self.assertEqual(self.output.global_vars['gQuantity'],0)

    def test_component_preserves_absolute_expiry_and_base_lifetime(self):
        class Container(s.Script):
            def call(self,name,args):
                if name=='state_entry':return
                return super().call(name,args)
            def builtin(self,name,args):
                if name in ('llSetObjectName','llSetLinkPrimitiveParamsFast','llSay'):return
                return super().builtin(name,args)
        self.ready();expiry=self.output.global_vars['gExpiry']
        self.advance(500)
        container=Container(self.w,'Component.lsl',s.CONTAINER,{'gRole':2})
        self.w.containers={s.CONTAINER:0};self.collect()
        self.assertEqual(container.global_vars['gExpiry'],expiry)
        self.assertEqual(container.global_vars['gLifeSecs'],86400)
        # Container restore reads the original expiration rather than renewing it.
        self.assertEqual(int(self.w.storage[s.CONTAINER,'rz_exp']),expiry)

    def test_expiry_ends_remainder_without_delivery_or_new_stock_operation(self):
        self.ready();before=list(self.w.receipts)
        self.w.now=self.output.global_vars['gExpiry']
        self.output.call('timer',[]);self.w.drain(20000)
        self.assertEqual(self.output.global_vars['gQuantity'],0)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')
        self.assertEqual(self.w.receipts,before)
        self.assertEqual(self.w.physical,[])

    def test_component_refuses_invalid_or_expired_absolute_date_before_mutation(self):
        class Blank(s.Script):
            def call(self,name,args):
                if name=='state_entry':return
                return super().call(name,args)
        self.w.now=1800000000
        blank=Blank(self.w,'Component.lsl',s.CONTAINER,{'gRole':2})
        for life,expiry in [('100','0'),('100','-1'),('100','bad'),('100','1800000000'),('0','1800001000')]:
            wire=f'CONFIG|{s.CONTAINER}|Mint|3|1|{life}|mint|chopped|||950|{expiry}'
            blank.call('listen',[-918273,'',s.BENCH,wire])
            self.assertFalse(blank.global_vars['gReady'])
            self.assertEqual(blank.global_vars['gQuantity'],0)
            self.assertEqual(blank.global_vars['gName'],'')

    def test_legacy_config_without_absolute_date_still_uses_relative_freshness(self):
        class Blank(s.Script):
            def call(self,name,args):
                if name=='state_entry':return
                return super().call(name,args)
            def builtin(self,name,args):
                if name in ('llSetObjectName','llSetLinkPrimitiveParamsFast','llSay'):return
                return super().builtin(name,args)
        self.w.now=1800000000
        blank=Blank(self.w,'Component.lsl',s.CONTAINER,{'gRole':2})
        wire=f'CONFIG|{s.CONTAINER}|Mint|3|1|1000|mint|chopped|||950'
        blank.call('listen',[-918273,'',s.BENCH,wire])
        self.assertTrue(blank.global_vars['gReady'])
        self.assertEqual(blank.global_vars['gExpiry'],self.w.now+950)

    def test_expiry_during_scan_returns_terminal_outcome(self):
        self.ready();self.w.containers={s.CONTAINER:0}
        self.w.now=self.output.global_vars['gExpiry']-1
        self.w.emit(s.HUD,918390,f'TRANSFER|{s.CONTAINER}',h.Key(str(uuid.uuid4())))
        self.w.drain(20000);self.advance(2)
        self.assertEqual(self.w.physical,[])
        self.assertEqual(self.output.global_vars['gQuantity'],0)
        receipt=json.loads(self.w.storage[s.BENCH,'ws:out:receipt'])[2]
        self.assertTrue(receipt.startswith('TRANSFER_EXPIRED|'))
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')

    def test_expiry_is_checked_before_direct_delivery_and_after_offline_reset(self):
        self.ready();self.w.now=self.output.global_vars['gExpiry']+10
        self.restart('output','Workshop_Output.lsl')
        self.assertEqual(self.output.global_vars['gPhase'],'DONE')
        self.assertEqual(self.output.global_vars['gQuantity'],0)
        self.assertEqual(self.w.physical,[])

    def test_unlimited_lot_has_no_expiry(self):
        self.here=lambda source=s.SOURCE,**kw:s.SplitTests.here(self,source,**kw).replace('|86400|','|0|')
        self.ready();self.advance(31536000)
        self.assertEqual(self.output.global_vars['gExpiry'],0)
        self.assertEqual(self.output.global_vars['gQuantity'],5)
        self.w.containers={s.CONTAINER:0};self.collect()
        wire=self.w.physical[-1].split('|')
        self.assertEqual(wire[5],'0');self.assertEqual(wire[11],'0')

    def test_legacy_perishable_product_retained_without_fabricated_age(self):
        self.ready();saved=json.loads(self.w.storage[s.BENCH,'ws:output'])[:10]
        self.w.storage[s.BENCH,'ws:output']=json.dumps(saved)
        self.restart('output','Workshop_Output.lsl')
        self.assertEqual(self.output.global_vars['gPhase'],'HOLD')
        self.assertEqual(self.output.global_vars['gQuantity'],5)
        self.assertEqual(self.output.global_vars['gExpiry'],-1)
        self.assertEqual(self.w.physical,[])

    def test_legacy_receipt_finishes_without_replaying_and_holds_unknown_remainder(self):
        self.ready();self.w.containers={s.CONTAINER:2};self.collect()
        saved=json.loads(self.w.storage[s.BENCH,'ws:output'])[:10];saved[3]='RECEIPTING'
        self.w.storage[s.BENCH,'ws:output']=json.dumps(saved);before=list(self.w.physical)
        self.restart('output','Workshop_Output.lsl')
        self.assertEqual(self.output.global_vars['gQuantity'],3)
        self.assertEqual(self.output.global_vars['gPhase'],'HOLD')
        self.assertEqual(self.w.physical,before)

    def test_legacy_unlimited_cooking_state_migrates_without_delay(self):
        self.here=lambda source=s.SOURCE,**kw:s.SplitTests.here(self,source,**kw).replace('|86400|','|0|')
        self.ready();saved=json.loads(self.w.storage[s.BENCH,'ws:output'])[:10]
        saved[3]='COOKING';saved[6]=int(self.w.now)+3600
        self.w.storage[s.BENCH,'ws:output']=json.dumps(saved)
        self.restart('output','Workshop_Output.lsl')
        self.assertEqual(self.output.global_vars['gPhase'],'WAIT_CONTAINER')
        self.assertEqual(self.output.global_vars['gQuantity'],5)

    def test_output_save_failure_prevents_physical_dispatch(self):
        self.ready();self.w.containers={s.CONTAINER:0}
        self.w.fail_storage.add((s.BENCH,'ws:output'))
        self.collect()
        self.assertEqual(self.w.physical,[])
        self.assertEqual(self.output.global_vars['gQuantity'],5)

    def test_activity_effects_follow_hud_and_stop_if_activity_is_lost(self):
        self.w.now=1800000000;self.bind()
        self.w.emit(s.HUD,918394,'1');self.w.drain(20000)
        self.assertEqual(self.output.global_vars['gActivityUntil'],self.w.now+8)
        self.advance(9)
        self.assertEqual(self.output.global_vars['gActivityUntil'],0)
        self.w.emit(s.HUD,918394,'1');self.w.drain(20000)
        self.w.emit(s.HUD,918394,'0');self.w.drain(20000)
        self.assertEqual(self.output.global_vars['gActivityUntil'],0)
        self.assertEqual(self.w.physical,[])

    def test_foreign_activity_is_rejected_and_activity_cannot_change_ready_product(self):
        self.bind();session=self.core.global_vars['gSession']
        self.w.chat(s.SOURCE,-918275,f'MCW|ACTIVITY|{s.BENCH}|{session}|{h.NULL}|1')
        self.w.drain(20000)
        self.assertEqual(self.output.global_vars['gActivityUntil'],0)
        self.prepare();self.submit()
        self.w.emit(s.HUD,918394,'1');self.w.drain(20000)
        self.assertEqual(self.output.global_vars['gActivityUntil'],0)

    def test_component_hover_menu_is_retained(self):
        self.bind();self.core.call('touch_start',[1]);self.w.drain(20000)
        self.assertIn('Text: ON',self.w.dialogs[-1][2])
        self.interface.call('listen',[self.interface.global_vars['gSessionMenu'],'',h.Key(h.OWNER),'Text: ON'])
        self.w.drain(20000)
        self.assertTrue(any(r[2]==-918273 and r[3]=='HOVER|0' for r in self.w.radio))

    def test_player_information_distinguishes_origin_from_collector(self):
        self.ready();recovery.RecoveryTests.other_player(self)
        info=self.interface.call('sessionInfo',[])
        self.assertIn(str(recovery.PLAYER2),info)
        self.assertIn(h.OWNER,info)
        self.assertEqual(self.core.global_vars['gUser'],h.OWNER)

    def test_five_workshop_versions_announce_at_start(self):
        logs=[text for obj,text in self.w.logs if obj==s.BENCH]
        for name in ['Workshop','Workshop_Config','Workshop_Interface','Workshop_HUD','Workshop_Eval','Workshop_Output','Workshop_Storage']:
            revision='0.9.1' if name in ('Workshop','Workshop_Config','Workshop_Interface') else ('0.8.1' if name=='Workshop_Output' else '0.8.0')
            date='2026-11-02' if name in ('Workshop','Workshop_Config','Workshop_Interface') else '2026-10-31'
            if name in ('Workshop_HUD', 'Workshop_Output'):
                revision = '0.8.1' if name == 'Workshop_HUD' else '0.8.2'
                date = '2026-11-09'
            self.assertTrue(any(name+' v'+revision+' ('+date+')' in text for text in logs),name)

if __name__=='__main__':unittest.main(verbosity=2)
