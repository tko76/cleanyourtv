package io.github.tko76.restarttv;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;

/**
 * Shows a "Restart now?" confirmation dialog over the launcher. D-pad navigable because it is
 * our own AlertDialog, not a system window we have no focus control over.
 *
 * On confirm: sends com.android.tv.settings.REBOOT_DEVICE to the Settings broadcast receiver,
 * which triggers a reboot when the sender has sufficient privilege. If refused (SecurityException),
 * falls back to opening Settings → System so the user can press Restart with one more OK press.
 *
 * noHistory=true so this activity never appears in the back stack.
 */
public class RestartActivity extends Activity {

    private static final String REBOOT_ACTION   = "com.android.tv.settings.REBOOT_DEVICE";
    private static final String SETTINGS_PKG    = "com.android.tv.settings";
    private static final String REBOOT_RECEIVER = SETTINGS_PKG + ".DeviceSettingBroadcastReceiver";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Restart now?")
                .setPositiveButton("Restart", (d, w) -> doRestart())
                .setNegativeButton("Cancel",  (d, w) -> finish())
                .setOnCancelListener(d -> finish())
                .show();
    }

    private void doRestart() {
        try {
            Intent reboot = new Intent(REBOOT_ACTION);
            reboot.setComponent(new ComponentName(SETTINGS_PKG, REBOOT_RECEIVER));
            reboot.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
            sendBroadcast(reboot);
        } catch (SecurityException ignored) {
            openSystemSettings();
        }
        finish();
    }

    private void openSystemSettings() {
        Intent deep = new Intent();
        deep.setClassName(SETTINGS_PKG, SETTINGS_PKG + ".MainSettings");
        deep.putExtra("com.android.tv.settings.TwoPanelSettingsFragment.PREFERENCE_FRAGMENT",
                      SETTINGS_PKG + ".system.SystemFragment");
        deep.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        try {
            startActivity(deep);
            return;
        } catch (Exception ignored) { }
        startActivity(new Intent(android.provider.Settings.ACTION_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }
}
