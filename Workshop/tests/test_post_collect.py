"""Actual Workshop/HUD path with a deliberately lost final radio confirmation."""
import unittest
import test_p3_recovery as recovery
import test_workshop_split as s


class PostCollectRecoveryTests(recovery.RecoveryTests):
    def test_lost_output_closed_is_recovered_by_status_without_second_delivery(self):
        self.ready()
        original = self.endpoint.builtin
        def drop_final(name, args):
            if name == 'llWhisper' and 'MCW|OUTPUT_CLOSED|' in str(args[1]):
                return
            return original(name, args)
        self.endpoint.builtin = drop_final
        self.w.containers = {s.CONTAINER: 0}
        self.request('TRANSFER', s.CONTAINER); self.advance(2)
        self.assertEqual(len(self.w.physical), 1)
        self.assertEqual(self.output.global_vars['gPhase'], 'DONE')
        self.assertEqual(self.link.global_vars['gPhase'], 'OUTPUT')
        self.endpoint.builtin = original
        self.link.call('timer', []); self.w.drain(20000)
        self.assertEqual(self.link.global_vars['gPhase'], 'IDLE')
        self.assertEqual(self.core.global_vars['gPhase'], 'BOUND')
        self.assertEqual(len(self.w.physical), 1)
        self.assertTrue(any(r[0] == s.HUD and r[2] == 918287 for r in self.w.replies))


if __name__ == '__main__': unittest.main(verbosity=2)
