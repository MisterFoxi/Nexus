"""Actual Workshop/HUD ASTs; LSL services and physical objects are test doubles."""
import base64
import hashlib
import json
import math
import re
import unittest
import uuid
from urllib.parse import quote, unquote
import lsl_runtime as h

BENCH=h.Key('22222222-2222-2222-2222-222222222222')
HUD=h.Key('33333333-3333-3333-3333-333333333333')
SOURCE=h.Key('44444444-4444-4444-4444-444444444444')
SOURCE2=h.Key('55555555-5555-5555-5555-555555555555')
CONTAINER=h.Key('66666666-6666-6666-6666-666666666666')
RUN=h.Key('77777777-7777-7777-7777-777777777777')

class World(h.World):
    def __init__(self, genre='cutting_board', keep=0):
        super().__init__()
        self.config=[f'Genre={genre}','CookTime=1','FluxAbs=0','Batch=1000,1000,1000,1000',
                     'NMax=99','SingleIngredient=1',f'AllowKeep={keep}','Action=fab.grind:hud']
        self.replies=[];self.dialogs=[];self.params=[];self.owners={}
        self.containers={};self.stock={SOURCE:[10,0],SOURCE2:[10,0]}
        self.query=0;self.drop_commit=False;self.receipts=[];self.touch_owner=h.Key(h.OWNER)
        self.physical=[]
        self.pause_codes=set();self.pause_build=False
        self.tokens={
            'meta.taxonomy':14,'meta.stage':10,'mint':16,'leaf':11,'chopped':28,
            'meta.organ':56,'act.nervous':5,'fab.grind':22,'root':17,'plant':23,
            'cuttable':27,'leaf_plant':15,'powder':12}
        for name,number in self.tokens.items():
            self.storage[BENCH,'tok:'+name]=str(number)
            self.storage[BENCH,'tok:#'+str(number)]=name
        self.storage[BENCH,'tax:16:toks']='16^15^27'
        self.storage[BENCH,'tax:16:trait']='5:2'
        self.storage[BENCH,'tax:16:organs']='11^17'
        law=f'law:{genre}:fixture:'
        for field,value in {'when':'14=15^10=11','verdict':'0','seq':'0','do':'10=28^qty*5'}.items():
            self.storage[BENCH,law+field]=value

    def emit(self, obj, code, text='', ticket=h.NULL):
        for script in list(self.scripts):
            if script.object==obj and 'link_message' in script.functions:
                self.queue.append((script,'link_message',[1,code,text,h.Key(ticket)]))

    def chat(self, source, channel, text):
        self.radio.append((source,None,channel,text))
        for script in list(self.scripts):
            if script.object!=source and 'listen' in script.functions:
                self.queue.append((script,'listen',[channel,'',h.Key(source),text]))

class Script(h.Script):
    def builtin(self,name,a):
        w=self.world
        if name=='llGetFreeMemory':return 50000
        if name=='llGetUnixTime':return int(w.now)
        if name=='llGetOwnerKey':return h.Key(w.owners.get(a[0],h.OWNER))
        if name=='llGetInventoryNumber':return 1 if a[0]==7 else 0
        if name=='llGetInventoryName':return 'bench_config'
        if name=='llGetInventoryType':return 7 if a[0]=='bench_config' else -1
        if name=='llGetNotecardLine':
            w.query+=1;query=h.Key(str(uuid.uuid4()))
            data=w.config[a[1]] if a[1]<len(w.config) else '\n\n\n'
            w.queue.append((self,'dataserver',[query,data]));return query
        if name=='llSubStringIndex':return a[0].find(a[1])
        if name=='llStringLength':return len(a[0])
        if name=='llStringToBase64':return base64.b64encode(a[0].encode()).decode()
        if name=='llMD5String':return hashlib.md5((a[0]+':'+str(a[1])).encode()).hexdigest()
        if name=='llGetSubString':
            text,start,end=a
            if start<0:start+=len(text)
            if end<0:end+=len(text)
            return text[start:end+1]
        if name=='llParseString2List':return [v for v in re.split('|'.join(map(re.escape,a[1])),a[0]) if v]
        if name=='llEscapeURL':return quote(a[0],safe='')
        if name=='llUnescapeURL':return unquote(a[0])
        if name=='llRound':return int(math.floor(a[0]+.5))
        if name=='llFloor':return int(math.floor(a[0]))
        if name=='llFrand':return 0.0
        if name=='llJsonValueType':
            try:
                value=json.loads(a[0])
                for key in a[1]:value=value[key]
            except (ValueError,TypeError,IndexError,KeyError):return '\ufdd0'
            return {list:'\ufdd2',dict:'\ufdd1',str:'\ufdd4',int:'\ufdd3',float:'\ufdd3',type(None):'\ufdd5'}.get(type(value),'\ufdd6' if value else '\ufdd7')
        if name=='llLinksetDataFindKeys':
            keys=sorted(k for obj,k in w.storage if obj==self.object and re.search(a[0],k))
            return keys[a[1]:] if a[2]==0 else keys[a[1]:a[1]+a[2]]
        if name=='llLinksetDataDelete':
            if self.object in w.fail_storage or (self.object,a[0]) in w.fail_storage:return 1
            return 0 if w.storage.pop((self.object,a[0]),None) is not None else 4
        if name=='llDetectedKey':return w.touch_owner
        if name=='llDialog':w.dialogs.append(a);return
        if name in ('llParticleSystem','llLoopSound','llPlaySound','llStopSound','llPreloadSound'):return
        if name=='llGetAttached':return 31
        if name=='llGetPermissions':return 0
        if name=='llMessageLinked':
            w.replies.append((self.object,*a))
            if a[1] in w.pause_codes or (w.pause_build and a[1]==970214 and self.global_vars.get('gPhase')=='BUILDING'):
                return
            result=super().builtin(name,a)
            if self.object==HUD and a[1:3]==[918372,'SNAPSHOT']:
                w.emit(HUD,918373,'OK|4.75|0',a[3])
            return result
        if name=='llWhisper':
            result=super().builtin(name,a)
            channel,text=a
            if channel==-918273 and text=='PING':
                for source,capacity in w.containers.items():w.chat(source,channel,f'BLANK|{source}|{capacity}')
            fields=text.split('|')
            if fields[0] in ('CONFIG','GIVE'):w.physical.append(text)
            if fields[0]=='MC' and fields[1] in ('TAKE','RETURN','COMMIT'):
                verb,source,request,amount=fields[1:];amount=int(amount);stock=w.stock[source]
                if verb=='TAKE':stock[0]-=amount;stock[1]+=amount
                elif verb=='RETURN':stock[0]+=amount;stock[1]-=amount
                else:stock[1]-=amount
                receipt=f'MC|RESULT|{source}|{request}|{verb}|OK|{stock[0]}'
                w.receipts.append((source,channel,receipt))
                if not (verb=='COMMIT' and w.drop_commit):w.chat(source,channel,receipt)
            return result
        return super().builtin(name,a)

class SplitTests(unittest.TestCase):
    def setUp(self):
        self.w=World()
        self.core=Script(self.w,'Workshop.lsl',BENCH)
        self.endpoint=Script(self.w,'Workshop_HUD.lsl',BENCH)
        self.evaluator=Script(self.w,'Workshop_Eval.lsl',BENCH)
        self.output=Script(self.w,'Workshop_Output.lsl',BENCH)
        self.storage=Script(self.w,'Workshop_Storage.lsl',BENCH)
        self.selected=Script(self.w,'MC_Selected_Controller.lsl',HUD)
        self.relay=Script(self.w,'MC_Transactions.lsl',HUD)
        self.link=Script(self.w,'MC_Workshop_Link.lsl',HUD)
        self.w.drain(20000)

    def bind(self):
        self.core.call('touch_start',[1]);self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')

    def here(self,source=SOURCE,name='Mint',stage='leaf'):
        return f'HERE|{source}|{name}|10|1|86400|mint|{stage}|act.nervous=2|5|950|Mesh|leaf'

    def add(self,source=SOURCE,**kwargs):
        self.w.emit(HUD,918300,self.here(source,**kwargs),source);self.w.drain(20000)

    def prepare(self,source=SOURCE):
        self.add(source)
        self.selected.call('basketAction',['CRAFT_STARTED',RUN]);self.w.drain(20000)

    def submit(self,choice='CONTAINER'):
        self.w.emit(HUD,918370,choice,RUN);self.w.drain(20000)

    def advance(self,seconds):
        self.w.now+=seconds
        self.output.call('timer',[]);self.core.call('timer',[]);self.w.drain(20000)

    def collect(self):
        self.output.call('listen',[self.output.global_vars['gMenuChannel'],'',h.Key(h.OWNER),'Collect'])
        self.w.drain(20000)

    def restart(self,attr,name):
        self.w.scripts.remove(getattr(self,attr));setattr(self,attr,Script(self.w,name,BENCH));self.w.drain(20000)

    def test_real_hud_handshake_spool_evaluation_container_and_stock_closure(self):
        self.bind();self.prepare();self.add(SOURCE2)
        # Sources may be added only before Start; begin this case with one held source.
        self.submit()
        self.assertEqual(self.core.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.link.global_vars['gPhase'],'WAIT_RESULT')
        self.assertEqual(self.w.stock[SOURCE],[9,1])
        self.assertEqual(self.w.physical,[])
        self.w.containers[CONTAINER]=0
        self.advance(1);self.advance(2);self.collect()
        self.assertEqual(len(self.w.physical),1)
        self.assertTrue(self.w.physical[0].startswith('CONFIG|'))
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')
        self.assertEqual(self.w.stock[SOURCE],[9,0])
        self.assertEqual(self.core.global_vars['gReady'],15)

    def test_multiple_sources_form_existing_name_stage_batch_without_core_copy(self):
        self.bind();self.add();self.add(SOURCE2)
        self.selected.call('basketAction',['CRAFT_STARTED',RUN]);self.w.drain(20000);self.submit()
        cached=json.loads(self.w.storage[BENCH,'ws:eval:result'])[1].split('|')
        self.assertEqual(cached[3],'10')
        self.assertNotIn('gIng',self.core.global_vars)
        self.assertNotIn('gPicks',self.core.global_vars)
        self.assertNotIn('gRec',self.output.global_vars)
        self.assertNotIn('gKept',self.storage.global_vars)

    def test_duplicate_end_and_output_start_never_duplicate_physical_delivery(self):
        self.bind();self.prepare();self.submit();run=self.core.global_vars['gRun']
        self.w.containers[CONTAINER]=0;self.advance(1);self.advance(2);self.collect()
        before=list(self.w.physical)
        self.w.emit(BENCH,970220,f'START|CONTAINER|{h.OWNER}',run)
        self.w.emit(BENCH,970210,f'MCW|END|{BENCH}|{self.core.global_vars["gSession"]}|{run}|1',HUD)
        self.w.drain(20000)
        self.assertEqual(self.w.physical,before)

    def test_no_container_keeps_output_and_player_lock_until_collection(self):
        self.bind();self.prepare();self.submit();self.advance(1);self.advance(2);self.collect()
        self.assertEqual(self.output.global_vars['gPhase'],'WAIT_CONTAINER')
        self.assertEqual(self.link.global_vars['gPhase'],'WAIT_RESULT')
        self.assertEqual(self.w.stock[SOURCE],[9,1])
        self.w.containers[CONTAINER]=0
        self.core.call('touch_start',[1]);self.w.drain(20000);self.advance(2);self.collect()
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')

    def test_partial_container_delivery_retains_remainder_and_never_replays_first(self):
        self.bind();self.prepare();self.submit();self.w.containers[CONTAINER]=2
        self.advance(1);self.advance(2);self.collect()
        self.assertEqual(self.output.global_vars['gQuantity'],3)
        self.assertEqual(self.link.global_vars['gPhase'],'WAIT_RESULT')
        self.restart('output','Workshop_Output.lsl')
        self.w.containers={SOURCE2:0}
        self.core.call('touch_start',[1]);self.w.drain(20000);self.advance(2);self.collect()
        self.assertEqual(len(self.w.physical),2)
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')

    def test_ambiguous_physical_dispatch_reset_holds_without_retry(self):
        self.bind();self.prepare();self.submit()
        data=json.loads(self.w.storage[BENCH,'ws:output']);data[3]='DISPATCH_CONFIG'
        self.w.storage[BENCH,'ws:output']=json.dumps(data)
        self.restart('output','Workshop_Output.lsl')
        self.assertEqual(self.output.global_vars['gPhase'],'HOLD')
        self.assertEqual(self.w.physical,[])
        self.assertEqual(self.w.stock[SOURCE],[9,1])

    def test_core_reset_restores_session_and_pending_output_without_recreating_product(self):
        self.bind();self.prepare();self.submit()
        run=self.core.global_vars['gRun'];cached=self.w.storage[BENCH,'ws:eval:result']
        self.restart('core','Workshop.lsl')
        self.assertEqual(self.core.global_vars['gRun'],run)
        self.assertEqual(self.w.storage[BENCH,'ws:eval:result'],cached)
        self.assertEqual(self.w.physical,[])

    def test_stock_ack_pending_does_not_replay_output_after_core_reset(self):
        self.bind();self.prepare();self.submit();self.w.containers[CONTAINER]=0;self.w.drop_commit=True
        self.advance(1);self.advance(2);self.collect()
        self.assertEqual(self.core.global_vars['gPhase'],'SETTLING')
        self.restart('core','Workshop.lsl');self.advance(5)
        self.assertEqual(len(self.w.physical),1)
        self.w.chat(*self.w.receipts[-1]);self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')

    def test_storage_import_is_progressive_preserves_records_across_reset(self):
        self.w.storage[BENCH,'state:kept']='Mint|2|mint|chopped|act.nervous=2|100|90\nOther|3|mint|leaf||0|0'
        self.restart('storage','Workshop_Storage.lsl')
        self.assertNotIn((BENCH,'state:kept'),self.w.storage)
        records=[v for (obj,key),v in self.w.storage.items() if obj==BENCH and key.startswith('ws:kept:')]
        self.assertEqual(len(records),2)
        self.restart('storage','Workshop_Storage.lsl')
        self.assertEqual(len([key for obj,key in self.w.storage if obj==BENCH and key.startswith('ws:kept:')]),2)

    def test_foreign_or_stale_session_cannot_submit_or_release(self):
        self.bind();lease=self.core.global_vars['gSession']
        self.w.chat(SOURCE,-918275,f'MCW|EXIT|{BENCH}|{lease}|{RUN}')
        self.w.chat(HUD,-918275,f'MCW|EXIT|{BENCH}|{RUN}|{RUN}')
        self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')

    def test_rejected_evaluation_does_not_commit_sources(self):
        self.bind();self.prepare()
        self.w.storage.pop((BENCH,'law:cutting_board:fixture:when'))
        self.submit()
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')
        self.assertEqual(self.w.stock[SOURCE],[9,1])
        self.assertEqual(self.w.physical,[])

    def test_second_preparation_reuses_session_and_evaluates_a_new_run(self):
        self.bind();self.prepare();self.submit();self.w.containers[CONTAINER]=0
        self.advance(1);self.advance(2);self.collect()
        first=self.core.global_vars['gRun'];lease=self.core.global_vars['gSession']
        self.prepare();self.submit()
        self.assertNotEqual(self.core.global_vars['gRun'],first)
        self.assertEqual(self.core.global_vars['gSession'],lease)
        self.assertEqual(self.core.global_vars['gPhase'],'OUTPUT')
        self.advance(1);self.advance(2);self.collect()
        self.assertEqual(len(self.w.physical),2)
        self.assertEqual(self.w.stock[SOURCE],[8,0])

    def test_input_reset_during_group_build_restarts_derived_cache_only(self):
        self.bind();self.prepare();self.w.pause_build=True;self.submit()
        self.assertEqual(self.core.global_vars['gPhase'],'BUILDING')
        self.assertIn((BENCH,'ws:in:row:0'),self.w.storage)
        self.w.pause_build=False;self.restart('endpoint','Workshop_HUD.lsl')
        self.assertEqual(self.core.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(json.loads(self.w.storage[BENCH,'ws:eval:result'])[1].split('|')[3],'5')

    def test_evaluator_reset_before_result_reads_the_stored_groups_again(self):
        self.bind();self.prepare();self.w.pause_codes.add(970203);self.submit()
        self.assertEqual(self.core.global_vars['gPhase'],'EVALUATING')
        self.w.pause_codes.clear();self.restart('evaluator','Workshop_Eval.lsl')
        self.assertEqual(self.core.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.w.physical,[])

    def test_yield_uses_existing_cut_give_output_for_each_held_source_unit(self):
        self.bind();self.add();self.add()
        self.selected.call('basketAction',['CRAFT_STARTED',RUN]);self.w.drain(20000)
        self.w.storage[BENCH,'law:cutting_board:fixture:verdict']='2'
        self.w.storage[BENCH,'law:cutting_board:fixture:do']='give=11^give=17'
        self.submit();self.advance(1)
        self.assertEqual(len(self.w.physical),2)
        self.assertTrue(all(item==f'GIVE|{SOURCE}|leaf^root' for item in self.w.physical))
        self.assertEqual(self.w.stock[SOURCE],[8,0])

    def test_keep_is_durable_and_idempotent_for_an_authorized_workshop(self):
        self.w.config[0]='Genre=mortar';self.w.config[6]='AllowKeep=1'
        for key,value in list(self.w.storage.items()):
            obj,name=key
            if obj==BENCH and name.startswith('law:cutting_board:'):
                self.w.storage[BENCH,name.replace('law:cutting_board:','law:mortar:')]=value
        self.core.call('loadConfig',[]);self.evaluator.call('loadConfig',[])
        self.w.scripts.remove(self.link)
        self.link=Script(self.w,'MC_Workshop_Link.lsl',HUD,{'HUD_KIND':'mortar'})
        self.w.drain(20000)
        self.bind();self.prepare();self.submit('KEEP');self.advance(1)
        run=self.core.global_vars['gRun']
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')
        self.assertIn((BENCH,'ws:kept:'+run),self.w.storage)
        first=self.w.storage[BENCH,'ws:kept:'+run]
        self.w.emit(BENCH,970230,'KEEP',run);self.w.drain(20000)
        self.assertEqual(self.w.storage[BENCH,'ws:kept:'+run],first)

    def test_many_input_groups_stay_out_of_core_and_endpoint_script_lists(self):
        self.w.config[5]='SingleIngredient=0';self.core.call('loadConfig',[]);self.w.drain(20000);self.bind()
        lease=self.core.global_vars['gSession']
        self.w.chat(HUD,-918275,f'MCW|BEGIN|{BENCH}|{lease}|{RUN}|CONTAINER|4.75|0');self.w.drain(20000)
        for index in range(64):
            source=h.Key(str(uuid.uuid4()))
            here=self.here(source,name='Plant'+str(index))
            self.w.chat(HUD,-918275,f'MCW|ROW|{BENCH}|{lease}|{RUN}|{index}|{source}|1|{quote(here,safe="")}')
            self.w.drain(20000)
        self.w.chat(HUD,-918275,f'MCW|END|{BENCH}|{lease}|{RUN}|64');self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.endpoint.global_vars['gGroups'],64)
        self.assertEqual([len(v) for v in self.core.global_vars.values() if isinstance(v,list)],[1])
        self.assertFalse(any(isinstance(v,list) for v in self.endpoint.global_vars.values()))

    def test_memory_query_reaches_all_five_subsystems_with_no_treatment(self):
        self.w.emit(BENCH,970290);self.w.drain(20000)
        messages=[text for obj,text in self.w.logs if obj==BENCH and 'Free:' in text]
        self.assertEqual(len(messages),5)

class EvalParityTests(unittest.TestCase):
    def result(self,filename,groups,header='',stream=False,mode='react'):
        w=World()
        if mode=='yield':
            w.storage[BENCH,'law:cutting_board:fixture:verdict']='2'
            w.storage[BENCH,'law:cutting_board:fixture:do']='give=11^give=17'
        if mode=='danger':
            w.storage[BENCH,'law:cutting_board:fixture:verdict']='1'
            w.storage[BENCH,'law:cutting_board:fixture:do']='10=28^qty*0.6^eff*0.5^5*2'
        script=Script(w,filename,BENCH);w.drain(20000)
        if stream:
            w.storage[BENCH,'ws:input']=json.dumps([RUN,'READY',len(groups),len(groups),0,''])
            for index,group in enumerate(groups):w.storage[BENCH,'ws:in:group:'+str(index)]='|'.join(map(str,group))
            script.call('link_message',[1,970202,header,RUN]);w.drain(20000)
            return json.loads(w.storage[BENCH,'ws:eval:result'])[1],w,script
        body='\n'.join('|'.join(map(str,g)) for g in groups)
        script.call('link_message',[1,970200,header+'\n\n'+body,RUN]);w.drain(20000)
        return [a[3] for a in w.replies if a[2]==970201][-1],w,script

    def test_progressive_evaluation_matches_original_arithmetic_and_rule_resolution(self):
        for mode in ['react','danger','yield']:
            for count in [1,2,7]:
                with self.subTest(mode=mode,count=count):
                    groups=[['Mint',count,'mint','leaf','act.nervous=2',86400,750,'leaf'],
                            ['Other',2,'mint','leaf','act.nervous=-1',3600,500,'root']]
                    old,_,_=self.result('Workshop_Eval.before.lsl',groups,'fab.grind=5',mode=mode)
                    new,_,_=self.result('Workshop_Eval.lsl',groups,'fab.grind=5',stream=True,mode=mode)
                    self.assertEqual(new,old)

    def test_duplicate_stream_request_returns_same_cached_random_result(self):
        groups=[['Mint',1,'mint','leaf','act.nervous=2',86400,750,'leaf']]
        result,w,script=self.result('Workshop_Eval.lsl',groups,stream=True)
        del w.storage[BENCH,'law:cutting_board:fixture:when']
        script.call('link_message',[1,970202,'',RUN]);w.drain(20000)
        self.assertEqual(json.loads(w.storage[BENCH,'ws:eval:result'])[1],result)

if __name__=='__main__':unittest.main(verbosity=2)
