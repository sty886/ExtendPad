package com.raisecaterror.meowdisplay.core.remote

enum class HostPlatform(val wireName: String) {
    MAC("macos"),
    LINUX("linux");

    companion object {
        fun parse(value: String?): HostPlatform = when (value?.trim()?.lowercase()) {
            LINUX.wireName, "ubuntu" -> LINUX
            else -> MAC
        }
    }
}
