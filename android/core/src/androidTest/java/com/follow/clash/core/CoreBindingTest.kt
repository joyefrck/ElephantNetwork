package com.follow.clash.core

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.follow.clash.core.mobile.Mobile
import com.follow.clash.core.mobile.ResultHandler
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class CoreBindingTest {
    private val sequence = AtomicInteger()

    private fun invoke(method: String, arguments: Any? = null): JSONObject {
        val id = sequence.incrementAndGet().toString()
        val received = AtomicReference<String>()
        val latch = CountDownLatch(1)
        Core.invokeMethod(JSONObject().put("id", id).put("method", method).put("arguments", arguments ?: JSONObject.NULL).toString()) {
            received.set(it)
            latch.countDown()
        }
        assertTrue("Core did not answer $method", latch.await(10, TimeUnit.SECONDS))
        return JSONObject(received.get()).also { assertEquals(id, it.getString("id")) }
    }

    @After
    fun releaseEvents() {
        Core.updateEventListener(null)
        invoke("log.stop")
    }

    @Test
    fun protocolRepliesUseStructuredErrorsAndNullCommands() {
        Core.load()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "core-binding-test").apply { mkdirs() }
        val init = invoke("core.init", JSONObject().put("home-dir", root.path).put("version", android.os.Build.VERSION.SDK_INT))
        assertTrue(init.isNull("result"))
        assertFalse(init.has("error"))
        assertTrue(invoke("core.initialized").getBoolean("result"))
        assertEquals("invalid_arguments", invoke("config.update", true).getJSONObject("error").getString("code"))
        assertEquals("not_implemented", invoke("updateConfig", JSONObject()).getJSONObject("error").getString("code"))
        File(root, "config.yaml").writeText("proxies: [invalid\n")
        val rejected = invoke("config.setup", JSONObject().put("selected-map", JSONObject()).put("test-url", "https://example.test"))
        assertEquals("core_error", rejected.getJSONObject("error").getString("code"))
        assertNull(rejected.opt("file"))
        val missing = File(root, "不存在🐘.yaml").path
        val readError = invoke("config.read", JSONObject().put("path", missing))
        assertTrue(readError.getJSONObject("error").getString("message").contains("不存在🐘.yaml"))
    }

    @Test
    fun JavaCallbackExceptionsDoNotPoisonLaterJniCalls() {
        repeat(16) {
            val latch = CountDownLatch(1)
            Mobile.invokeMethod("""{"id":"throw","method":"core.initialized"}""", ResultHandler {
                latch.countDown()
                throw IllegalStateException("Expected callback failure")
            })
            assertTrue(latch.await(10, TimeUnit.SECONDS))
            assertFalse(invoke("core.initialized").has("error"))
        }
    }

    @Test
    fun eventListenerCanThrowDetachAndReconnect() {
        val failed = CountDownLatch(1)
        Core.updateEventListener {
            failed.countDown()
            throw IllegalStateException("Expected event callback failure")
        }
        invoke("log.start")
        Core.forceGC()
        assertTrue(failed.await(10, TimeUnit.SECONDS))
        Core.updateEventListener(null)
        val received = CountDownLatch(1)
        Core.updateEventListener { result ->
            if (JSONObject(result!!).getString("method") == "message") received.countDown()
        }
        Core.forceGC()
        assertTrue(received.await(10, TimeUnit.SECONDS))
        assertTrue(JSONObject(Core.getTotalTraffic(false)).has("up"))
    }
}
