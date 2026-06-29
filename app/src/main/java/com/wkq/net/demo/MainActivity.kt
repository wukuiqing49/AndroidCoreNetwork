package com.wkq.net.demo

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import com.wkq.net.core.ApiResponse
import com.wkq.net.core.Net
import com.wkq.net.core.NetManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : Activity() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var statusText: TextView
    private lateinit var resultText: TextView
    private lateinit var requestButton: Button
    private lateinit var progressBar: ProgressBar

    private val demoApi: DemoApi by lazy {
        Net.create(DemoApi::class.java)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(createContentView())
        showReadyState()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun createContentView(): View {
        val density = resources.displayMetrics.density
        fun Int.dp(): Int = (this * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(20.dp(), 28.dp(), 20.dp(), 20.dp())
            setBackgroundColor(Color.rgb(248, 250, 252))
        }

        val title = TextView(this).apply {
            text = "Core Network 测试页"
            textSize = 24f
            setTextColor(Color.rgb(15, 23, 42))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }

        statusText = TextView(this).apply {
            textSize = 14f
            setTextColor(Color.rgb(71, 85, 105))
            setPadding(0, 10.dp(), 0, 18.dp())
        }

        requestButton = Button(this).apply {
            text = "请求测试接口"
            minHeight = 48.dp()
            setOnClickListener { requestDemoPost() }
        }

        progressBar = ProgressBar(this).apply {
            visibility = View.GONE
            isIndeterminate = true
        }

        resultText = TextView(this).apply {
            textSize = 15f
            setTextColor(Color.rgb(30, 41, 59))
            setPadding(0, 18.dp(), 0, 0)
            setLineSpacing(3.dp().toFloat(), 1f)
        }

        val progressWrapper = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(0, 14.dp(), 0, 4.dp())
            addView(
                progressBar,
                LinearLayout.LayoutParams(36.dp(), 36.dp())
            )
        }

        val scrollView = ScrollView(this).apply {
            addView(
                resultText,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
            )
        }

        root.addView(title)
        root.addView(statusText)
        root.addView(
            requestButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )
        root.addView(progressWrapper)
        root.addView(
            scrollView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        )

        return root
    }

    private fun showReadyState() {
        val initialized = NetManager.isInitialized()
        statusText.text = if (initialized) {
            "NetManager 已初始化，BaseUrl: ${NetManager.getConfig().baseUrl}"
        } else {
            "NetManager 未初始化"
        }
        resultText.text = "点击按钮后会通过 core_network 请求 jsonplaceholder 的 posts/1 接口。"
    }

    private fun requestDemoPost() {
        requestButton.isEnabled = false
        progressBar.visibility = View.VISIBLE
        resultText.text = "请求中..."

        scope.launch {
            val response = withContext(Dispatchers.IO) {
                Net.raw { demoApi.getPost(1) }
            }

            progressBar.visibility = View.GONE
            requestButton.isEnabled = true

            resultText.text = when (response) {
                is ApiResponse.Success -> response.data?.toPrettyText()
                    ?: "请求成功，但响应体为空。"
                is ApiResponse.Error -> buildString {
                    appendLine("请求失败")
                    appendLine("code: ${response.code}")
                    appendLine("type: ${response.type}")
                    appendLine("message: ${response.message}")
                    response.throwable?.message?.let { appendLine("throwable: $it") }
                }
            }
        }
    }

    private fun DemoPost.toPrettyText(): String {
        return buildString {
            appendLine("请求成功")
            appendLine()
            appendLine("id: $id")
            appendLine("userId: $userId")
            appendLine("title: $title")
            appendLine()
            appendLine(body)
        }
    }
}
