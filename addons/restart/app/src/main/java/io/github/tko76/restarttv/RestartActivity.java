package io.github.tko76.restarttv;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

/**
 * Opens as a transparent overlay, fires the system power dialog (Restart / Cancel) and then
 * finishes itself after a short delay. The delay lets the system dialog render and claim D-pad
 * focus before this activity exits. The dialog is a system window independent of this activity's
 * lifetime, so it stays on screen after finish() returns. noHistory=true ensures the activity is
 * never on the back stack.
 */
public class RestartActivity extends Activity {
    private static final int FINISH_DELAY_MS = 400;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!PowerService.showPowerDialog()) {
            // Service not enabled yet — send the user to Accessibility Settings.
            Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        }
        // Finish after the dialog has had time to render and take D-pad focus.
        new Handler(Looper.getMainLooper()).postDelayed(this::finish, FINISH_DELAY_MS);
    }
}
