"""tests/jxl_header.py, which the e2e suites use to check a stored photo's size (decision 0074)."""
import base64, os, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
from jxl_header import jxl_size  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


class JxlHeader(unittest.TestCase):
    def test_small(self):   # common.js's 1 x 1 probe image (the "small" size form)
        self.assertEqual(jxl_size(base64.b64decode('/woAEBAJCAABACgASxiLFcJJQU5/AA==')), (1, 1))

    def test_course_picture(self):   # a 1600 x 1200 picture (4:3, written as a ratio)
        with open(os.path.join(REPO, 'data', 'courses', 'ppt-01.jxl'), 'rb') as f:
            self.assertEqual(jxl_size(f.read()), (1600, 1200))

    def test_not_jxl(self):
        for blob in (b'\x89PNG\r\n\x1a\n' + bytes(16), b'\x00\x00\x00\x0cJXL \r\n\x87\n' + bytes(16)):
            with self.assertRaises(ValueError):
                jxl_size(blob)


if __name__ == '__main__':
    unittest.main()
