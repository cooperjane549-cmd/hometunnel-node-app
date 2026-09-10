package co.ke.hometunnel.host

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets

class MainActivity: FlutterActivity() {
    private val CHANNEL = "co.ke.hometunnel/wireguard_host"
    private var backend: GoBackend? = null
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        backend = GoBackend(context)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startHostServer" -> {
                    val configText = call.argument<String>("config")
                    if (configText != null) {
                        val intent = VpnService.prepare(context)
                        if (intent != null) {
                            pendingConfig = configText
                            pendingResult = result
                            startActivityForResult(intent, 100)
                        } else {
                            startHostWireGuard(configText, result)
                        }
                    } else {
                        result.error("BAD_ARGS", "Config missing", null)
                    }
                }
                "stopHostServer" -> {
                    try {
                        backend?.setState(SimpleHostTunnel(), Tunnel.State.DOWN, null)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 100) {
            if (resultCode == Activity.RESULT_OK) {
                pendingConfig?.let { config ->
                    pendingResult?.let { res ->
                        startHostWireGuard(config, res)
                    }
                }
            } else {
                pendingResult?.error("PERMISSION_DENIED", "VPN permission denied by user", null)
            }
            pendingConfig = null
            pendingResult = null
        }
    }

    private fun startHostWireGuard(configText: String, result: MethodChannel.Result) {
        try {
            val config = Config.parse(ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8)))
            backend?.setState(SimpleHostTunnel(), Tunnel.State.UP, config)
            result.success(true)
        } catch (e: Exception) {
            result.error("TUNNEL_ERROR", e.message, null)
        }
    }

    class SimpleHostTunnel : Tunnel {
        override fun getName(): String = "HomeTunnelHost"
        override fun onStateChange(newState: Tunnel.State) {}
    }
}
