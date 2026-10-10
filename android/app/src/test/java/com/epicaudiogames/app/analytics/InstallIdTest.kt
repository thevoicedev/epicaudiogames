package com.epicaudiogames.app.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * The random ID usage data is sent under (analytics/InstallId.kt): made once and kept, a UUID and nothing else, and
 * forgotten for good when usage data is turned off or deleted (the next one is another).
 */
class InstallIdTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val file by lazy { File(folder.root, "analytics/install_id") }

    @Test
    fun itsMadeTheFirstTimeItsNeededAndKept() {
        val id = InstallId(file)
        assertNull(id.peek())
        assertFalse(file.exists())
        val made = id.get()
        assertTrue(made, Events.fits("uuid", made))
        assertEquals(made, id.get())
        assertEquals(made, file.readText())
        // The next run reads the same.
        assertEquals(made, InstallId(file).peek())
        assertEquals(made, InstallId(file).get())
    }

    @Test
    fun forgottenItsGoneAndTheNextIsAnother() {
        val id = InstallId(file)
        val first = id.get()
        id.forget()
        assertNull(id.peek())
        assertFalse(file.exists())
        assertNull(InstallId(file).peek())
        val second = id.get()
        assertNotEquals(first, second)
        assertEquals(second, InstallId(file).peek())
    }

    @Test
    fun aDamagedFileIsNoID() {
        file.parentFile!!.mkdirs()
        file.writeText("not an id")
        val id = InstallId(file)
        assertNull(id.peek())
        val made = id.get()
        assertTrue(Events.fits("uuid", made))
        assertEquals(made, file.readText())
        // One written in capitals (by hand) is read, in the server's lower case.
        file.writeText("4B0C8A8E-4F3D-4C6E-9A51-3B8A7F0F2D10\n")
        assertEquals("4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10", InstallId(file).peek())
    }
}
