package com.omnirunner.omni_runner

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup WearOS DataLayer bridge (phone side)
        PhoneDataLayerManager.shared.setup(
            context = this,
            binaryMessenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
