package io.github.tko76.menudisplay;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.storage.StorageManager;
import android.os.storage.StorageVolume;
import android.view.KeyEvent;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.ImageView;
import android.widget.Toast;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Full-screen image display (or slideshow) loaded from internal storage or a USB drive.
 *
 * Source: /sdcard/Menu is tried first (push images there with adb — no USB drive needed);
 * if that folder is missing or empty, falls back to the root of a removable USB volume.
 *
 * Single image:  name the file display.jpg / display.png / menu.jpg in the source folder.
 * Slideshow:     put multiple jpg/png/webp files in the source folder; they cycle alphabetically.
 *                interval.txt in the same folder sets seconds-per-slide (default 10).
 *
 * Back or Home returns to the launcher.
 * Update content by swapping files in /sdcard/Menu (or on the USB drive) and power-cycling the TV.
 */
public class MenuActivity extends Activity {

    private static final int DEFAULT_INTERVAL_S = 10;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private List<File> images = new ArrayList<>();
    private int current = 0;
    private long intervalMs = DEFAULT_INTERVAL_S * 1000L;
    private ImageView iv;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        iv = new ImageView(this);
        iv.setBackgroundColor(0xff000000);
        iv.setScaleType(ImageView.ScaleType.FIT_CENTER);
        setContentView(iv);
        hideSystemUi();

        new Thread(() -> {
            File source = findSource();
            if (source == null) {
                runOnUiThread(() -> toast(
                    "No images found in /sdcard/Menu or on a USB drive."));
                return;
            }

            intervalMs = readInterval(source) * 1000L;
            images = findImages(source);

            if (images.isEmpty()) {
                runOnUiThread(() -> toast(
                    "No images found in /sdcard/Menu or on a USB drive (jpg/png/webp)."));
                return;
            }

            runOnUiThread(() -> showImage(0));
        }).start();
    }

    // ── Slide management ─────────────────────────────────────────────────────

    private void showImage(int index) {
        current = index;
        File file = images.get(current);
        new Thread(() -> {
            Bitmap bm = loadBitmap(file);
            runOnUiThread(() -> {
                if (bm != null) iv.setImageBitmap(bm);
                if (images.size() > 1) scheduleNext();
            });
        }).start();
    }

    private void scheduleNext() {
        handler.removeCallbacksAndMessages(null);
        handler.postDelayed(() -> showImage((current + 1) % images.size()), intervalMs);
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemUi();
    }

    private void hideSystemUi() {
        WindowInsetsController ctrl = getWindow().getInsetsController();
        if (ctrl != null) {
            ctrl.hide(WindowInsets.Type.systemBars());
            ctrl.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
    }

    // ── Source discovery ─────────────────────────────────────────────────────

    /** Internal storage folder tried before any USB drive: /sdcard/Menu. */
    private static final String INTERNAL_FOLDER_NAME = "Menu";

    /**
     * Internal /sdcard/Menu first (if it exists and has at least one usable image),
     * otherwise the root of the first removable USB volume found.
     */
    private File findSource() {
        File internal = new File(android.os.Environment.getExternalStorageDirectory(),
            INTERNAL_FOLDER_NAME);
        if (internal.exists() && internal.isDirectory() && !findImages(internal).isEmpty()) {
            return internal;
        }
        return findUsbRoot();
    }

    private File findUsbRoot() {
        StorageManager sm = getSystemService(StorageManager.class);
        for (StorageVolume vol : sm.getStorageVolumes()) {
            if (!vol.isRemovable()) continue;
            File dir = vol.getDirectory();
            if (dir != null && dir.exists()) return dir;
        }
        return null;
    }

    /** Read interval.txt; returns DEFAULT_INTERVAL_S if absent or invalid. */
    private int readInterval(File dir) {
        File f = new File(dir, "interval.txt");
        if (!f.exists()) return DEFAULT_INTERVAL_S;
        try (BufferedReader r = new BufferedReader(new FileReader(f))) {
            int v = Integer.parseInt(r.readLine().trim());
            return v > 0 ? v : DEFAULT_INTERVAL_S;
        } catch (Exception ignored) {
            return DEFAULT_INTERVAL_S;
        }
    }

    /**
     * Image selection:
     *   Single-image convention: display.jpg/png or menu.jpg/png → show forever.
     *   Otherwise: all jpg/png/webp files in root sorted alphabetically → slideshow.
     */
    private List<File> findImages(File dir) {
        for (String name : new String[]{
                "display.jpg", "display.jpeg", "display.png", "display.webp",
                "menu.jpg", "menu.jpeg", "menu.png", "menu.webp"}) {
            File f = new File(dir, name);
            if (f.exists() && f.canRead()) {
                List<File> single = new ArrayList<>();
                single.add(f);
                return single;
            }
        }

        File[] files = dir.listFiles(f -> {
            if (!f.isFile()) return false;
            String n = f.getName().toLowerCase();
            return n.endsWith(".jpg") || n.endsWith(".jpeg")
                || n.endsWith(".png") || n.endsWith(".webp");
        });
        List<File> list = new ArrayList<>();
        if (files != null) {
            Arrays.sort(files, (a, b) -> a.getName().compareToIgnoreCase(b.getName()));
            for (File f : files) if (f.canRead()) list.add(f);
        }
        return list;
    }

    // ── Bitmap loading ───────────────────────────────────────────────────────

    private Bitmap loadBitmap(File file) {
        try {
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(file.getAbsolutePath(), opts);
            opts.inSampleSize = calcSampleSize(opts.outWidth, opts.outHeight, 1920, 1080);
            opts.inJustDecodeBounds = false;
            return BitmapFactory.decodeFile(file.getAbsolutePath(), opts);
        } catch (OutOfMemoryError | Exception e) {
            android.util.Log.e("MenuDisplay", "Failed to load: " + file, e);
            return null;
        }
    }

    private static int calcSampleSize(int srcW, int srcH, int maxW, int maxH) {
        int ss = 1;
        while ((srcW / (ss * 2)) >= maxW && (srcH / (ss * 2)) >= maxH) ss *= 2;
        return ss;
    }

    // ── Navigation ───────────────────────────────────────────────────────────

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK || keyCode == KeyEvent.KEYCODE_HOME) {
            finish();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void toast(String msg) {
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show();
        handler.postDelayed(this::finish, 4000);
    }
}
