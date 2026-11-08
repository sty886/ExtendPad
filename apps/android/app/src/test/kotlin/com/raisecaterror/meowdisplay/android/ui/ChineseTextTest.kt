package com.raisecaterror.meowdisplay.android.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ChineseTextTest {
    @Test
    fun localConnectStatusStaysChineseWithRouteDetails() {
        assertEquals(
            "正在请求主机连接… · USB 可用 · Wi-Fi 可用",
            ChineseText.translate("Asking it to connect… · USB available · Wi-Fi available"),
        )
    }

    @Test
    fun connectedSessionSummaryTranslatesEveryPart() {
        assertEquals(
            "扩展 · 正在控制 · 局域网",
            ChineseText.translate("Extend · Controlling · Local"),
        )
        assertEquals(
            "镜像 · 仅查看 · 远程",
            ChineseText.translate("Mirror · View Only · Remote"),
        )
    }

    @Test
    fun usbFailureDialogsAreChinese() {
        assertEquals(
            "Mac 未通过 USB 应答。请检查数据线，并确认 Mac 上的 ExtendPad 已打开。",
            ChineseText.translate("The Mac didn't answer over USB. Check the cable and that ExtendPad is open on the Mac."),
        )
        assertEquals(
            "USB 连接请求失败。请检查数据线，并确认 Mac 上的 ExtendPad 已打开。",
            ChineseText.translate("USB connection request failed. Check the cable and that the Mac app is open."),
        )
    }
}
