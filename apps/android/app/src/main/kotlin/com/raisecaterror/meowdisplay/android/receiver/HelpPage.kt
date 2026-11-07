package com.raisecaterror.meowdisplay.android.receiver

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import com.raisecaterror.meowdisplay.android.ui.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Product links and the tagline. Same addresses as the Apple apps (Shared/ProjectLinks.swift). */
object ProjectLinks {
    const val TAGLINE = "Mac Everywhere, On Whatever Display"
    const val GITHUB = "https://github.com/raiseCatError/meowdisplay"
    const val PRIVACY = "https://meowdisplay.app/privacy"
    const val MAC_APP = "https://github.com/raiseCatError/meowdisplay/releases/latest/download/MeowDisplay.dmg"
}

/** How each way of connecting works on Android today, in the order people try them. */
internal val connectionHelp = listOf(
    "同一无线局域网" to "在 Mac 上打开 ExtendPad。Mac 会自动出现在本设备首页，本设备也会出现在 Mac 应用中，无需输入 IP 地址。",
    "首次连接" to "点按“配对”，核对两端显示相同的六位验证码并分别确认。之后点按“连接”。",
    "USB 连接" to "在平板上开启并授权 USB 调试，用 USB 连接 Mac，并在 Mac 上允许 ADB 调试。ExtendPad 会通过已授权的 ADB forward 隧道连接，无需输入 IP 地址。",
    "其他网络" to "在本设备和 Mac 上安装 Tailscale 并登录同一账户（也可使用能连通两端的 VPN）。在 Mac 上打开“设置 → 设备”，选择“开放远程配对”。在此点按“+ 添加远程 Mac”，输入 Mac 的 Tailscale 名称或地址，点按“配对新 Mac”，并在两端确认相同验证码。之后即使不在同一无线局域网，也可点按“连接”。",
    "地址" to "可使用 Mac 的 MagicDNS 名称（mac.tailnet.ts.net 或 mac）、Tailscale IPv4 地址（100.101.102.103）或 IPv6 地址（[fd7a:115c:a1e0::1]）。仅在修改过端口时添加“:端口”。地址仅用于查找设备；是否信任 Mac 取决于配对，而不是地址或共享的 Tailscale 网络。",
    "找不到 Mac？" to "请确认 Mac 上的 ExtendPad 已打开，且两端连接同一无线局域网。访客网络通常会隔离设备。",
    "连接已断开" to "Mac 恢复可用后，本设备会自动重新连接（可在设置中调整“自动重新连接”）。如果已存储 Mac 的远程地址，本应用打开时还会在数分钟内请求 Mac 通过远程网络重新连接，包括离开 Mac 的无线局域网后。也可在首页点按“连接”。",
    "需要更新" to "如果 Mac 或本设备上的 ExtendPad 版本过旧，请更新旧版本，使两端版本匹配。",
)

@Composable
internal fun HelpPage() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sharing by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Heading("How to Connect")
        connectionHelp.forEach { (title, body) ->
            Column {
                Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
                Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        TextButton(onClick = { open(context, ProjectLinks.MAC_APP) }) { Text("Get the Mac app") }

        Heading("Troubleshooting")
        OutlinedButton(enabled = !sharing, onClick = {
            sharing = true
            scope.launch {
                val log = withContext(Dispatchers.IO) { ownLog() }
                sharing = false
                share(context, log)
            }
        }) { Text(if (sharing) "Preparing…" else "Share Connection Log") }
        Text(
            "What this device saw while connecting. No screen content, and nothing leaves the device unless you share it.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Heading("About")
        Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
            Text("Version", Modifier.weight(1f))
            Text(versionName(context), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        TextButton(onClick = { open(context, ProjectLinks.GITHUB) }) { Text("MeowDisplay on GitHub") }
        TextButton(onClick = { open(context, ProjectLinks.PRIVACY) }) { Text("Privacy Policy") }
        TextButton(onClick = { openAppSettings(context) }) { Text("Android Settings for MeowDisplay") }
        Text(ProjectLinks.TAGLINE, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun Heading(text: String) = Text(
    text, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary,
    modifier = Modifier.padding(top = 8.dp).semantics { heading() },
)

private fun versionName(context: Context): String = runCatching {
    context.packageManager.getPackageInfo(context.packageName, 0).versionName
}.getOrNull() ?: "dev"

private fun open(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
    }
}

private fun openAppSettings(context: Context) {
    try {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    } catch (_: ActivityNotFoundException) {
    }
}

/** This app's own recent log lines (Android only lets an app read its own), bounded for sharing. */
private fun ownLog(): String = runCatching {
    val process = ProcessBuilder("logcat", "-d", "-v", "time", "-t", "1500", "--pid=${android.os.Process.myPid()}")
        .redirectErrorStream(true).start()
    process.inputStream.bufferedReader().use { it.readText() }.takeLast(MAX_LOG_CHARS)
}.getOrElse { "Couldn't read the log: ${it.message}" }

private fun share(context: Context, log: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain")
        .putExtra(Intent.EXTRA_SUBJECT, "MeowDisplay connection log")
        .putExtra(Intent.EXTRA_TEXT, log)
    try {
        context.startActivity(Intent.createChooser(send, "Share Connection Log").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
    }
}

/** Well under the binder limit for an intent extra. */
private const val MAX_LOG_CHARS = 200_000
