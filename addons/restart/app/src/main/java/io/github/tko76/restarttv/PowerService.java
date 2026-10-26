package io.github.tko76.restarttv;

import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityEvent;

/**
 * Shows the system power dialog (Restart / Cancel) via the GLOBAL_ACTION_POWER_DIALOG accessibility
 * global action (available since Android 5.0 / API 21). The service asks for no events and reads no
 * window content: its only job is this one action, fired from RestartActivity.
 */
public class PowerService extends AccessibilityService {
    private static PowerService instance;

    static boolean showPowerDialog() {
        PowerService service = instance;
        return service != null && service.performGlobalAction(GLOBAL_ACTION_POWER_DIALOG);
    }

    @Override
    protected void onServiceConnected() {
        instance = this;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    public void onDestroy() {
        instance = null;
        super.onDestroy();
    }
}
