package io.github.tko76.restarttv;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;

/**
 * Opens as a transparent overlay, fires the system power dialog (Restart / Cancel) and stays alive
 * (but invisible) while the dialog is on screen so the D-pad focus lands inside the dialog, not
 * back at the launcher. Finishes in onResume(), which fires when the user dismisses the dialog and
 * returns here. noHistory=true ensures it is never on the back stack.
 */
public class RestartActivity extends Activity {
    private boolean launched;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!PowerService.showPowerDialog()) {
            Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            finish();
        } else {
            launched = true;
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (launched) {
            finish();
        }
    }
}
