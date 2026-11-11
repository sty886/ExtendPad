package com.raisecaterror.meowdisplay.android.receiver.workspace

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.raisecaterror.meowdisplay.core.workspace.AppMenuEntry
import com.raisecaterror.meowdisplay.core.workspace.BarMenuModel
import com.raisecaterror.meowdisplay.core.workspace.BarMenuUi
import com.raisecaterror.meowdisplay.core.controls.CGRect
import kotlin.math.roundToInt

/**
 * Extend/Mirror: the streamed display's menu bar (PROTOCOL.md 6.18). The native menu bar is in
 * the picture; a transparent strip over it asks the Mac for the tapped title's menu and draws
 * the drop-down here. macOS anchors a windowless Finder's menus to the main display, so the
 * native drop-down is not usable on the extended one. Status items and the Apple menu come back
 * as `native`: the Mac opens the original menu itself and this overlay stays out of the way.
 */
@Composable
internal fun BarMenuOverlay(
    model: BarMenuModel,
    ui: BarMenuUi,
    /** The streamed picture in this window's dp coordinates. */
    frame: CGRect,
    screenWidthDp: Double,
    screenHeightDp: Double,
) {
    if (!ui.available || frame.isEmpty || frame.width <= 0 || frame.height <= 0) return
    val density = LocalDensity.current.density
    val stripHeight = frame.height * ui.heightFraction
    val anchorX = frame.minX + ui.anchorX * frame.width
    val menuWidth = 270.0
    val menuX = anchorX.coerceIn(8.0, maxOf(8.0, screenWidthDp - menuWidth - 8))
    val menuY = frame.minY + stripHeight + 4

    if (ui.open.isEmpty()) {
        // The invisible touch strip over the native menu bar. A tap names the title; the Mac
        // reads that title's menu (or opens a status item natively) and answers.
        // It is a Popup: a Compose sibling of the picture's AndroidView does not receive
        // touches that the interop view already handles.
        Popup(
            alignment = Alignment.TopStart,
            offset = IntOffset((frame.minX * density).roundToInt(), (frame.minY * density).roundToInt()),
            properties = PopupProperties(focusable = false, dismissOnClickOutside = false),
        ) {
            Box(
                Modifier
                    .size(frame.width.dp, stripHeight.dp)
                    .pointerInput(frame, ui.heightFraction) {
                        detectTapGestures { offset ->
                            val x = if (frame.width > 0) (offset.x / density) / frame.width else 0.0
                            // The middle of the menu bar: only x picks the title; a lower point
                            // would be the desktop on a slightly taller strip.
                            model.request(x.coerceIn(0.0, 1.0), ui.heightFraction * 0.5)
                        }
                    }
                    .semantics {
                        contentDescription = "Mac menu bar"
                        role = Role.Button
                    },
            )
        }
        ui.failed?.let { message ->
            Popup(
                alignment = Alignment.TopStart,
                offset = IntOffset((menuX * density).roundToInt(), (menuY * density).roundToInt()),
                properties = PopupProperties(focusable = false, dismissOnClickOutside = false),
            ) {
                Text(
                    message,
                    color = Color(0xFFFFB347),
                    fontSize = 12.sp,
                    modifier = Modifier
                        .background(Color(0xFF232326), RoundedCornerShape(8.dp))
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
        }
        return
    }

    // A full-window Popup: it sits above the picture's AndroidView, catches taps outside the
    // drop-down to close it, and keeps everything else from reaching the Mac while open.
    Popup(
        alignment = Alignment.TopStart,
        offset = IntOffset.Zero,
        properties = PopupProperties(focusable = false, dismissOnClickOutside = false),
    ) {
        Box(Modifier.size(screenWidthDp.dp, screenHeightDp.dp)) {
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) { detectTapGestures { model.close() } },
            )
            val level = ui.open.last()
            Column(
                Modifier
                    .offset { IntOffset((menuX * density).roundToInt(), (menuY * density).roundToInt()) }
                    .width(menuWidth.dp)
                    .heightIn(max = maxOf(120.0, minOf(460.0, screenHeightDp - menuY - 8)).dp)
                    .background(Color(0xFF232326), RoundedCornerShape(12.dp))
                    .border(0.75.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(12.dp))
                    .pointerInput(Unit) { detectTapGestures { } }
                    .semantics { contentDescription = level.title.ifEmpty { "Menu" } },
            ) {
                if (ui.open.size > 1) {
                    Text(
                        "‹  " + level.title,
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        maxLines = 1,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(role = Role.Button) { model.back() }
                            .semantics { contentDescription = "Back from ${level.title}" }
                            .heightIn(min = 48.dp)
                            .padding(horizontal = 12.dp)
                            .wrapContentHeight(Alignment.CenterVertically),
                    )
                    Box(Modifier.fillMaxWidth().height(0.5.dp).background(Color.White.copy(alpha = 0.2f)))
                }
                when {
                    level.loading -> Text("Loading…", color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp, modifier = Modifier.padding(14.dp))
                    level.error != null -> Text(barMenuMessage(level.error.orEmpty()), color = Color.White.copy(alpha = 0.75f), fontSize = 13.sp, modifier = Modifier.padding(14.dp))
                    level.items.isEmpty() -> Text("No items", color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp, modifier = Modifier.padding(14.dp))
                    else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 4.dp)) {
                        for (item in level.items) {
                            if (item.separator) {
                                Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).height(0.5.dp).background(Color.White.copy(alpha = 0.2f)))
                            } else {
                                BarMenuItem(item) {
                                    if (item.hasSubmenu) model.openSubmenu(item) else model.press(item)
                                }
                            }
                        }
                    }
                }
                ui.failed?.let { message ->
                    Text(barMenuMessage(message), color = Color(0xFFFFB347), fontSize = 12.sp, modifier = Modifier.padding(10.dp))
                }
            }
        }
    }
}

@Composable
private fun BarMenuItem(item: AppMenuEntry, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(enabled = item.enabled, role = Role.Button, onClick = onClick)
            .semantics {
                val states = listOfNotNull(
                    if (item.checked) "Checked" else null,
                    if (item.hasSubmenu) "Has a submenu" else null,
                )
                if (states.isNotEmpty()) stateDescription = states.joinToString(", ")
            }
            .heightIn(min = 48.dp)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(if (item.checked) "✓" else "", color = Color.White, fontSize = 12.sp,
            modifier = Modifier.width(18.dp).clearAndSetSemantics {})
        Text(item.title, color = Color.White.copy(alpha = if (item.enabled) 1f else 0.4f), fontSize = 14.sp,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        item.shortcut?.let {
            Text(it, color = Color.White.copy(alpha = 0.55f), fontSize = 12.sp, modifier = Modifier.padding(start = 8.dp))
        }
        if (item.hasSubmenu) {
            Text("›", color = Color.White.copy(alpha = 0.6f), fontSize = 16.sp,
                modifier = Modifier.padding(start = 8.dp).clearAndSetSemantics {})
        }
    }
}

private fun barMenuMessage(error: String) = when (error) {
    "accessibility" -> "Allow Accessibility for MeowDisplay on the Mac to use menus."
    "control" -> "Menus need control of the Mac."
    "changed" -> "That menu changed on the Mac. Try again."
    else -> "This menu isn't available."
}
