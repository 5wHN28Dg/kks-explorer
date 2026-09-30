package kks.bench;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.ColorSpace;
import android.graphics.HardwareRenderer;
import android.graphics.PixelFormat;
import android.graphics.RecordingCanvas;
import android.graphics.RenderNode;
import android.hardware.HardwareBuffer;
import android.media.Image;
import android.media.ImageReader;
import android.graphics.pdf.PdfRenderer;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.BitSet;
import java.util.List;

/** Throwaway M6 measurement (docs/decisions/0015): the same 512 px tiles as tools/m6 on the laptop, drawn by
 *  (1) Android PdfRenderer from the original PDF and (2) a software Canvas from grid-indexed paths. Logs "KKSBENCH". */
public class Bench extends Activity {
    static int T = 512;
    static final int N = 32, RUNS = 5;
    TextView out;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        T = getIntent().getIntExtra("tile", 512);
        out = new TextView(this);
        out.setTextSize(12);
        ScrollView sv = new ScrollView(this);
        sv.addView(out);
        setContentView(sv);
        new Thread(this::runAll).start();
    }

    void log(String s) {
        Log.i("KKSBENCH", s);
        runOnUiThread(() -> out.append(s + "\n"));
    }

    File asset(String name) throws Exception {
        File f = new File(getCacheDir(), name);
        try (InputStream in = getAssets().open(name); OutputStream o = new FileOutputStream(f)) {
            byte[] buf = new byte[1 << 16]; int n;
            while ((n = in.read(buf)) > 0) o.write(buf, 0, n);
        }
        return f;
    }

    static double median(double[] v) { double[] c = v.clone(); Arrays.sort(c); return c[c.length / 2]; }

    void runAll() {
        try {
            log("tile " + T + " px; device " + android.os.Build.MODEL + " Android " + android.os.Build.VERSION.RELEASE);
            for (String s : new String[]{"lp", "fw", "b1cond"}) runSheet(s);
            log("DONE");
        } catch (Throwable e) {
            log("ERROR " + e);
        }
    }

    void runSheet(String s) throws Exception {
        // ---- (1) PdfRenderer ----
        File pdf = asset(s + ".pdf");
        long t0 = System.nanoTime();
        PdfRenderer r = new PdfRenderer(ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY));
        PdfRenderer.Page page = r.openPage(0);
        double pdfLoad = (System.nanoTime() - t0) / 1e6;
        float pw = page.getWidth(), ph = page.getHeight();
        float fit = 2000f / pw;
        StringBuilder sb = new StringBuilder(String.format("%-7s PdfRenderer  open %6.1f ms", s, pdfLoad));
        for (int z : new int[]{1, 4, 16}) {
            float sc = fit * z;
            double[] ts = new double[RUNS];
            for (int i = 0; i < RUNS; i++) {
                Bitmap bm = Bitmap.createBitmap(T, T, Bitmap.Config.ARGB_8888);
                bm.eraseColor(Color.WHITE);
                Matrix m = new Matrix();
                m.setScale(sc * 72f / 72f, sc);   // page units are points; bitmap = pixels
                m.postTranslate(T / 2f - pw / 2 * sc, T / 2f - ph / 2 * sc);
                long a = System.nanoTime();
                page.render(bm, null, m, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                ts[i] = (System.nanoTime() - a) / 1e6;
                if (i == 0 && z == 4) save(bm, s + "-pdf-4x.png");
                bm.recycle();
            }
            sb.append(String.format("  tile %2dx %8.1f ms", z, median(ts)));
        }
        page.close(); r.close();
        log(sb.toString());

        // ---- (2) grid-indexed paths on a software Canvas ----
        File kkg = asset(s + ".kkg");
        t0 = System.nanoTime();
        byte[] raw = java.nio.file.Files.readAllBytes(kkg.toPath());
        ByteBuffer bb = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN);
        bb.position(4);
        float w = bb.getFloat(), h = bb.getFloat();
        int n = bb.getInt();
        float[][] box = new float[n][];
        Path[] paths = new Path[n];
        float[] lw = new float[n];
        int[] stroke = new int[n], fill = new int[n];
        for (int i = 0; i < n; i++) {
            box[i] = new float[]{bb.getFloat(), bb.getFloat(), bb.getFloat(), bb.getFloat()};
            lw[i] = bb.getFloat(); stroke[i] = bb.getInt(); fill[i] = bb.getInt();
            int segs = bb.getInt();
            Path p = new Path();
            float lx = Float.NaN, ly = Float.NaN;   // current point: continue the sub-path when a segment starts there
            for (int k = 0; k < segs; k++) {
                int t = bb.get();
                if (t == 2) { float x = bb.getFloat(), y = bb.getFloat(); p.addRect(x, y, x + bb.getFloat(), y + bb.getFloat(), Path.Direction.CW); lx = Float.NaN; continue; }
                float x0 = bb.getFloat(), y0 = bb.getFloat();
                if (x0 != lx || y0 != ly) p.moveTo(x0, y0);
                if (t == 0) { lx = bb.getFloat(); ly = bb.getFloat(); p.lineTo(lx, ly); }
                else if (t == 1) { float a = bb.getFloat(), b2 = bb.getFloat(), c2 = bb.getFloat(), d = bb.getFloat(); lx = bb.getFloat(); ly = bb.getFloat(); p.cubicTo(a, b2, c2, d, lx, ly); }
                else { p.lineTo(bb.getFloat(), bb.getFloat()); p.lineTo(bb.getFloat(), bb.getFloat()); p.lineTo(bb.getFloat(), bb.getFloat()); p.close(); lx = Float.NaN; }
            }
            if (fill[i] != -1) p.close();
            paths[i] = p;
        }
        double parse = (System.nanoTime() - t0) / 1e6;
        t0 = System.nanoTime();
        float cw = w / N, ch = h / N;
        List<List<Integer>> grid = new ArrayList<>();
        for (int i = 0; i < N * N; i++) grid.add(new ArrayList<>());
        for (int i = 0; i < n; i++) {
            int gx0 = Math.max(0, (int) (box[i][0] / cw)), gx1 = Math.min(N - 1, (int) (box[i][2] / cw));
            int gy0 = Math.max(0, (int) (box[i][1] / ch)), gy1 = Math.min(N - 1, (int) (box[i][3] / ch));
            for (int gx = gx0; gx <= gx1; gx++) for (int gy = gy0; gy <= gy1; gy++) grid.get(gy * N + gx).add(i);
        }
        double idx = (System.nanoTime() - t0) / 1e6;
        Paint sp = new Paint(Paint.ANTI_ALIAS_FLAG); sp.setStyle(Paint.Style.STROKE);
        Paint fp = new Paint(Paint.ANTI_ALIAS_FLAG); fp.setStyle(Paint.Style.FILL);
        sb = new StringBuilder(String.format("%-7s grid Canvas  parse %6.1f ms index %5.1f ms", s, parse, idx));
        for (int z : new int[]{1, 4, 16}) {
            float sc = (2000f / w) * z;
            double[] ts = new double[RUNS];
            int drawn = 0;
            for (int rI = 0; rI < RUNS; rI++) {
                Bitmap bm = Bitmap.createBitmap(T, T, Bitmap.Config.ARGB_8888);
                long a = System.nanoTime();
                bm.eraseColor(Color.WHITE);
                Canvas c = new Canvas(bm);
                float ox = w / 2 - T / 2f / sc, oy = h / 2 - T / 2f / sc;
                c.scale(sc, sc);
                c.translate(-ox, -oy);
                float minW = 1f / sc;   // at least one device pixel, like Poppler
                BitSet seen = new BitSet(n);
                drawn = 0;
                for (int gx = Math.max(0, (int) (ox / cw)); gx <= Math.min(N - 1, (int) ((ox + T / sc) / cw)); gx++)
                    for (int gy = Math.max(0, (int) (oy / ch)); gy <= Math.min(N - 1, (int) ((oy + T / sc) / ch)); gy++)
                        for (int i : grid.get(gy * N + gx)) {
                            if (seen.get(i)) continue;
                            seen.set(i); drawn++;
                            if (fill[i] != -1) { fp.setColor(0xFF000000 | fill[i]); c.drawPath(paths[i], fp); }
                            sp.setColor(0xFF000000 | stroke[i]); sp.setStrokeWidth(Math.max(lw[i], minW));
                            c.drawPath(paths[i], sp);
                        }
                ts[rI] = (System.nanoTime() - a) / 1e6;
                if (rI == 0 && z == 4) save(bm, s + "-grid-4x.png");
                bm.recycle();
            }
            sb.append(String.format("  tile %2dx %8.1f ms (%d paths)", z, median(ts), drawn));
        }
        log(sb.toString());

        // ---- (3) the same drawing on the GPU: RenderNode display list -> HardwareRenderer -> off-screen surface ----
        ImageReader reader = ImageReader.newInstance(T, T, PixelFormat.RGBA_8888, 3,
                HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE | HardwareBuffer.USAGE_GPU_COLOR_OUTPUT);
        HardwareRenderer hr = new HardwareRenderer();
        hr.setSurface(reader.getSurface());
        RenderNode root = new RenderNode("tile");
        root.setPosition(0, 0, T, T);
        hr.setContentRoot(root);
        sb = new StringBuilder(String.format("%-7s grid GPU    ", s));
        for (int z : new int[]{1, 4, 16}) {
            float sc = (2000f / w) * z;
            double[] rec = new double[RUNS], all = new double[RUNS];
            for (int rI = -2; rI < RUNS; rI++) {   // 2 untimed warm-up frames (shader compilation)
                long a = System.nanoTime();
                RecordingCanvas c = root.beginRecording(T, T);
                c.drawColor(Color.WHITE);
                float ox = w / 2 - T / 2f / sc, oy = h / 2 - T / 2f / sc;
                c.scale(sc, sc);
                c.translate(-ox, -oy);
                float minW = 1f / sc;
                BitSet seen = new BitSet(n);
                for (int gx = Math.max(0, (int) (ox / cw)); gx <= Math.min(N - 1, (int) ((ox + T / sc) / cw)); gx++)
                    for (int gy = Math.max(0, (int) (oy / ch)); gy <= Math.min(N - 1, (int) ((oy + T / sc) / ch)); gy++)
                        for (int i : grid.get(gy * N + gx)) {
                            if (seen.get(i)) continue;
                            seen.set(i);
                            if (fill[i] != -1) { fp.setColor(0xFF000000 | fill[i]); c.drawPath(paths[i], fp); }
                            sp.setColor(0xFF000000 | stroke[i]); sp.setStrokeWidth(Math.max(lw[i], minW));
                            c.drawPath(paths[i], sp);
                        }
                root.endRecording();
                long b2 = System.nanoTime();
                hr.createRenderRequest().setWaitForPresent(true).syncAndDraw();
                long e = System.nanoTime();
                Image img = reader.acquireLatestImage();
                if (img != null) {
                    if (rI == 0 && z == 4) {
                        Bitmap hw = Bitmap.wrapHardwareBuffer(img.getHardwareBuffer(), ColorSpace.get(ColorSpace.Named.SRGB));
                        save(hw.copy(Bitmap.Config.ARGB_8888, false), s + "-gpu-4x.png");
                    }
                    img.close();
                }
                if (rI >= 0) { rec[rI] = (b2 - a) / 1e6; all[rI] = (e - a) / 1e6; }
            }
            sb.append(String.format("  tile %2dx %6.1f ms (record %.1f)", z, median(all), median(rec)));
        }
        hr.destroy();
        reader.close();
        log(sb.toString());
    }

    void save(Bitmap bm, String name) {
        try (OutputStream o = new FileOutputStream(new File(getExternalFilesDir(null), name))) {
            bm.compress(Bitmap.CompressFormat.PNG, 100, o);
        } catch (Exception e) {
            log("save failed " + e);
        }
    }
}
