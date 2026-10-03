"""A short video of a QR code, as a webcam would see it (grey background, slight blur and noise), for the camera
scanning tests (decision 0039): make_qr_video.py OUT.mp4 TEXT. Needs OpenCV (the importer's .venv) and ffmpeg."""
import subprocess, sys, tempfile, os
import cv2, numpy as np

out, text = sys.argv[1], sys.argv[2]
q = cv2.QRCodeEncoder_create().encode(text)
q = cv2.resize(q, (q.shape[1] * 8, q.shape[0] * 8), interpolation=cv2.INTER_NEAREST)
frame = np.full((720, 1280), 110, np.uint8)
y, x = (720 - q.shape[0]) // 2, (1280 - q.shape[1]) // 2
frame[y:y + q.shape[0], x:x + q.shape[1]] = q
frame = cv2.GaussianBlur(frame, (3, 3), 0)
frame = np.clip(frame + np.random.default_rng(1).normal(0, 6, frame.shape), 0, 255).astype(np.uint8)
with tempfile.TemporaryDirectory() as d:
    png = os.path.join(d, 'qr.png')
    cv2.imwrite(png, frame)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-loop', '1', '-i', png, '-t', '6', '-r', '15', '-c:v', 'libx264',
                    '-pix_fmt', 'yuv420p', out], check=True)
