package io.github.tko76.restarttv;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;

/**
 * Opens as a transparent overlay, fires the system power dialog (Restart / Cancel) and finishes.
 * If PowerService is not yet enabled, opens Accessibility Settings so the user can turn it on.
 */
public class RestartActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (PowerService.showPowerDialog()) {
            finish();
        } else {
            // Service not enabled yet — send the user to Accessibility Settings.
            Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            finish();
        }
    }
}
