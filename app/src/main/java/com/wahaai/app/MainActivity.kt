package com.wahaai.app

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.widget.EditText
import android.widget.ImageButton
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {

    private class ApiException(message: String) : Exception(message)

    private val adapter = MessageAdapter()
    private val history = mutableListOf<Pair<String, String>>() // role to content
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .build()
    private val prefs by lazy { getSharedPreferences("waha_prefs", MODE_PRIVATE) }

    private lateinit var recycler: RecyclerView
    private lateinit var welcome: View
    private lateinit var editMessage: EditText
    private lateinit var btnSend: ImageButton
    private var busy = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        recycler = findViewById(R.id.recyclerMessages)
        welcome = findViewById(R.id.welcomeScreen)
        editMessage = findViewById(R.id.editMessage)
        btnSend = findViewById(R.id.btnSend)

        recycler.layoutManager = LinearLayoutManager(this)
        recycler.adapter = adapter

        btnSend.setOnClickListener { sendMessage() }
        findViewById<ImageButton>(R.id.btnSettings).setOnClickListener { showSettings() }
        findViewById<ImageButton>(R.id.btnNewChat).setOnClickListener { newChat() }
    }

    private fun baseUrl() = prefs.getString("base_url", null)?.takeIf { it.isNotBlank() }
        ?: getString(R.string.default_base_url)

    private fun apiKey() = prefs.getString("api_key", "") ?: ""

    private fun model() = prefs.getString("model", null)?.takeIf { it.isNotBlank() }
        ?: getString(R.string.default_model)

    private fun showChat() {
        welcome.visibility = View.GONE
        recycler.visibility = View.VISIBLE
    }

    private fun scrollToEnd() {
        if (adapter.itemCount > 0) recycler.scrollToPosition(adapter.itemCount - 1)
    }

    private fun newChat() {
        history.clear()
        adapter.clearMessages()
        recycler.visibility = View.GONE
        welcome.visibility = View.VISIBLE
    }

    private fun sendMessage() {
        if (busy) return
        val text = editMessage.text.toString().trim()
        if (text.isEmpty()) return

        showChat()
        if (apiKey().isBlank()) {
            adapter.addMessage(ChatMessage(text, true))
            adapter.addMessage(ChatMessage(getString(R.string.error_no_api_key), false, isError = true))
            editMessage.text.clear()
            scrollToEnd()
            return
        }

        editMessage.text.clear()
        adapter.addMessage(ChatMessage(text, true))
        history.add("user" to text)
        adapter.addMessage(ChatMessage(getString(R.string.msg_thinking), false))
        scrollToEnd()
        busy = true
        btnSend.isEnabled = false

        val snapshot = history.toList()
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { requestChat(snapshot) } }
            adapter.removeLastMessage()
            result.onSuccess { reply ->
                history.add("assistant" to reply)
                adapter.addMessage(ChatMessage(reply, false))
            }.onFailure { e ->
                val msg = if (e is ApiException) getString(R.string.error_api, e.message)
                else getString(R.string.error_network)
                adapter.addMessage(ChatMessage(msg, false, isError = true))
            }
            scrollToEnd()
            busy = false
            btnSend.isEnabled = true
        }
    }

    private fun requestChat(
        messages: List<Pair<String, String>>,
        base: String = baseUrl(),
        key: String = apiKey(),
        modelName: String = model()
    ): String {
        val msgs = JsonArray()
        messages.forEach { (role, content) ->
            msgs.add(JsonObject().apply {
                addProperty("role", role)
                addProperty("content", content)
            })
        }
        val body = JsonObject().apply {
            addProperty("model", modelName)
            add("messages", msgs)
        }.toString().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url(base.trim().trimEnd('/') + "/chat/completions")
            .header("Authorization", "Bearer $key")
            .post(body)
            .build()

        client.newCall(request).execute().use { response ->
            val raw = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val detail = try {
                    JsonParser.parseString(raw).asJsonObject
                        .getAsJsonObject("error")?.get("message")?.asString
                } catch (e: Exception) {
                    null
                }
                throw ApiException(detail ?: "HTTP ${response.code}")
            }
            try {
                return JsonParser.parseString(raw).asJsonObject
                    .getAsJsonArray("choices")[0].asJsonObject
                    .getAsJsonObject("message")
                    .get("content").asString.trim()
            } catch (e: Exception) {
                throw ApiException(raw.take(200))
            }
        }
    }

    private fun showSettings() {
        val view = LayoutInflater.from(this).inflate(R.layout.dialog_settings, null)
        val editUrl = view.findViewById<EditText>(R.id.editBaseUrl)
        val editKey = view.findViewById<EditText>(R.id.editApiKey)
        val editModel = view.findViewById<EditText>(R.id.editModel)
        editUrl.setText(baseUrl())
        editKey.setText(apiKey())
        editModel.setText(model())

        val dialog = AlertDialog.Builder(this)
            .setView(view)
            .setPositiveButton(R.string.btn_save, null)
            .setNeutralButton(R.string.btn_test, null)
            .setNegativeButton(R.string.btn_cancel, null)
            .create()
        dialog.show()

        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            prefs.edit()
                .putString("base_url", editUrl.text.toString().trim())
                .putString("api_key", editKey.text.toString().trim())
                .putString("model", editModel.text.toString().trim())
                .apply()
            Toast.makeText(this, R.string.msg_saved, Toast.LENGTH_SHORT).show()
            dialog.dismiss()
        }

        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
            val url = editUrl.text.toString().trim().ifBlank { getString(R.string.default_base_url) }
            val key = editKey.text.toString().trim()
            val mdl = editModel.text.toString().trim().ifBlank { getString(R.string.default_model) }
            lifecycleScope.launch {
                val result = withContext(Dispatchers.IO) {
                    runCatching { requestChat(listOf("user" to "ping"), url, key, mdl) }
                }
                val msg = result.fold(
                    onSuccess = { getString(R.string.msg_test_success) },
                    onFailure = { e ->
                        getString(
                            R.string.msg_test_fail,
                            if (e is ApiException || e is IOException) e.message ?: "" else e.toString()
                        )
                    }
                )
                Toast.makeText(this@MainActivity, msg, Toast.LENGTH_LONG).show()
            }
        }
    }
}
