package com.lazyscan.lazyscan

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppInfoTest {
    @Test
    fun theVersionIsTheOneInTheVersionFile() {
        val wanted = File("../../VERSION").readText().trim()
        assertEquals("$wanted-debug", BuildConfig.VERSION_NAME)
    }

    @Test
    fun theTitleCarriesTheVersion() {
        assertTrue(AppInfo.title.startsWith("Lazy Scan "))
    }
}
