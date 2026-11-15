package io.github.tko76.menudisplay;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Launches the menu display automatically after a cold boot (outlet-timer power cycle). */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        Intent launch = new Intent(context, MenuActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        context.startActivity(launch);
    }
}
