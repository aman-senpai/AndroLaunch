@file:OptIn(ExperimentalMaterial3Api::class)

package com.senpai.androlaunch.companion.ui

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.senpai.androlaunch.companion.CallStateMonitor
import com.senpai.androlaunch.companion.CompanionService
import com.senpai.androlaunch.companion.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val PREFS = "androlaunch_ui"
private const val PREF_NOTIF_PROMPTED = "notif_prompted"

/** Pending call action that waits for ANSWER_PHONE_CALLS. */
private enum class PendingCallAction { None, Answer, Decline, End }

/** Which permission rationale sheet is currently shown. */
private enum class Rationale { None, Notifications, Phone, Control }

/**
 * The whole companion console: Material 3 scaffold, cards and rows.
 *
 * State comes from the existing Java daemon via [readCompanionState]; the UI only
 * orchestrates permissions, dialogs and snackbars. All live refresh happens on the
 * main thread from the daemon listeners plus a 1 Hz tick while resumed.
 */
@Composable
fun CompanionApp() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val handler = remember { Handler(Looper.getMainLooper()) }

    var state by remember { mutableStateOf(readCompanionState(context)) }
    var serviceOverride by remember { mutableStateOf<Boolean?>(null) }
    var callOverride by remember { mutableStateOf<Boolean?>(null) }
    var pendingCallAction by remember { mutableStateOf(PendingCallAction.None) }
    var rationale by remember { mutableStateOf(Rationale.None) }
    var menuExpanded by remember { mutableStateOf(false) }
    var showAbout by remember { mutableStateOf(false) }
    var showPrivacy by remember { mutableStateOf(false) }

    val refresh: () -> Unit = { state = readCompanionState(context) }
    fun snack(message: String) {
        scope.launch { snackbarHostState.showSnackbar(message) }
    }

    // Daemon + call-monitor listeners, and a 1 Hz tick while the screen is resumed.
    DisposableEffect(lifecycleOwner) {
        val listener = Runnable { handler.post { refresh() } }
        CompanionService.addStateListener(listener)
        CallStateMonitor.addListener(listener)
        onDispose {
            CompanionService.removeStateListener(listener)
            CallStateMonitor.removeListener(listener)
            handler.removeCallbacksAndMessages(null)
        }
    }
    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                refresh()
                delay(1_000L)
            }
        }
    }

    // Release the optimistic switch value once the daemon state catches up.
    LaunchedEffect(state.serviceActive, serviceOverride) {
        if (serviceOverride != null && state.serviceActive == serviceOverride) {
            serviceOverride = null
        }
    }
    LaunchedEffect(serviceOverride) {
        if (serviceOverride != null) {
            delay(2_500L)
            serviceOverride = null
        }
    }
    // Same optimistic handling for the call-awareness switch.
    LaunchedEffect(state.callLive, callOverride) {
        if (callOverride != null && state.callLive == callOverride) {
            callOverride = null
        }
    }
    LaunchedEffect(callOverride) {
        if (callOverride != null) {
            delay(2_500L)
            callOverride = null
        }
    }

    // --- service actions ---------------------------------------------------
    val startService: () -> Unit = {
        serviceOverride = true
        try {
            CompanionService.start(context)
            handler.postDelayed({ refresh() }, 350L)
            handler.postDelayed({ refresh() }, 1_100L)
        } catch (e: RuntimeException) {
            snack(context.getString(R.string.ui_toast_start_failed))
        }
    }
    val stopService: () -> Unit = {
        serviceOverride = false
        try {
            CompanionService.stop(context)
        } catch (_: RuntimeException) {
            // Stopping an already-stopped service is not an error.
        }
        handler.postDelayed({ refresh() }, 350L)
    }
    val restartService: () -> Unit = {
        try {
            CompanionService.stop(context)
        } catch (_: RuntimeException) {
        }
        serviceOverride = true
        snack(context.getString(R.string.ui_restarting))
        handler.postDelayed({
            try {
                CompanionService.start(context)
            } catch (_: RuntimeException) {
            }
            refresh()
        }, 400L)
        handler.postDelayed({ refresh() }, 1_200L)
    }

    val copyAdbCommand: () -> Unit = {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboard?.setPrimaryClip(
            ClipData.newPlainText(
                "AndroLaunch ADB command",
                context.getString(R.string.ui_adb_command),
            ),
        )
        snack(context.getString(R.string.ui_copied))
    }
    val openNotificationSettings: () -> Unit = {
        try {
            context.startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
            )
        } catch (_: RuntimeException) {
            try {
                context.startActivity(Intent(Settings.ACTION_SETTINGS))
            } catch (_: RuntimeException) {
            }
        }
    }
    val openNotificationAccess: () -> Unit = {
        try {
            context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        } catch (_: RuntimeException) {
            openNotificationSettings()
        }
    }

    // --- call actions ------------------------------------------------------
    val enableCallAwareness: () -> Unit = {
        callOverride = true
        CallStateMonitor.setEnabled(context, true)
        CallStateMonitor.start(context)
        snack(context.getString(R.string.ui_toast_awareness_on))
        handler.postDelayed({ refresh() }, 300L)
    }
    val disableCallAwareness: () -> Unit = {
        callOverride = false
        CallStateMonitor.setEnabled(context, false)
        CallStateMonitor.stop()
        snack(context.getString(R.string.ui_toast_awareness_off))
        handler.postDelayed({ refresh() }, 300L)
    }
    val performCallAction: (PendingCallAction) -> Unit = { action ->
        when (action) {
            PendingCallAction.Answer -> if (!CallStateMonitor.answerCall(context)) {
                snack(context.getString(R.string.ui_toast_answer_failed))
            }
            PendingCallAction.Decline, PendingCallAction.End -> if (!CallStateMonitor.declineCall(context)) {
                snack(context.getString(R.string.ui_toast_decline_failed))
            }
            PendingCallAction.None -> Unit
        }
        handler.postDelayed({ refresh() }, 500L)
    }
    val requestCallControl: (PendingCallAction) -> Unit = { action ->
        pendingCallAction = action
        rationale = Rationale.Control
    }

    // --- permission launchers ---------------------------------------------
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { _ ->
        // The bridge works with or without the notification; start it regardless.
        startService()
    }
    val phonePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            callOverride = true
            CallStateMonitor.setEnabled(context, true)
            CallStateMonitor.start(context)
            snack(context.getString(R.string.ui_toast_awareness_on))
        } else {
            snack(context.getString(R.string.ui_toast_phone_denied))
        }
        refresh()
    }
    val controlPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val action = pendingCallAction
        pendingCallAction = PendingCallAction.None
        if (granted && action != PendingCallAction.None) {
            performCallAction(action)
        } else {
            refresh()
        }
    }

    fun notificationsPrompted(): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(PREF_NOTIF_PROMPTED, false)

    fun markNotificationsPrompted() {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(PREF_NOTIF_PROMPTED, true)
            .apply()
    }

    fun shouldPromptNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        return !granted && !notificationsPrompted()
    }

    val bridgeChecked = serviceOverride ?: state.serviceActive
    val onBridgeChange: (Boolean) -> Unit = { checked ->
        if (checked) {
            if (shouldPromptNotifications()) {
                rationale = Rationale.Notifications
            } else {
                startService()
            }
        } else {
            stopService()
        }
    }
    val onCallAwarenessChange: (Boolean) -> Unit = { checked ->
        if (!state.callSupported) {
            // Row is not interactive when telephony is unavailable.
        } else if (checked) {
            if (!state.callAccess) {
                rationale = Rationale.Phone
            } else {
                enableCallAwareness()
            }
        } else {
            disableCallAwareness()
        }
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            painter = painterResource(R.drawable.ic_notification_large_icon),
                            contentDescription = stringResource(R.string.app_name),
                            modifier = Modifier
                                .size(28.dp)
                                .clip(RoundedCornerShape(8.dp)),
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            text = stringResource(R.string.app_name),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { menuExpanded = true }) {
                            Icon(
                                imageVector = Icons.Filled.MoreVert,
                                contentDescription = stringResource(R.string.ui_more),
                            )
                        }
                        DropdownMenu(
                            expanded = menuExpanded,
                            onDismissRequest = { menuExpanded = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.ui_menu_restart)) },
                                onClick = {
                                    menuExpanded = false
                                    restartService()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.ui_menu_copy_adb)) },
                                onClick = {
                                    menuExpanded = false
                                    copyAdbCommand()
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(stringResource(R.string.ui_menu_notification_settings))
                                },
                                onClick = {
                                    menuExpanded = false
                                    openNotificationSettings()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.ui_menu_privacy)) },
                                onClick = {
                                    menuExpanded = false
                                    showPrivacy = true
                                },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.ui_menu_about)) },
                                onClick = {
                                    menuExpanded = false
                                    showAbout = true
                                },
                            )
                        }
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ConnectionCard(
                state = state,
                bridgeChecked = bridgeChecked,
                onBridgeChange = onBridgeChange,
            )
            MirroringCard(
                state = state,
                onAllowNotifications = openNotificationAccess,
            )
            CallsCard(
                state = state,
                callsChecked = callOverride ?: state.callLive,
                onCallAwarenessChange = onCallAwarenessChange,
                onAllowPhone = { rationale = Rationale.Phone },
                onAllowControl = { requestCallControl(PendingCallAction.None) },
                onAnswer = {
                    if (state.callControl) {
                        performCallAction(PendingCallAction.Answer)
                    } else {
                        requestCallControl(PendingCallAction.Answer)
                    }
                },
                onDecline = {
                    if (state.callControl) {
                        performCallAction(PendingCallAction.Decline)
                    } else {
                        requestCallControl(PendingCallAction.Decline)
                    }
                },
                onEndCall = {
                    if (state.callControl) {
                        performCallAction(PendingCallAction.End)
                    } else {
                        requestCallControl(PendingCallAction.End)
                    }
                },
            )
            Text(
                text = stringResource(R.string.ui_local_only),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    // --- dialogs -----------------------------------------------------------
    when (rationale) {
        Rationale.Notifications -> RationaleDialog(
            title = stringResource(R.string.ui_notif_rationale_title),
            message = stringResource(R.string.ui_notif_rationale_message),
            onContinue = {
                markNotificationsPrompted()
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            },
            onDismiss = { rationale = Rationale.None },
        )
        Rationale.Phone -> RationaleDialog(
            title = stringResource(R.string.ui_phone_rationale_title),
            message = stringResource(R.string.ui_phone_rationale_message),
            onContinue = {
                phonePermissionLauncher.launch(Manifest.permission.READ_PHONE_STATE)
            },
            onDismiss = { rationale = Rationale.None },
        )
        Rationale.Control -> RationaleDialog(
            title = stringResource(R.string.ui_control_rationale_title),
            message = stringResource(R.string.ui_control_rationale_message),
            onContinue = {
                controlPermissionLauncher.launch(Manifest.permission.ANSWER_PHONE_CALLS)
            },
            onDismiss = {
                pendingCallAction = PendingCallAction.None
                rationale = Rationale.None
            },
        )
        Rationale.None -> Unit
    }

    if (showAbout) {
        AboutDialog(onDismiss = { showAbout = false })
    }
    if (showPrivacy) {
        PrivacyDialog(onDismiss = { showPrivacy = false })
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp),
    )
}

@Composable
private fun ConnectionCard(
    state: CompanionUiState,
    bridgeChecked: Boolean,
    onBridgeChange: (Boolean) -> Unit,
) {
    val bridgeLabel = stringResource(R.string.ui_bridge)
    val bridgeText = when {
        state.serviceActive && state.clients > 0 -> stringResource(R.string.ui_bridge_running_connected)
        state.serviceActive -> stringResource(R.string.ui_bridge_running_waiting)
        else -> stringResource(R.string.ui_bridge_stopped)
    }
    val bridgeColor = if (state.serviceActive) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val mirrored = if (state.serviceActive && state.notificationAccess) {
        state.mirrored.toString()
    } else {
        stringResource(R.string.ui_value_none)
    }
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionLabel(stringResource(R.string.ui_section_connection))
            ListItem(
                headlineContent = { Text(stringResource(R.string.ui_bridge)) },
                supportingContent = { Text(bridgeText, color = bridgeColor) },
                trailingContent = {
                    Switch(
                        checked = bridgeChecked,
                        onCheckedChange = onBridgeChange,
                        modifier = Modifier.semantics { contentDescription = bridgeLabel },
                    )
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            ListItem(
                headlineContent = { Text(stringResource(R.string.ui_mirrored)) },
                trailingContent = {
                    Text(
                        text = mirrored,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
        }
    }
}

@Composable
private fun MirroringCard(
    state: CompanionUiState,
    onAllowNotifications: () -> Unit,
) {
    val clipboard = if (state.serviceActive) {
        stringResource(R.string.ui_clipboard_ready)
    } else {
        stringResource(R.string.ui_clipboard_off)
    }
    val notifications = if (state.notificationAccess) {
        stringResource(R.string.ui_notifications_allowed)
    } else {
        stringResource(R.string.ui_notifications_needs)
    }
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionLabel(stringResource(R.string.ui_section_mirroring))
            ListItem(
                headlineContent = { Text(stringResource(R.string.ui_clipboard)) },
                trailingContent = {
                    Text(
                        text = clipboard,
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (state.serviceActive) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            ListItem(
                headlineContent = { Text(stringResource(R.string.ui_notifications)) },
                supportingContent = {
                    Text(
                        text = notifications,
                        color = if (state.notificationAccess) {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        } else {
                            MaterialTheme.colorScheme.error
                        },
                    )
                },
                trailingContent = {
                    if (!state.notificationAccess) {
                        TextButton(onClick = onAllowNotifications) {
                            Text(stringResource(R.string.ui_allow))
                        }
                    }
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
        }
    }
}

@Composable
private fun CallsCard(
    state: CompanionUiState,
    callsChecked: Boolean,
    onCallAwarenessChange: (Boolean) -> Unit,
    onAllowPhone: () -> Unit,
    onAllowControl: () -> Unit,
    onAnswer: () -> Unit,
    onDecline: () -> Unit,
    onEndCall: () -> Unit,
) {
    val callsLabel = stringResource(R.string.ui_calls)
    val summary = when {
        !state.callSupported -> stringResource(R.string.ui_calls_unsupported)
        !state.callAccess -> stringResource(R.string.ui_calls_needs_phone)
        !state.callEnabled -> stringResource(R.string.ui_calls_off)
        state.ringing -> stringResource(R.string.ui_calls_ringing)
        state.inCall -> stringResource(R.string.ui_calls_in_call)
        else -> stringResource(R.string.ui_calls_idle)
    }
    val summaryColor = when {
        !state.callSupported -> MaterialTheme.colorScheme.onSurfaceVariant
        !state.callAccess -> MaterialTheme.colorScheme.error
        state.ringing -> MaterialTheme.colorScheme.error
        state.inCall -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    val showAllowPhone = state.callSupported && !state.callAccess
    val showAnswer = state.callLive && state.ringing
    val showEndCall = state.callLive && state.inCall
    val showAllowControl = state.callLive && !state.callControl && !state.ringing && !state.inCall
    val hasAction = showAllowPhone || showAnswer || showEndCall || showAllowControl

    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            ListItem(
                headlineContent = { Text(stringResource(R.string.ui_calls)) },
                supportingContent = { Text(summary, color = summaryColor) },
                trailingContent = {
                    if (state.callSupported) {
                        Switch(
                            checked = callsChecked,
                            onCheckedChange = onCallAwarenessChange,
                            modifier = Modifier.semantics {
                                contentDescription = callsLabel
                            },
                        )
                    }
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
            if (hasAction) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 16.dp, end = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (showAllowPhone) {
                        TextButton(onClick = onAllowPhone) {
                            Text(stringResource(R.string.ui_allow_phone))
                        }
                    }
                    if (showAnswer) {
                        TextButton(onClick = onAnswer) {
                            Text(stringResource(R.string.ui_answer))
                        }
                        TextButton(onClick = onDecline) {
                            Text(
                                text = stringResource(R.string.ui_decline),
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                    if (showEndCall) {
                        TextButton(onClick = onEndCall) {
                            Text(
                                text = stringResource(R.string.ui_end_call),
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                    if (showAllowControl) {
                        TextButton(onClick = onAllowControl) {
                            Text(stringResource(R.string.ui_allow_control))
                        }
                    }
                }
            }
            Text(
                text = stringResource(R.string.ui_audio_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
            )
        }
    }
}

@Composable
private fun RationaleDialog(
    title: String,
    message: String,
    onContinue: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(
                onClick = {
                    onDismiss()
                    onContinue()
                },
            ) {
                Text(stringResource(R.string.ui_continue))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.ui_not_now))
            }
        },
    )
}

@Composable
private fun AboutDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val version = remember { appVersion(context) }
    val protocol = stringResource(R.string.ui_protocol_value)
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Image(
                painter = painterResource(R.drawable.ic_notification_large_icon),
                contentDescription = null,
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(12.dp)),
            )
        },
        title = { Text(stringResource(R.string.app_name)) },
        text = {
            Text(stringResource(R.string.ui_about_message, version, protocol))
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.ui_close))
            }
        },
    )
}

@Composable
private fun PrivacyDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.ui_menu_privacy)) },
        text = { Text(stringResource(R.string.ui_privacy_message)) },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.ui_close))
            }
        },
    )
}

private fun appVersion(context: Context): String {
    return try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "1.0.0"
    } catch (_: Exception) {
        "1.0.0"
    }
}
