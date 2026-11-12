package com.follow.clash.plugins

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.net.toUri
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile

internal object SelfUpdater {
    private const val PREFS = "self_update"

    private fun preferences(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun id(arguments: Map<*, *>): String {
        val id = arguments["id"] as? String ?: error("Missing task id")
        require(Regex("[a-f0-9]{32}").matches(id))
        return id
    }

    @Suppress("DEPRECATION")
    fun validate(context: Context, arguments: Map<*, *>): File {
        val taskId = id(arguments)
        val root = File(context.filesDir, "updates").canonicalFile
        val file = File(arguments["path"] as? String ?: error("Missing update file"))
        val expected = File(root, "$taskId/installer.apk")
        require(file.absoluteFile == expected && file.canonicalFile == expected)
        require(file.isFile && file.length() == (arguments["size"] as Number).toLong())
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        require(digest.digest().joinToString("") { "%02x".format(it) } == arguments["sha256"])
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val pm = context.packageManager
        val archive = pm.getPackageArchiveInfo(file.path, flags) ?: error("Invalid APK")
        val installed = pm.getPackageInfo(context.packageName, flags)
        require(archive.packageName == context.packageName)
        val code = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        require(code == (arguments["build"] as Number).toLong() && code > installedCode)
        require(archive.versionName == arguments["version"])
        val archiveSignatures = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
        val installedSignatures = if (Build.VERSION.SDK_INT >= 28) installed.signingInfo?.apkContentsSigners else installed.signatures
        require(!archiveSignatures.isNullOrEmpty() && !installedSignatures.isNullOrEmpty())
        require(archiveSignatures.toSet() == installedSignatures.toSet())
        val abi = when (arguments["arch"]) {
            "arm64" -> "arm64-v8a"
            "arm" -> "armeabi-v7a"
            "x64" -> "x86_64"
            "x86" -> "x86"
            else -> error("Unsupported APK architecture")
        }
        require(Build.SUPPORTED_ABIS.contains(abi))
        ZipFile(file).use { zip -> require(zip.getEntry("lib/$abi/libflutter.so") != null) }
        return file
    }

    fun install(context: Context, activity: Activity?, arguments: Map<*, *>): String {
        val file = validate(context, arguments)
        val taskId = id(arguments)
        if (recover(context, taskId) == "installing") return "launched"
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
            requireNotNull(activity).startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, "package:${context.packageName}".toUri()),
            )
            return "authorizationRequired"
        }
        val installer = context.packageManager.packageInstaller
        val sessionId = installer.createSession(PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        })
        try {
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("base.apk", 0, file.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                preferences(context).edit().putInt("session.$taskId", sessionId).putString("status.$taskId", "installing").commit()
                val intent = Intent(context, UpdateInstallReceiver::class.java).apply {
                    action = "${context.packageName}.UPDATE_RESULT"
                    putExtra("taskId", taskId)
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
                session.commit(pending.intentSender)
            }
        } catch (error: Exception) {
            installer.abandonSession(sessionId)
            preferences(context).edit().putString("status.$taskId", "failed").commit()
            throw error
        }
        return "launched"
    }

    fun recover(context: Context, taskId: String): String? {
        require(Regex("[a-f0-9]{32}").matches(taskId))
        val prefs = preferences(context)
        val status = prefs.getString("status.$taskId", null)
        if (status != "installing") return status
        val sessionId = prefs.getInt("session.$taskId", -1)
        if (context.packageManager.packageInstaller.getSessionInfo(sessionId) == null) return "cancelled"
        return status
    }

    fun onResult(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra("taskId") ?: return
        if (!Regex("[a-f0-9]{32}").matches(taskId)) return
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirmation = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                try {
                    context.startActivity(confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (_: Exception) {
                    preferences(context).edit().putString("status.$taskId", "cancelled").commit()
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                preferences(context).edit().putString("status.$taskId", "installed").commit()
                context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                    context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> preferences(context).edit().putString("status.$taskId", "cancelled").commit()
            else -> preferences(context).edit()
                .putString("status.$taskId", "failed")
                .putString("error.$taskId", intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
                .commit()
        }
    }
}

class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        SelfUpdater.onResult(context, intent)
    }
}
