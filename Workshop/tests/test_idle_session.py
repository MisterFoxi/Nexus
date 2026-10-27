import unittest
import test_workshop_split as s

class IdleSessionTests(unittest.TestCase):
    setUp=s.SplitTests.setUp
    bind=s.SplitTests.bind
    add=s.SplitTests.add
    here=s.SplitTests.here
    prepare=s.SplitTests.prepare
    submit=s.SplitTests.submit

    def menu(self,choice):
        self.core.call('touch_start',[1]);self.w.drain(20000)
        self.assertEqual(self.w.dialogs[-1][2][:2],['Resume','Exit'])
        self.core.call('listen',[self.core.global_vars['gSessionMenu'],'',s.h.Key(s.h.OWNER),choice])
        self.w.drain(20000)

    def test_own_idle_session_can_exit_without_clearing_linkset_data(self):
        self.bind();self.menu('Exit')
        self.assertEqual(self.core.global_vars['gPhase'],'FREE')
        self.assertEqual(self.link.global_vars['gSession'],s.h.NULL)
        self.assertNotIn((s.HUD,'mc:workshop:session'),self.w.storage)

    def test_resume_keeps_the_same_session(self):
        self.bind();lease=self.core.global_vars['gSession'];self.menu('Resume')
        self.assertEqual(self.core.global_vars['gSession'],lease)
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')

    def test_exit_returns_unused_units_before_releasing_workshop(self):
        self.bind();self.add();self.menu('Exit')
        self.assertEqual(self.w.stock[s.SOURCE],[10,0])
        self.assertEqual(self.core.global_vars['gPhase'],'FREE')

    def test_exit_commits_used_units_without_another_debit(self):
        self.bind();self.prepare();self.menu('Exit')
        self.assertEqual(self.w.stock[s.SOURCE],[9,0])
        self.assertEqual(self.core.global_vars['gPhase'],'FREE')

    def test_old_menu_cannot_release_a_submitted_treatment(self):
        self.bind();self.prepare()
        self.core.call('touch_start',[1]);self.w.drain(20000)
        channel=self.core.global_vars['gSessionMenu'];self.submit()
        self.core.call('listen',[channel,'',s.h.Key(s.h.OWNER),'Exit']);self.w.drain(20000)
        self.assertEqual(self.core.global_vars['gPhase'],'OUTPUT')
        self.assertEqual(self.w.stock[s.SOURCE],[9,1])

    def test_foreign_exit_request_is_ignored(self):
        self.bind();lease=self.core.global_vars['gSession']
        self.w.chat(s.SOURCE,-918275,f'MCW|EXIT_REQUEST|{s.HUD}|{lease}|{s.h.NULL}')
        self.w.drain(20000)
        self.assertEqual(self.link.global_vars['gPhase'],'IDLE')
        self.assertEqual(self.core.global_vars['gPhase'],'BOUND')

if __name__=='__main__':unittest.main(verbosity=2)
