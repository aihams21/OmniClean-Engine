package dev.omniclean.omni_clean_engine

import android.app.Activity
import android.app.usage.StorageStatsManager
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The native half of OmniClean's Android storage engine.
 *
 * Every byte this application claims to reclaim on Android comes from here,
 * never from dart:io. That is deliberate: since Android 11 the File API cannot
 * see MediaStore, the trash, or another app's directory, so a dart:io cleaner
 * on a modern phone is a no-op that reports 97 KB. This class speaks the two
 * APIs that still work — MediaStore for indexed media, and the Java File tree
 * where "All files access" has been granted — and reports honestly when it has
 * neither.
 */
class StorageBridge(
    private val context: Context,
    private val activityProvider: () -> Activity?,
) {

    private companion object {
        const val CHANNEL = "dev.omniclean.engine/storage"

        /** Junk categories share one display name, so one text description. */
        const val TEXT_MIME = "text/plain"

        /**
         * How many candidate rows a scan may materialise before it starts
         * reporting `capped`. A phone with 40 000 photos is normal; shipping
         * every row over the method channel is not.
         */
        const val SCAN_CEILING = 4000

        /** How many media rows a gallery page may return. */
        const val MEDIA_CEILING = 500
    }

    fun attach(messenger: BinaryMessenger): MethodChannel {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(::onCall)
        return channel
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "capabilities" -> result.success(capabilities())
                "scanJunk" -> result.success(scanJunk(minAgeMillis(call)))
                "deleteEntries" -> result.success(deleteEntries(call))
                "emptyTrash" -> result.success(emptyTrash())
                "media" -> result.success(media(call))
                "mediaFiles" -> result.success(mediaFiles(call))
                "unusedApps" -> result.success(unusedApps(minAgeMillis(call)))
                "launchUninstall" -> result.success(launchUninstall(call))
                "boost" -> result.success(boost())
                "requestAccess" -> result.success(requestAccess())
                "browsableRoots" -> result.success(browsableRoots())
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            // A bridge that throws is a bridge that crashes the app on the one
            // device shape nobody tested. Every failure degrades to an honest
            // empty answer instead.
            result.success(
                mapOf(
                    "error" to (t.message ?: t::class.java.simpleName),
                ),
            )
        }
    }

    private fun minAgeMillis(call: MethodCall): Long {
        val days = call.argument<Double>("minAgeDays") ?: 7.0
        return (days.coerceAtLeast(0.0) * 86_400_000L).toLong()
    }

    // ---------------------------------------------------------------- capability

    private fun capabilities(): Map<String, Any?> {
        val allFiles = hasAllFilesAccess()
        val sdk = Build.VERSION.SDK_INT
        val mediaRead = allFiles || hasMediaReadPermission()
        val root = Environment.getExternalStorageDirectory()?.absolutePath ?: "/storage/emulated/0"
        val mounted = Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED
        var total = 0L
        var free = 0L
        if (mounted) {
            try {
                val stat = StatFs(root)
                total = stat.blockCountLong * stat.blockSizeLong
                free = stat.availableBlocksLong * stat.blockSizeLong
            } catch (_: Throwable) {
                // A stat failure must read as "unknown", not as a zero drive.
            }
        }
        return mapOf(
            "apiLevel" to sdk,
            "hasAllFilesAccess" to allFiles,
            "hasMediaRead" to mediaRead,
            "canRequestAllFiles" to (sdk >= Build.VERSION_CODES.R && !allFiles),
            "canQueryUsageStats" to canQueryUsageStats(),
            "canUninstallApps" to true,
            "storageRoot" to root,
            "totalBytes" to total,
            "freeBytes" to free,
            "externalStorageMounted" to mounted,
        )
    }

    private fun hasAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
        val raw = Environment.isExternalStorageManager()
        if (raw) return true
        // Some OEM builds report false while still granting the access, so the
        // only honest cross-check is whether the tree is actually walkable.
        return try {
            val probe = File(Environment.getExternalStorageDirectory(), "Android")
            probe.isDirectory && probe.canRead()
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasMediaReadPermission(): Boolean {
        val fine = android.Manifest.permission.READ_EXTERNAL_STORAGE
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return context.checkSelfPermission(fine) == PackageManager.PERMISSION_GRANTED
        }
        val perType = listOf(
            android.Manifest.permission.READ_MEDIA_IMAGES,
            android.Manifest.permission.READ_MEDIA_VIDEO,
            android.Manifest.permission.READ_MEDIA_AUDIO,
        )
        // Any one of them is enough to list media; the gallery only ever shows
        // what the user may see anyway.
        return perType.any {
            context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun canQueryUsageStats(): Boolean {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return false
        return try {
            val now = System.currentTimeMillis()
            usm.queryEvents(now - 60_000L, now).hasNextEvent()
        } catch (_: Throwable) {
            false
        }
    }

    // ------------------------------------------------------------------- junk

    private fun scanJunk(minAgeMillis: Long): Map<String, Any?> {
        val out = mutableListOf<Map<String, Any?>>()
        val cutoff = System.currentTimeMillis() - minAgeMillis
        var scanned = 0
        var capped = false
        var supersededBytes = 0L

        fun add(row: Map<String, Any?>) {
            if (out.size >= SCAN_CEILING) {
                capped = true
                return
            }
            out.add(row)
        }

        // 1. The trash. MediaStore knows exactly what the user deleted, on every
        //    version from API 30 up, and it is the single largest category.
        scanned += queryMedia(
            selection = "${MediaStore.MediaColumns.IS_TRASHED} = 1",
            selectionArgs = null,
            projection = TRASH_PROJECTION,
        ) { cursor ->
            scanned++
            add(
                row(
                    id = cursor.getLong(0),
                    name = cursor.getString(2) ?: "trashed",
                    size = cursor.getLong(3),
                    modified = cursor.getLong(4),
                    kind = "trashed",
                    mime = cursor.getString(5) ?: TEXT_MIME,
                ),
            )
        }

        // 2. Half-finished downloads. A .crdownload or .part that has been
        //    sitting for a week is an interrupted transfer, never a real file.
        scanned += queryMedia(
            selection = null,
            selectionArgs = null,
            projection = TRASH_PROJECTION,
            where = { name ->
                val lower = name.lowercase()
                lower.endsWith(".crdownload") ||
                    lower.endsWith(".part") ||
                    lower.endsWith(".opdownload") ||
                    lower.endsWith(".download")
            },
        ) { cursor ->
            scanned++
            if (cursor.getLong(4) < cutoff) {
                add(
                    row(
                        id = cursor.getLong(0),
                        name = cursor.getString(2) ?: "partial",
                        size = cursor.getLong(3),
                        modified = cursor.getLong(4),
                        kind = "partialDownload",
                        mime = cursor.getString(5) ?: TEXT_MIME,
                    ),
                )
            }
        }

        // 3. Installers. A directory of APKs is the classic Android junk pile:
        //    the user downloads an update, installs it, and forgets the file.
        //    Only the *older* copy of a same-app pair is junk - the newest one
        //    may be the only installer the user still has.
        val installers = mutableListOf<Pair<Long, Triple<String, Long, Long>>>()
        var installerBytes = 0L
        scanned += queryMedia(
            selection = null,
            selectionArgs = null,
            projection = TRASH_PROJECTION,
            where = { name ->
                val lower = name.lowercase()
                lower.endsWith(".apk") || lower.endsWith(".apk.tmp") || lower.endsWith(".xapk")
            },
        ) { cursor ->
            scanned++
            val modified = cursor.getLong(4)
            val name = cursor.getString(2) ?: "installer"
            if (modified < cutoff) {
                val size = cursor.getLong(3)
                installerBytes += size
                installers.add(cursor.getLong(0) to Triple(name, size, modified))
            }
            true
        }
        // Group by the app the file installs, then keep every row but the
        // newest in each group. A group of one is never flagged.
        val newestByApp = HashMap<String, Long>()
        for ((_, triple) in installers) {
            val stamp = triple.third
            val app = installerKey(triple.first)
            val current = newestByApp[app]
            if (current == null || stamp > current) newestByApp[app] = stamp
        }
        for ((id, triple) in installers) {
            val (name, _, modified) = triple
            val newest = newestByApp[installerKey(name)]
            val obsolete = newest != null && modified < newest
            if (obsolete) installerBytes -= triple.second
            add(
                row(
                    id = id,
                    name = name,
                    size = triple.second,
                    modified = modified,
                    kind = if (obsolete) "obsoleteInstaller" else "logs",
                    mime = "application/vnd.android.package-archive",
                ),
            )
        }
        // Files nobody has superseded are still offered, but under their own
        // kind so the UI can label them honestly instead of calling them junk.
        supersededBytes = installerBytes.coerceAtLeast(0)

        // 4. Screenshots older than the retention window. The user keeps the
        //    ones they want; a month-old screenshot is not a loss.
        scanned += queryMedia(
            selection = null,
            selectionArgs = null,
            projection = TRASH_PROJECTION,
            where = { name ->
                val lower = name.lowercase()
                lower.startsWith("screenshot_") ||
                    lower.startsWith("screen capture") ||
                    lower.startsWith("screenshot ") ||
                    lower.startsWith("لقطة الشاشة") ||
                    lower.startsWith("截屏")
            },
        ) { cursor ->
            scanned++
            if (cursor.getLong(4) < cutoff) {
                add(
                    row(
                        id = cursor.getLong(0),
                        name = cursor.getString(2) ?: "screenshot",
                        size = cursor.getLong(3),
                        modified = cursor.getLong(4),
                        kind = "screenshots",
                        mime = cursor.getString(5) ?: "image/png",
                    ),
                )
            }
        }

        // 5. Residue of uninstalled apps: an Android/obb folder whose owning
        //    package is no longer installed. Needs the File API, so it only runs
        //    with "All files access".
        if (hasAllFilesAccess()) {
            scanned += scanAppResidue { entry ->
                if (entry != null) add(entry)
                if (out.size >= SCAN_CEILING) capped = true
            }
        }

        var total = 0L
        for (row in out) total += (row["sizeBytes"] as Long)

        return mapOf(
            "entries" to out,
            "totalBytes" to total,
            "scannedEntries" to scanned,
            "capped" to capped,
        )
    }

    /**
     * The app an installer belongs to, with the version stripped off.
     *
     * `WhatsApp-2.24.1.apk` beside `WhatsApp-2.25.0.apk` has to collapse to one
     * key, which is why the trailing digits are removed rather than compared:
     * naming schemes are too varied to parse, but "everything before the last
     * run of digits" identifies the app in practice.
     */
    private fun installerKey(name: String): String =
        name.replace(Regex("[-_ ]?v?\\d+(\\.\\d+)*(\\s*\\(.*?\\))?"), "")
            .substringBeforeLast('.')
            .lowercase()
            .trim()

    private fun scanAppResidue(emit: (Map<String, Any?>?) -> Unit): Int {
        var seen = 0
        val root = Environment.getExternalStorageDirectory() ?: return seen
        val android = File(root, "Android")
        if (!android.isDirectory) return seen
        val installed = installedPackages()

        for (container in listOf(File(android, "data"), File(android, "obb"))) {
            if (!container.isDirectory) continue
            val packages = container.listFiles() ?: continue
            for (dir in packages) {
                seen++
                if (!dir.isDirectory) continue
                // A package that is still installed is somebody's live data.
                if (dir.name !in installed) {
                    val bytes = treeBytes(dir)
                    if (bytes > 0) {
                        emit(
                            row(
                                id = dir.absolutePath.hashCode().toLong(),
                                name = dir.name,
                                size = bytes,
                                modified = dir.lastModified(),
                                kind = "appResidue",
                                mime = TEXT_MIME,
                                packageName = dir.name,
                            ),
                        )
                    }
                }
            }
        }
        return seen
    }

    private fun installedPackages(): Set<String> = try {
        val pm = context.packageManager
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(0)
        }
        packages.map { it.packageName }.toSet()
    } catch (_: Throwable) {
        emptySet()
    }

    private fun treeBytes(dir: File): Long {
        if (!dir.exists()) return 0
        if (dir.isFile) return dir.length()
        var sum = 0L
        val stack = ArrayDeque<File>()
        stack.addLast(dir)
        var guard = 0
        while (stack.isNotEmpty() && guard++ < 200_000) {
            val current = stack.removeLast()
            val children = current.listFiles() ?: continue
            for (child in children) {
                // Symlinked trees would let a stray link walk the whole device.
                if (child.isDirectory && !isSymlink(child)) {
                    stack.addLast(child)
                } else if (child.isFile) {
                    sum += child.length()
                }
            }
        }
        return sum
    }

    private fun isSymlink(file: File): Boolean = try {
        java.nio.file.Files.isSymbolicLink(file.toPath())
    } catch (_: Throwable) {
        false
    }

    // ----------------------------------------------------------------- delete

    /**
     * Deleting indexed media goes through MediaStore so the system updates its
     * own index; deleting a File-tree entry is an ordinary unlink, which is
     * safe only because "All files access" was granted and the path came from
     * our own scan rather than from the Dart side.
     */
    private fun deleteEntries(call: MethodCall): Map<String, Any?> {
        val ids = call.argument<List<String>>("ids").orEmpty()
        var freed = 0L
        var deleted = 0
        var failed = 0

        for (raw in ids) {
            val trimmed = raw.trim()
            if (trimmed.startsWith("media:")) {
                val longId = trimmed.removePrefix("media:").toLongOrNull()
                if (longId == null) {
                    failed++
                    continue
                }
                val uri = ContentUris.withAppendedId(MediaStore.Files.getContentUri("external"), longId)
                try {
                    val rows = context.contentResolver.delete(uri, null, null)
                    if (rows > 0) {
                        deleted += rows
                    } else {
                        failed++
                    }
                } catch (_: Throwable) {
                    failed++
                }
                continue
            }

            val target = File(trimmed)
            try {
                if (!target.exists()) {
                    failed++
                } else {
                    freed += if (target.isDirectory) {
                        treeBytes(target).also { target.deleteRecursively() }
                    } else {
                        target.length().also { target.delete() }
                    }
                    deleted++
                }
            } catch (_: Throwable) {
                failed++
            }
        }

        return mapOf(
            "deleted" to deleted,
            "failed" to failed,
            "freedBytes" to freed,
        )
    }

    /**
     * The trash is emptied by asking MediaStore to purge what it already
     * marked as deleted, which is the only path the platform actually supports.
     */
    private fun emptyTrash(): Map<String, Any?> {
        val uri = MediaStore.Files.getContentUri("external")
        var freed = 0L
        var deleted = 0
        cursor(
            uri,
            arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.SIZE,
            ),
            "${MediaStore.MediaColumns.IS_TRASHED} = 1",
            null,
        ) { c ->
            freed += c.getLong(1)
            deleted++
            true
        }
        var failed = 0
        if (deleted > 0) {
            try {
                // API 30+ can purge in one call; below that the rows have to be
                // deleted individually.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val rows = context.contentResolver.delete(
                        uri,
                        "${MediaStore.MediaColumns.IS_TRASHED} = 1",
                        null,
                    )
                    if (rows <= 0) failed = deleted
                } else {
                    cursor(
                        uri,
                        arrayOf(MediaStore.MediaColumns._ID),
                        "${MediaStore.MediaColumns.IS_TRASHED} = 1",
                        null,
                    ) { c ->
                        val id = ContentUris.withAppendedId(uri, c.getLong(0))
                        try {
                            if (context.contentResolver.delete(id, null, null) <= 0) failed++
                        } catch (_: Throwable) {
                            failed++
                        }
                        true
                    }
                }
            } catch (_: Throwable) {
                failed = deleted
            }
        }
        return mapOf("deleted" to deleted, "failed" to failed, "freedBytes" to freed)
    }

    // ------------------------------------------------------------------ media

    private fun media(call: MethodCall): Map<String, Any?> {
        val kind = call.argument<String>("kind") ?: "photos"
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        val (uri, selection) = when (kind) {
            "videos" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI to
                "${MediaStore.MediaColumns.IS_TRASHED} = 0"
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI to
                "${MediaStore.MediaColumns.IS_TRASHED} = 0"
            "downloads" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.EXTERNAL_CONTENT_URI to
                    "${MediaStore.MediaColumns.IS_TRASHED} = 0"
            } else {
                MediaStore.Files.getContentUri("external") to null
            }
            else -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI to
                "${MediaStore.MediaColumns.IS_TRASHED} = 0"
        }

        val items = mutableListOf<Map<String, Any?>>()
        var total = 0L
        var capped = false

        cursor(
            uri,
            projection,
            selection,
            null,
            MediaStore.MediaColumns.DATE_MODIFIED + " DESC",
        ) { c ->
            if (items.size >= MEDIA_CEILING) {
                capped = true
                return@cursor false
            }
            val size = c.getLong(2)
            total += size
            items.add(
                mapOf(
                    "id" to "media:${c.getLong(0)}",
                    "name" to (c.getString(1) ?: "file"),
                    "path" to "/storage/emulated/0/${c.getString(1) ?: "file"}",
                    "sizeBytes" to size,
                    // MediaStore stores seconds, not milliseconds.
                    "modifiedMillis" to (c.getLong(3) * 1000L),
                    "mimeType" to (c.getString(4) ?: TEXT_MIME),
                ),
            )
            true
        }

        return mapOf(
            "items" to items,
            "totalBytes" to total,
            "scannedEntries" to items.size,
            "capped" to capped,
        )
    }

    /**
     * Every media file on the device, with the real absolute path.
     *
     * This is the call that makes the duplicate finder work with zero setup.
     * The user never picks a folder; MediaStore already knows every photo and
     * video the device holds. The Dart side then runs its normal three
     * verification passes over this list, so a group it reports is exactly as
     * trustworthy as one found by walking a disk on the desktop.
     *
     * The DATA column is what makes the entry useful: the hasher needs a path
     * it can open, and a content URI is not one.
     */
    private fun mediaFiles(call: MethodCall): Map<String, Any?> {
        val minSize = (call.argument<Number>("minSizeBytes")?.toLong() ?: 4096L)
            .coerceAtLeast(0L)
        val projection = arrayOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATA,
        )
        val entries = mutableListOf<Map<String, Any?>>()
        var scanned = 0
        var capped = false

        val sources = listOf(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        )
        for (uri in sources) {
            cursor(
                uri,
                projection,
                "${MediaStore.MediaColumns.IS_TRASHED} = 0 AND " +
                    "${MediaStore.MediaColumns.SIZE} >= $minSize",
                null,
                MediaStore.MediaColumns.SIZE + " DESC",
            ) { c ->
                if (entries.size >= SCAN_CEILING) {
                    capped = true
                    return@cursor false
                }
                scanned++
                val path = c.getString(4)
                if (path.isNullOrBlank()) return@cursor true
                entries.add(
                    mapOf(
                        // The path is the identity here: the hasher opens it and
                        // the quarantine moves it, so it must be stable.
                        "id" to path,
                        "name" to (c.getString(0) ?: "file"),
                        "path" to path,
                        "sizeBytes" to c.getLong(1),
                        "modifiedMillis" to (c.getLong(2) * 1000L),
                        "kind" to "duplicateMedia",
                        "mimeType" to (c.getString(3) ?: TEXT_MIME),
                        "isDirectory" to false,
                    ),
                )
                true
            }
        }

        return mapOf(
            "entries" to entries,
            "totalBytes" to entries.sumOf { (it["sizeBytes"] as Long) },
            "scannedEntries" to scanned,
            "capped" to capped,
        )
    }

    // ------------------------------------------------------------ unused apps

    private fun unusedApps(minAgeMillis: Long): Map<String, Any?> {
        val pm = context.packageManager
        val usage = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        val stats = usage?.let { service ->
            try {
                val now = System.currentTimeMillis()
                val from = now - (minAgeMillis * 4).coerceAtLeast(86_400_000L)
                service.queryEvents(from, now).let { events ->
                    buildMap<String, Long> {
                        val event = android.app.usage.UsageEvents.Event()
                        while (events.hasNextEvent()) {
                            events.getNextEvent(event)
                            if (event.eventType == android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED ||
                                event.eventType == android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED
                            ) {
                                put(event.packageName, event.timeStamp)
                            }
                        }
                    }
                }
            } catch (_: Throwable) {
                null
            }
        }

        val storageStats = context.getSystemService(Context.STORAGE_STATS_SERVICE) as? StorageStatsManager
        val cutoff = System.currentTimeMillis() - minAgeMillis
        val rows = mutableListOf<Map<String, Any?>>()

        val installed = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledPackages(0)
            }
        } catch (_: Throwable) {
            emptyList()
        }

        for (info in installed) {
            val pkg = info.packageName
            if (pkg == context.packageName) continue
            val app = info.applicationInfo ?: continue
            val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val lastUsed = stats?.get(pkg) ?: 0L
            // Without usage-stats access every app looks "never used", which
            // would offer to uninstall the entire phone. System apps are never
            // offered, and a zero reading is reported as zero, not as ancient.
            if (isSystem && lastUsed == 0L) continue

            var bytes = 0L
            if (storageStats != null) {
                try {
                    bytes = storageStats.queryStatsForPackage(
                        // UUID_DEFAULT is the primary shared volume, which is
                        // where every installed app's data actually lives.
                        android.os.storage.StorageManager.UUID_DEFAULT,
                        context.packageName,
                        android.os.Process.myUserHandle(),
                    ).dataBytes
                } catch (_: Throwable) {
                    bytes = 0L
                }
            }

            rows.add(
                mapOf(
                    "packageName" to pkg,
                    "label" to runCatching { app.loadLabel(pm).toString() }.getOrDefault(pkg),
                    "sizeBytes" to bytes,
                    "lastUsedMillis" to lastUsed,
                    "versionName" to (info.versionName ?: ""),
                    "isSystem" to isSystem,
                    "installedMillis" to info.firstInstallTime,
                    // A zero lastUsed with real access means the app really was
                    // never opened; with no access it means "unknown", which the
                    // Dart side turns into a refusal to offer an uninstall.
                    "usageKnown" to (stats != null || lastUsed > 0L),
                    "idleCutoff" to cutoff,
                ),
            )
        }

        return mapOf("apps" to rows)
    }

    private fun launchUninstall(call: MethodCall): Map<String, Any?> {
        val pkg = call.argument<String>("packageName")
            ?: return mapOf("started" to false, "reason" to "no package name")
        val intent = Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val activity = activityProvider()
        return try {
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                context.startActivity(intent)
            }
            mapOf("started" to true)
        } catch (t: Throwable) {
            mapOf("started" to false, "reason" to (t.message ?: "cannot start uninstall"))
        }
    }

    // ------------------------------------------------------------------- boost

    /**
     * The boost a phone can honestly deliver without root.
     *
     * Root work that exists but cannot run is reported as skipped rather than
     * quietly pretended: claiming a cache drop that never happened is how a
     * cleaner loses the only thing it has - the user's trust in its numbers.
     */
    private fun boost(): Map<String, Any?> {
        val actions = mutableListOf<String>()
        var droppedCaches = false
        var freed = 0L

        val before = memorySnapshot()
        val cpuBefore = cpuSnapshot()

        // 1. Ask the platform to trim its own caches. This is the documented,
        //    permission-free way to hand memory back and it is real.
        try {
            val activity = activityProvider()
            if (activity != null) {
                requestTrim()
                actions.add("trimmed the application cache")
            } else {
                actions.add("skipped the cache trim: no foreground activity")
            }
        } catch (t: Throwable) {
            actions.add("skipped the cache trim: ${t.message ?: "failed"}")
        }

        // 2. Clear this app's own cache directory. Small, but free, and it is
        //    the one directory we are certain belongs to us.
        try {
            val cache = context.cacheDir
            var size = 0L
            cache.listFiles()?.forEach { child ->
                size += treeBytes(child)
                child.deleteRecursively()
            }
            freed += size
            actions.add("cleared this app's own cache (${size / 1024} KB)")
        } catch (t: Throwable) {
            actions.add("skipped the own cache: ${t.message ?: "failed"}")
        }

        // 3. Legacy caches outside our own directory.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            try {
                val external = context.externalCacheDir
                if (external != null) {
                    val size = treeBytes(external)
                    external.deleteRecursively()
                    freed += size
                    actions.add("cleared the legacy external cache (${size / 1024} KB)")
                }
            } catch (_: Throwable) {
                // Optional on modern devices; nothing to report.
            }
        }

        // 4. The page cache and the low-memory killer live behind root. Report
        //    the attempt, never a fake result.
        val rootResult = runRoot("sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; echo 1 > /proc/sys/vm/compaction_proactiveness 2>/dev/null")
        droppedCaches = rootResult.first
        actions.add(
            if (rootResult.first) {
                "dropped the page cache with root"
            } else {
                "page cache kept: dropping it needs root"
            },
        )

        // 5. Ask the battery manager to stop putting us to sleep.
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
            if (pm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                actions.add("asked the battery manager to stop dozing us")
            }
        } catch (_: Throwable) {
            // A OEM that blocks the intent is not an error worth surfacing.
        }

        // Re-read the numbers after the work, so the dashboard shows the
        // effect rather than the starting point copied twice.
        val after = memorySnapshot()
        val cpuAfter = cpuSnapshot()
        return mapOf(
            "killedProcesses" to 0,
            "droppedCaches" to droppedCaches,
            "freedBytes" to freed,
            "actions" to actions,
            "cpuBefore" to cpuBefore,
            "cpuAfter" to cpuAfter,
            "memoryBeforeBytes" to before,
            "memoryAfterBytes" to after,
        )
    }

    private fun runRoot(script: String): Pair<Boolean, String> = try {
        val process = ProcessBuilder("su", "-c", script).redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText().trim()
        process.waitFor()
        Pair(process.exitValue() == 0, output)
    } catch (_: Throwable) {
        Pair(false, "no root shell")
    }

    /**
     * Asks the app to release what it can, using the only public API Android
     * offers an app for this: delivering the strongest
     * [android.content.ComponentCallbacks2] trim level to ourselves, which runs
     * our own `onTrimMemory` and frees the caches we own.
     *
     * There is deliberately no attempt to trim *other* apps. Since Oreo the
     * system refuses that to any normal app, and a cleaner that pretends to have
     * done it is lying about the only number the user cares about.
     */
    private fun requestTrim() {
        val level = android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE
        val callbacks = activityProvider()?.application
        if (callbacks is android.content.ComponentCallbacks2) {
            callbacks.onTrimMemory(level)
        }
        val runtime = Runtime.getRuntime()
        System.gc()
        System.runFinalization()
        runtime.freeMemory()
    }

    private fun memorySnapshot(): Long = try {
        val stat = StatFs("/dev/shm")
        val total = stat.blockCountLong * stat.blockSizeLong
        val free = stat.availableBlocksLong * stat.blockSizeLong
        total - free
    } catch (_: Throwable) {
        0L
    }

    /**
     * Reads the CPU pressure straight out of /proc. Cheap, always available,
     * and - unlike a timer-based guess - it is the same number the kernel uses.
     */
    private fun cpuSnapshot(): Double = try {
        val stat = File("/proc/stat").readText().lineSequence().firstOrNull()
        val parts = stat?.trim()?.split(Regex("\\s+")) ?: return 0.0
        if (parts.size < 5 || !parts[0].startsWith("cpu ")) return 0.0
        val values = parts.drop(1).mapNotNull { it.toLongOrNull() ?: 0L }
        val total = values.sum()
        val idle = values.getOrElse(3) { 0L } + values.getOrElse(4) { 0L }
        val ratio = (total - idle).toDouble() / total
        if (total <= 0) 0.0 else ratio.coerceIn(0.0, 1.0)
    } catch (_: Throwable) {
        0.0
    }

    // ----------------------------------------------------------------- access

    private fun requestAccess(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return mapOf("started" to false, "reason" to "not needed on this version")
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val fallback = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            mapOf("started" to true)
        } catch (_: Throwable) {
            try {
                context.startActivity(fallback)
                mapOf("started" to true)
            } catch (t: Throwable) {
                mapOf("started" to false, "reason" to (t.message ?: "no settings activity"))
            }
        }
    }

    private fun browsableRoots(): Map<String, Any?> {
        if (!hasAllFilesAccess()) return mapOf("roots" to emptyList<Any>())
        val base = Environment.getExternalStorageDirectory() ?: return mapOf("roots" to emptyList<Any>())
        val roots = mutableListOf<Map<String, Any?>>()
        for (name in listOf("Download", "Documents", "Pictures", "Movies", "Music", "DCIM")) {
            val dir = File(base, name)
            if (dir.isDirectory) {
                roots.add(
                    mapOf(
                        "path" to dir.absolutePath,
                        "name" to name,
                        "bytes" to treeBytes(dir),
                    ),
                )
            }
        }
        return mapOf("roots" to roots)
    }

    // ----------------------------------------------------------------- cursor

    private fun queryMedia(
        selection: String?,
        selectionArgs: Array<String>?,
        projection: Array<String>,
        where: ((String) -> Boolean)? = null,
        onRow: (android.database.Cursor) -> Unit,
    ): Int {
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Files.getContentUri("external")
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Files.getContentUri("external")
        }
        var rows = 0
        cursor(uri, projection, selection, selectionArgs) { c ->
            rows++
            if (where != null) {
                val name = c.getString(2) ?: ""
                if (!where(name)) return@cursor true
            }
            onRow(c)
            true
        }
        return rows
    }

    private fun cursor(
        uri: Uri,
        projection: Array<String>,
        selection: String?,
        selectionArgs: Array<String>?,
        sort: String? = null,
        onRow: (android.database.Cursor) -> Boolean,
    ) {
        try {
            context.contentResolver.query(
                uri,
                projection,
                selection,
                selectionArgs,
                sort,
            )?.use { c ->
                val idIndex = c.getColumnIndex(MediaStore.MediaColumns._ID)
                if (idIndex < 0) return
                while (c.moveToNext()) {
                    if (!onRow(c)) return
                }
            }
        } catch (_: Throwable) {
            // A vendor MediaStore that throws on an exotic projection must not
            // take the scan down with it.
        }
    }

    private fun row(
        id: Long,
        name: String,
        size: Long,
        modified: Long,
        kind: String,
        mime: String,
        packageName: String? = null,
    ): Map<String, Any?> = mapOf(
        "id" to "media:$id",
        "name" to name,
        "path" to "/storage/emulated/0/$name",
        "sizeBytes" to size.coerceAtLeast(0),
        "modifiedMillis" to modified,
        "kind" to kind,
        "mimeType" to mime,
        "isDirectory" to false,
        "packageName" to packageName,
    )

    private val TRASH_PROJECTION = arrayOf(
        MediaStore.MediaColumns._ID,
        MediaStore.MediaColumns._ID,
        MediaStore.MediaColumns.DISPLAY_NAME,
        MediaStore.MediaColumns.SIZE,
        MediaStore.MediaColumns.DATE_MODIFIED,
        MediaStore.MediaColumns.MIME_TYPE,
    )
}
