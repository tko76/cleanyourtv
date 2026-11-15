package io.github.luyzfernando08.sleeptimer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;

/** The timer's two alarms: a minute early, the warning; just after the end, sleep if nobody answered. */
public class AlarmReceiver extends BroadcastReceiver {
    private static final String ACTION_CONFIGURE = "io.github.luyzfernando08.sleeptimer.CONFIGURE";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (ACTION_CONFIGURE.equals(intent.getAction())) {
            // ADB-only provisioning path: the exported receiver is protected by WRITE_SECURE_SETTINGS.
            try {
                JSONArray source = new JSONArray(intent.getStringExtra("rules"));
                List<ScheduleRules.Rule> rules = new ArrayList<>();
                for (int i = 0; i < source.length(); i++) {
                    JSONObject item = source.getJSONObject(i);
                    rules.add(new ScheduleRules.Rule(item.getInt("days"), item.getInt("minute"), item.getBoolean("wake")));
                }
                Schedule.save(context, intent.getBooleanExtra("enabled", true), rules, Schedule.pauses(context));
            } catch (Exception error) {
                android.util.Log.e("SleepSchedule", "Invalid ADB schedule", error);
            }
            return;
        }
        if (Timer.ACTION_TEST.equals(intent.getAction())) {
            // From adb only (the receiver needs WRITE_SECURE_SETTINGS): a timer of a few seconds, to try it out.
            if (intent.getBooleanExtra("wake", false)) Schedule.testWake(context, intent.getIntExtra("seconds", 60));
            else Timer.startSeconds(context, intent.getIntExtra("seconds", 70));
            return;
        }
        if (Schedule.ACTION_TEST_WAKE.equals(intent.getAction())) {
            Schedule.wakeScreen(context,goAsync()::finish);
            return;
        }
        if (Schedule.ACTION_EVENT.equals(intent.getAction())) {
            Schedule.fire(context,goAsync()::finish);
            return;
        }
        if (Schedule.ACTION_BEDTIME.equals(intent.getAction())) {
            Schedule.reschedule(context);
            return;
        }
        long end = Timer.end(context);
        if (end == 0) return;                                   // cancelled, or pushed back since
        if (Timer.ACTION_WARN.equals(intent.getAction())) {
            context.startActivity(new Intent(context, WarningActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } else if (Timer.ACTION_SLEEP.equals(intent.getAction()) && System.currentTimeMillis() >= end) {
            Timer.sleepNow(context);
        }
    }
}
