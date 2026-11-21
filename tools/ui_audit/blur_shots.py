"""The blur test's shots (the UI and UX policy's V1): each screenshot given, blurred so only the screen's weight
shows (what stands out first), written beside it as NAME-blur.png. Radius: 1/80 of the image's width.
  .venv/bin/python tools/ui_audit/blur_shots.py SHOT.png [SHOT.png ...]"""
import sys
from PIL import Image, ImageFilter

for path in sys.argv[1:]:
    im = Image.open(path).convert('RGB')
    im.filter(ImageFilter.GaussianBlur(max(2, im.width // 80))).save(path[:-4] + '-blur.png')
