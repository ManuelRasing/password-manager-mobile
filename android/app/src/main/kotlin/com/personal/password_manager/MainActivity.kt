package com.personal.password_manager

import android.os.Bundle
import android.view.WindowManager
// FlutterFragmentActivity is required by local_auth for biometric dialogs on Android
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Block screenshots and hide content in the Android recent-apps thumbnail.
        // Applied at process start so the splash and every screen are covered.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
