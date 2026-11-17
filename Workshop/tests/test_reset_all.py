"""Owner menu authorization and destructive-reset service calls."""
import copy
import unittest
import test_workshop_split as t


class Endpoint(t.Script):
    def builtin(self,name,args):
        w=self.world
        scripts=['Workshop_HUD','Workshop','Workshop_Config','Workshop_Eval','World_Loader']
        if name=='llGetScriptName': return 'Workshop_HUD'
        if name=='llGetInventoryNumber' and args[0]==10: return len(scripts)
        if name=='llGetInventoryName' and args[0]==10: return scripts[args[1]]
        if name=='llSetScriptState': w.reset_calls.append(('state',*args)); return
        if name=='llResetOtherScript': w.reset_calls.append(('reset',*args)); return
        if name=='llResetScript': w.reset_calls.append(('self',)); return
        if name=='llLinksetDataReset':
            w.reset_calls.append(('clear',))
            for key in list(w.storage):
                if key[0]==self.object: del w.storage[key]
            return 0
        return super().builtin(name,args)


class ResetAll(unittest.TestCase):
    def setUp(self):
        self.base=t.SplitTests(); self.base.setUp(); self.w=self.base.w
        self.w.scripts.remove(self.base.endpoint)
        self.w.reset_calls=[]
        self.endpoint=Endpoint(self.w,'Workshop_HUD.lsl',t.BENCH); self.w.drain(20000)

    def menu(self):
        self.base.core.call('touch_start',[1]); self.w.drain(20000)
        self.assertIn('RESET ALL',self.w.dialogs[-1][2])
        self.base.interface.call('listen',[self.base.interface.global_vars['gSessionMenu'],'',t.h.Key(t.h.OWNER),'RESET ALL'])
        self.w.drain(20000)
        self.assertEqual(self.w.dialogs[-1][2],['ERASE ALL','Cancel'])

    def confirm(self,choice='ERASE ALL',user=None):
        self.endpoint.call('listen',[self.endpoint.global_vars['gResetChannel'],'',user or t.h.Key(t.h.OWNER),choice])
        self.w.drain(20000)

    def test_owner_reset_clears_only_workshop_data_and_restarts_root_scripts(self):
        self.base.bind(); self.base.prepare()
        self.w.storage[t.BENCH,'ws:output']='pending product'
        stock=copy.deepcopy(self.w.stock)
        hud={key:value for key,value in self.w.storage.items() if key[0]==t.HUD}
        self.menu(); self.confirm()
        self.assertFalse(any(key[0]==t.BENCH for key in self.w.storage))
        self.assertEqual({key:value for key,value in self.w.storage.items() if key[0]==t.HUD},hud)
        self.assertEqual(self.w.stock,stock)
        self.assertEqual(self.w.physical,[])
        self.assertEqual(self.w.reset_calls[:4],[('state',name,0) for name in ['Workshop','Workshop_Config','Workshop_Eval','World_Loader']])
        self.assertEqual(self.w.reset_calls[4],('clear',))
        self.assertEqual(self.w.reset_calls[-1],('self',))
        self.assertIn(('reset','World_Loader'),self.w.reset_calls)

    def test_cancel_does_not_clear_or_restart(self):
        self.menu(); before=copy.deepcopy(self.w.storage)
        self.confirm('Cancel')
        self.assertEqual(self.w.storage,before)
        self.assertEqual(self.w.reset_calls,[])

    def test_foreign_user_cannot_request_or_confirm_reset(self):
        self.w.emit(t.BENCH,970216,'CONFIRM_RESET',t.SOURCE); self.w.drain(20000)
        self.assertEqual(self.endpoint.global_vars['gResetListen'],0)
        self.menu(); self.confirm(user=t.SOURCE)
        self.assertEqual(self.w.reset_calls,[])

    def test_owner_has_reset_option_while_endpoint_and_core_are_faulted(self):
        self.base.bind()
        self.endpoint.global_vars['gFault']=True
        self.base.core.global_vars['gFault']=True
        self.menu()
        self.assertNotEqual(self.endpoint.global_vars['gResetListen'],0)

    def test_expired_confirmation_cannot_reset(self):
        self.menu(); self.endpoint.call('timer',[])
        self.confirm()
        self.assertEqual(self.w.reset_calls,[])


if __name__=='__main__': unittest.main()
