import base64, os, sys, time, unittest
import test_windows as T
class S(T.Windows):
    def test_scratch(self):
        self.join('sjoin.uia')
        self.check('s0.uia', ['wait\t~Sample sheet\t60', 'press\tSelect tags\t0x10', 'sleep\t500', 'press\tSearch equipment by KKS code or description\t0x10', 'sleep\t500', 'press\tSelect tags\t0x10', 'sleep\t800'])
        self.screenshot('scroll-' + os.environ.get('WHICH', 'x'))
        self.leave()
if __name__ == '__main__':
    unittest.main(defaultTest='S.test_scratch', argv=['x'])
