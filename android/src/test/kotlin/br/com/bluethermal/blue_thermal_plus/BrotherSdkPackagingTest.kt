package br.com.bluethermal.blue_thermal_plus

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

class BrotherSdkPackagingTest {
    @Test
    fun `plugin keeps the proprietary Brother AAR in the host app`() {
        val buildGradle = File("build.gradle").readText()

        assertTrue(!buildGradle.contains("BrotherPrintLibrary.aar"))
        assertTrue(!buildGradle.contains("implementation files("))
    }
}
