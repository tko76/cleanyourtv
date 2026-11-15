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
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.ImageView;
import android.widget.Toast;
import java.io.File;
import java.util.Arrays;
import java.util.List;

/**
 * Full-screen image display loaded from a USB drive.
 *
 * Image selection priority (USB root):
 *   1. display.jpg / display.jpeg / display.png / display.webp
 *   2. menu.jpg / menu.jpeg / menu.png
 *   3. First .jpg/.jpeg/.png/.webp found alphabetically
 *
 * Back or Home returns to the launcher.
 * USB drive must stay plugged in; content is updated by swapping files on the drive.
 */
public class MenuActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ImageView iv = new ImageView(this);
        iv.setBackgroundColor(0xff000000);
        iv.setScaleType(ImageView.ScaleType.FIT_CENTER);
        setContentView(iv);

        hideSystemUi();

        new Thread(() -> {
            File image = findImage();
            if (image == null) {
                runOnUiThread(() -> {
                    Toast.makeText(this,
                        "No image found on USB drive. Plug in a drive with display.jpg in the root.",
                        Toast.LENGTH_LONG).show();
                    new Handler(Looper.getMainLooper()).postDelayed(this::finish, 4000);
                });
                return;
            }
            Bitmap bm = loadBitmap(image);
            if (bm != null) {
                runOnUiThread(() -> iv.setImageBitmap(bm));
            } else {
                runOnUiThread(() -> {
                    Toast.makeText(this, "Could not load: " + image.getName(), Toast.LENGTH_LONG).show();
                    new Handler(Looper.getMainLooper()).postDelayed(this::finish, 4000);
                });
            }
        }).start();
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

    // ── Image discovery ──────────────────────────────────────────────────────

    private File findImage() {
        StorageManager sm = getSystemService(StorageManager.class);
        List<StorageVolume> volumes = sm.getStorageVolumes();

        for (StorageVolume vol : volumes) {
            if (!vol.isRemovable()) continue;
            File dir = vol.getDirectory();
            if (dir == null || !dir.exists()) continue;

            // Named candidates first (convention: put display.jpg on the drive root)
            for (String name : new String[]{
                    "display.jpg", "display.jpeg", "display.png", "display.webp",
                    "menu.jpg", "menu.jpeg", "menu.png", "menu.webp"}) {
                File f = new File(dir, name);
                if (f.exists() && f.canRead()) return f;
            }

            // Fallback: first image in root alphabetically
            File[] files = dir.listFiles(f -> {
                if (!f.isFile()) return false;
                String n = f.getName().toLowerCase();
                return n.endsWith(".jpg") || n.endsWith(".jpeg")
                    || n.endsWith(".png") || n.endsWith(".webp");
            });
            if (files != null && files.length > 0) {
                Arrays.sort(files, (a, b) -> a.getName().compareToIgnoreCase(b.getName()));
                return files[0];
            }
        }
        return null;
    }

    // ── Bitmap loading ───────────────────────────────────────────────────────

    private Bitmap loadBitmap(File file) {
        try {
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(file.getAbsolutePath(), opts);

            // Downsample to fit screen (1920×1080) to avoid OOM on large photos
            opts.inSampleSize = calcSampleSize(opts.outWidth, opts.outHeight, 1920, 1080);
            opts.inJustDecodeBounds = false;

            return BitmapFactory.decodeFile(file.getAbsolutePath(), opts);
        } catch (OutOfMemoryError | Exception e) {
            android.util.Log.e("MenuDisplay", "Failed to load bitmap: " + file, e);
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
}
