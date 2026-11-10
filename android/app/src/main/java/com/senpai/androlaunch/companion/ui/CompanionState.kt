package com.senpai.androlaunch.companion.ui

import android.content.Context
import com.senpai.androlaunch.companion.CallStateMonitor
import com.senpai.androlaunch.companion.CompanionService
import com.senpai.androlaunch.companion.NotificationRelay

/**
 * Immutable snapshot of the companion state for one recomposition.
 *
 * The daemon, notification relay and call monitor are plain Java singletons; this
 * reads their coarse state (no I/O) so Compose can render it. Refresh is driven by
 * their listeners plus a 1 Hz tick while the screen is resumed.
 */
data class CompanionUiState(
    val serviceActive: Boolean = false,
    val clients: Int = 0,
    val notificationAccess: Boolean = false,
    val mirrored: Int = 0,
    val callSupported: Boolean = false,
    val callAccess: Boolean = false,
    val callControl: Boolean = false,
    val callEnabled: Boolean = false,
    val ringing: Boolean = false,
    val inCall: Boolean = false,
) {
    /** True when call awareness is actually live (opt-in + telephony permission). */
    val callLive: Boolean get() = callSupported && callAccess && callEnabled
}

fun readCompanionState(context: Context): CompanionUiState {
    val active = CompanionService.isActive()
    val notificationAccess = NotificationRelay.hasAccess(context)
    val callEnabled = CallStateMonitor.isEnabled(context)
    val callAccess = CallStateMonitor.hasAccess(context)
    return CompanionUiState(
        serviceActive = active,
        clients = if (active) CompanionService.clientCount() else 0,
        notificationAccess = notificationAccess,
        mirrored = if (notificationAccess) NotificationRelay.size() else 0,
        callSupported = CallStateMonitor.isSupported(context),
        callAccess = callAccess,
        callControl = CallStateMonitor.hasControlAccess(context),
        callEnabled = callEnabled,
        ringing = callEnabled && callAccess && CallStateMonitor.isRinging(),
        inCall = callEnabled && callAccess && CallStateMonitor.isInCall(),
    )
}
