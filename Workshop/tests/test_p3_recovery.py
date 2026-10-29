"""P3 integration against actual LSL ASTs, including a different HUD owner."""
import json
import unittest
import uuid
import test_workshop_split as s

h=s.h
PLAYER2=h.Key('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
HUD2=h.Key('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
BLANK2=h.Key('cccccccc-cccc-cccc-cccc-cccccccccccc')

class OtherHUD(s.Script):
    def builtin(self,name,args):
        if name=='llGetOwner': return PLAYER2
        return super().builtin(name,args)

class RecoveryTests(s.SplitTests):
    # Existing suite also runs with the new implementation.
    def ready(self):
        self.bind();self.prepare();self.submit();self.advance(1)

    def other_player(self):
        self.w.owners[HUD2]=PLAYER2;self.w.owners[BLANK2]=PLAYER2
        self.other=OtherHUD(self.w,'MC_Workshop_Link.lsl',HUD2)
        self.w.touch_owner=PLAYER2
        self.core.call('touch_start',[1]);self.w.drain(20000)
        self.assertEqual(self.other.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.other.global_vars['gRun'],self.core.global_vars['gRun'])

    def request(self,verb,target=h.NULL,script=None,ticket=None):
        script=script or self.link
        ticket=ticket or h.Key(str(uuid.uuid4()))
        command='DISCARD' if verb=='OUTPUT_DISCARD' else f'TRANSFER|{target}'
        script.call('link_message',[1,918390,command,ticket]);self.w.drain(20000)
        return ticket

    def test_ready_closes_ingredients_before_any_recipient_exists(self):
        self.ready()
        self.assertEqual(self.w.stock[s.SOURCE],[9,0])
        self.assertEqual(self.w.physical,[])
        self.assertEqual(self.core.global_vars['gPhase'],'PRODUCT')
        self.assertEqual(self.link.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.output.global_vars['gQuantity'],5)
        self.assertEqual(self.w.dialogs,[])

    def test_different_player_touches_collects_and_becomes_current_session(self):
        self.ready();self.other_player()
        self.w.containers={BLANK2:0,s.CONTAINER:0}
        self.request('TRANSFER',BLANK2,self.other);self.advance(2)
        self.assertEqual(len(self.w.physical),1)
        self.assertIn(str(BLANK2),self.w.physical[0])
        self.assertEqual(self.core.global_vars['gUser'],PLAYER2)
        self.assertEqual(self.core.global_vars['gHUD'],HUD2)
        self.assertEqual(self.other.global_vars['gPhase'],'IDLE')
        self.assertEqual(self.link.global_vars['gSession'],h.NULL)
        self.assertEqual(self.w.stock[s.SOURCE],[9,0])

    def test_old_collector_cannot_transfer_or_discard_after_new_touch(self):
        self.ready();old=self.link.global_vars['gSession'];run=self.link.global_vars['gRun']
        self.other_player()
        self.w.chat(s.HUD,-918275,f'MCW|OUTPUT_DISCARD|{s.BENCH}|{old}|{run}|{uuid.uuid4()}|{h.NULL}')
        self.w.drain(20000)
        self.assertEqual(self.output.global_vars['gQuantity'],5)
        self.assertEqual(self.w.physical,[])

    def test_discard_product_by_other_player_never_commits_their_basket(self):
        self.ready();self.other_player();before=list(self.w.receipts)
        self.request('OUTPUT_DISCARD',script=self.other)
        self.assertEqual(self.output.global_vars['gQuantity'],0)
        self.assertEqual(self.output.global_vars['gPhase'],'DONE')
        self.assertEqual(self.w.receipts,before)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.assertEqual(self.other.global_vars['gPhase'],'IDLE')
        self.assertEqual(self.w.physical,[])

    def test_only_selected_container_is_filled_and_capacity_preserves_remainder(self):
        self.ready();self.w.containers={s.CONTAINER:2,s.SOURCE2:0}
        self.request('TRANSFER',s.CONTAINER);self.advance(2)
        self.assertEqual(len(self.w.physical),1)
        self.assertEqual(self.w.physical[0].split('|')[3],'2')
        self.assertEqual(self.output.global_vars['gQuantity'],3)
        self.assertEqual(self.link.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.core.global_vars['gPhase'],'PRODUCT')

    def test_missing_or_foreign_recipient_does_not_consume_product(self):
        self.ready();self.w.containers={BLANK2:0};self.w.owners[BLANK2]=PLAYER2
        self.request('TRANSFER',BLANK2);self.advance(2)
        self.assertEqual(self.output.global_vars['gQuantity'],5)
        self.assertEqual(self.link.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.w.physical,[])

    def test_exact_retry_after_lost_response_never_repeats_delivery(self):
        self.ready();self.w.containers={s.CONTAINER:2}
        self.request('TRANSFER',s.CONTAINER)
        wire=self.link.global_vars['gWire']
        self.advance(2);before=list(self.w.physical)
        self.w.chat(s.HUD,-918275,wire);self.w.drain(20000)
        self.assertEqual(self.w.physical,before)
        self.assertEqual(self.output.global_vars['gQuantity'],3)

    def test_pending_origin_commit_does_not_prevent_other_player_discard(self):
        self.w.drop_commit=True;self.ready();self.other_player()
        self.assertEqual(self.core.global_vars['gPhase'],'SETTLING')
        self.request('OUTPUT_DISCARD',script=self.other)
        self.assertEqual(self.output.global_vars['gPhase'],'DONE')
        self.assertEqual(self.core.global_vars['gPhase'],'SETTLING')
        # A new craft remains locked, but the product has been discarded independently.
        receipt=self.w.receipts[-1];before=len(self.w.receipts)
        self.w.chat(*receipt);self.w.drain(20000)
        self.assertEqual(len(self.w.receipts),before)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.assertEqual(self.other.global_vars['gPhase'],'IDLE')

    def test_resets_preserve_current_collector_and_product_remainder(self):
        self.ready();self.other_player();self.w.containers={BLANK2:2}
        self.request('TRANSFER',BLANK2,self.other);self.advance(2)
        self.restart('output','Workshop_Output.lsl');self.restart('core','Workshop.lsl')
        self.assertEqual(self.core.global_vars['gCollectorHUD'],HUD2)
        self.assertEqual(self.output.global_vars['gQuantity'],3)
        self.assertEqual(len(self.w.physical),1)

    def test_reset_after_saved_quantity_finishes_receipt_without_repeating_config(self):
        self.ready();self.w.containers={s.CONTAINER:2}
        self.request('TRANSFER',s.CONTAINER);self.advance(2)
        data=json.loads(self.w.storage[s.BENCH,'ws:output']);data[3]='RECEIPTING'
        self.w.storage[s.BENCH,'ws:output']=json.dumps(data)
        before=list(self.w.physical)
        self.restart('output','Workshop_Output.lsl')
        self.assertEqual(self.w.physical,before)
        self.assertEqual(self.output.global_vars['gQuantity'],3)
        self.assertEqual(self.output.global_vars['gPhase'],'WAIT_CONTAINER')

    def test_retry_lost_terminal_responses_closes_hud_without_another_delivery(self):
        self.ready();self.w.containers={s.CONTAINER:0}
        self.request('TRANSFER',s.CONTAINER);wire=self.link.global_vars['gWire']
        self.w.scripts.remove(self.link)
        self.advance(2)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.w.scripts.append(self.link)
        self.w.chat(s.HUD,-918275,wire);self.w.drain(20000)
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')
        self.assertEqual(len(self.w.physical),1)

    def test_origin_hud_absent_collection_works_and_late_closure_is_still_required(self):
        self.bind();self.prepare();self.submit()
        self.w.scripts.remove(self.link);self.advance(1)
        self.other_player();self.request('OUTPUT_DISCARD',script=self.other)
        self.assertEqual(self.core.global_vars['gPhase'],'SETTLING')
        self.assertEqual(self.w.stock[s.SOURCE],[9,1])
        self.w.scripts.append(self.link)
        self.link.call('choose',['RETRY']);self.w.drain(20000)
        self.assertEqual(self.w.stock[s.SOURCE],[9,0])
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.assertEqual(self.other.global_vars['gPhase'],'IDLE')

if __name__=='__main__': unittest.main(verbosity=2)
