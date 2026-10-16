package dev.omniclean.omni_clean_engine

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The Flutter host, and the only place the native storage engine is wired up.
 *
 * Everything OmniClean knows about the phone's storage comes through
 * [StorageBridge]; the Dart side owns no storage logic of its own, so there is
 * exactly one place where a platform capability can be added.
 */
class MainActivity : FlutterActivity() {

    private var bridge: StorageBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bridge = StorageBridge(applicationContext) { this }.apply {
            attach(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun onDestroy() {
        bridge = null
        super.onDestroy()
    }
}
