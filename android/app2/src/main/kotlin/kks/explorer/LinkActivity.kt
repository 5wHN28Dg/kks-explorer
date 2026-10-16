package kks.explorer

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.Bundle
import kks.explorer.ui.AppLinks

/** Links from other apps (walkdown://…, decision 0058): the only activity with the scheme's intent filter. It has no
 *  window and finishes at once.
 *  - Walkdown's task is there: the link is queued (AppLinks) and the task comes to the front as it is. Whatever is open
 *    above MainActivity stays open, a photo being taken or a file being picked (CLEAR_TOP or `singleTask` would
 *    finish it and lose its result); the main screen opens the link once it is back in front (resumed).
 *  - No task: MainActivity starts in a new one with the link as its data (MainActivity.onCreate reads it).
 *  A VIEW Intent from another app (Walkdown Plant's `OS.shell_open` sets no NEW_TASK) would otherwise start a second
 *  MainActivity in the caller's task. Only the link's text goes on: no extras, no flags of the caller's. What it
 *  opens is read by the core, on the main screen. */
class LinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val data = intent?.dataString
        if (savedInstanceState == null && intent?.action == Intent.ACTION_VIEW && data != null && data.length <= MainActivity.MAX_LINK) {
            val task = getSystemService(ActivityManager::class.java).appTasks.firstOrNull {
                it.taskInfo.baseActivity?.className == MainActivity::class.java.name
            }
            if (task != null) {
                AppLinks.pending = data
                task.moveToFront()
            } else {
                startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(data), this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
        finish()
    }
}
