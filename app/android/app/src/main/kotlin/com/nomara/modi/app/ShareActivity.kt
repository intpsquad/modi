package com.nomara.modi.app

import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputFilter
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * S-25-D 외부 공유 등록: OS 공유 시트("공유하기")로 받은 링크/텍스트를 앱을 열지 않고 바로
 * 아카이브에 등록하는 순수 네이티브 화면(Flutter 엔진을 띄우지 않는다). specs/0014 참고.
 *
 * 로그인 세션은 Firebase Auth Android SDK가 앱 프로세스 전역(네이티브 SharedPreferences)에
 * 이미 영속화해두므로, Dart 쪽 코드 변경이나 flutter_secure_storage 없이
 * FirebaseAuth.getInstance().currentUser로 바로 접근한다.
 *
 * 방 선택 → 폴더 선택(또는 생성) → 등록을 하나의 액티비티 안에서 AlertDialog를 순차적으로
 * 띄우는 방식으로 구현한다(공유 타겟 액티비티의 경량 패턴 — 코루틴/OkHttp 의존성 없이
 * ExecutorService + HttpURLConnection + org.json만 사용).
 *
 * 2026-08-09: 제목 입력 단계를 없앴다 — 폴더를 고르거나 새로 만드는 순간 공유된 값을 제목으로
 * 그대로 등록한다(사용자 확정, specs/0014-외부-공유-등록.md). 다이얼로그도 기본 `setItems`
 * 목록 대신 [ShareTokens]로 브랜드 톤을 입힌 커스텀 뷰를 쓴다(iOS ShareViewController와 같은 방향).
 */
class ShareActivity : AppCompatActivity() {

    private companion object {
        const val NEW_FOLDER_LABEL = "＋ 새 폴더 만들기"
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private data class RoomOption(val id: Long, val name: String)
    private data class FolderOption(val id: Long, val name: String)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val sharedText = intent?.takeIf { it.action == Intent.ACTION_SEND }
            ?.getStringExtra(Intent.EXTRA_TEXT)
            ?.trim()
        if (sharedText.isNullOrEmpty()) {
            finish()
            return
        }
        // 🔴 "문자열 전체가 URL 인가"가 아니라 "텍스트 안에 URL 이 있는가"를 본다.
        // 네이버 지도처럼 설명 + 링크를 함께 보내는 앱이 많다 — 이유와 실측은 SharedTextUrl.
        val extractedUrl = SharedTextUrl.extract(sharedText)
        val isUrl = extractedUrl != null
        // 링크를 찾았으면 **그 링크만** 서버로 보낸다. 나머지 설명은 버린다 —
        // 제목은 크롤링한 것(네이버는 가게명)이 훨씬 깔끔하고, 기존 URL 공유 동작과도 같다.
        val content = extractedUrl ?: sharedText

        val user = FirebaseAuth.getInstance().currentUser
        if (user == null) {
            showFinishingDialog("앱을 열어 로그인해주세요")
            return
        }
        user.getIdToken(false).addOnCompleteListener { task ->
            runIfAlive {
                val token = if (task.isSuccessful) task.result?.token else null
                if (token == null) {
                    showFinishingDialog("앱을 열어 로그인해주세요")
                } else {
                    fetchRooms(token, content, isUrl)
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdownNow()
    }

    /**
     * 백그라운드 스레드(executor)나 Firebase 콜백에서 메인 스레드로 돌아와 다이얼로그를 띄우기 전에
     * 액티비티가 이미 종료(뒤로가기 등)되지 않았는지 확인한다. 종료된 뒤에 AlertDialog를 띄우면
     * WindowManager.BadTokenException으로 앱 전체가 죽는다 — 느린 네트워크 응답 도중 사용자가
     * 뒤로가기를 누르는 흔한 시나리오에서 재현된다.
     */
    private fun runIfAlive(action: () -> Unit) {
        if (!isFinishing && !isDestroyed) {
            action()
        }
    }

    // ---- 1단계: 방 목록 조회 ----

    private fun fetchRooms(token: String, content: String, isUrl: Boolean) {
        executor.execute {
            try {
                val body = httpRequest("GET", "/rooms", token, null)
                val array = JSONArray(body)
                val rooms = mutableListOf<RoomOption>()
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    if (obj.optString("status") == "ACTIVE") {
                        rooms.add(RoomOption(obj.getLong("id"), obj.getString("name")))
                    }
                }
                mainHandler.post { runIfAlive { onRoomsLoaded(rooms, token, content, isUrl) } }
            } catch (e: Exception) {
                android.util.Log.w("ShareActivity", "방 목록 조회 실패", e)
                mainHandler.post { runIfAlive { showFinishingDialog("등록하지 못했어요") } }
            }
        }
    }

    private fun onRoomsLoaded(
        rooms: List<RoomOption>,
        token: String,
        content: String,
        isUrl: Boolean,
    ) {
        if (rooms.isEmpty()) {
            showFinishingDialog("진행 중인 방이 없어요")
            return
        }
        if (rooms.size == 1) {
            fetchFolders(token, rooms[0].id, content, isUrl)
            return
        }

        lateinit var dialog: AlertDialog
        val rows = rooms.map { room ->
            makeListRow(room.name) {
                dialog.dismiss()
                fetchFolders(token, room.id, content, isUrl)
            }
        }.toMutableList<View>()
        rows.add(makeCancelRow { dialog.dismiss(); finish() })

        dialog = AlertDialog.Builder(this)
            .setCustomTitle(makeTitleView("등록할 방을 선택해주세요"))
            .setView(buildContainer(rows))
            .setOnCancelListener { finish() }
            .create()
        dialog.show()
    }

    // ---- 2단계: 폴더 목록 조회 ----

    private fun fetchFolders(token: String, roomId: Long, content: String, isUrl: Boolean) {
        executor.execute {
            try {
                val body = httpRequest("GET", "/rooms/$roomId/archive/folders", token, null)
                val array = JSONArray(body)
                val folders = mutableListOf<FolderOption>()
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    folders.add(FolderOption(obj.getLong("id"), obj.getString("name")))
                }
                mainHandler.post {
                    runIfAlive { onFoldersLoaded(folders, token, roomId, content, isUrl) }
                }
            } catch (e: Exception) {
                android.util.Log.w("ShareActivity", "폴더 목록 조회 실패", e)
                mainHandler.post { runIfAlive { showFinishingDialog("등록하지 못했어요") } }
            }
        }
    }

    private fun onFoldersLoaded(
        folders: List<FolderOption>,
        token: String,
        roomId: Long,
        content: String,
        isUrl: Boolean,
    ) {
        // 폴더가 하나도 없어도 앱에 들어가지 않고 바로 새 폴더를 만들어 등록할 수 있게 한다
        // (specs/0014 개정 QA). 예전엔 여기서 "앱에서 먼저 폴더를 만들어주세요"로 종료했다.
        if (folders.isEmpty()) {
            promptNewFolder(token, roomId, content, isUrl)
            return
        }

        lateinit var dialog: AlertDialog
        val rows = folders.map { folder ->
            makeListRow(folder.name) {
                dialog.dismiss()
                // 폴더를 고른 순간 그 즉시 등록한다 — 제목 입력 단계 없음(2026-08-09 확정).
                registerNow(token, roomId, folder.id, content, isUrl)
            }
        }.toMutableList<View>()
        // 폴더가 있어도 새 폴더를 바로 만들 수 있게 선택지를 추가한다.
        rows.add(
            makeListRow(NEW_FOLDER_LABEL, textColor = ShareTokens.primary) {
                dialog.dismiss()
                promptNewFolder(token, roomId, content, isUrl)
            }
        )
        rows.add(makeCancelRow { dialog.dismiss(); finish() })

        dialog = AlertDialog.Builder(this)
            .setCustomTitle(makeTitleView("등록할 폴더를 선택해주세요"))
            .setView(buildContainer(rows))
            .setOnCancelListener { finish() }
            .create()
        dialog.show()
    }

    /**
     * 공유 흐름 안에서 새 아카이브 폴더를 만드는 이름 입력 화면(QA).
     * 앱 내 폴더 추가 다이얼로그(archive_screen.dart)의 패턴을 미러링한다(최대 20자).
     * errorMessage가 있으면(생성 실패 재시도) 위에 빨간 안내를 보여준다.
     */
    private fun promptNewFolder(
        token: String,
        roomId: Long,
        content: String,
        isUrl: Boolean,
        errorMessage: String? = null,
    ) {
        val nameInput = EditText(this).apply {
            hint = "폴더 이름"
            filters = arrayOf(InputFilter.LengthFilter(20))
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setStroke(dp(1), ShareTokens.border)
                setColor(ShareTokens.surface)
            }
        }

        lateinit var dialog: AlertDialog
        val views = mutableListOf<View>()
        if (errorMessage != null) views.add(makeErrorText(errorMessage))
        views.add(nameInput)
        views.add(
            makePrimaryButton("만들기") {
                val name = nameInput.text.toString().trim()
                if (name.isEmpty()) {
                    Toast.makeText(this, "이름을 입력해 주세요", Toast.LENGTH_SHORT).show()
                } else {
                    dialog.dismiss()
                    createFolder(token, roomId, name, content, isUrl)
                }
            }
        )
        views.add(makeCancelRow { dialog.dismiss(); finish() })

        dialog = AlertDialog.Builder(this)
            .setCustomTitle(makeTitleView("새 폴더 만들기"))
            .setView(buildContainer(views))
            .setOnCancelListener { finish() }
            .create()
        dialog.show()
    }

    private fun createFolder(
        token: String,
        roomId: Long,
        name: String,
        content: String,
        isUrl: Boolean,
    ) {
        executor.execute {
            try {
                val payload = JSONObject().apply { put("name", name) }
                val body = httpRequest(
                    "POST",
                    "/rooms/$roomId/archive/folders",
                    token,
                    payload.toString(),
                )
                val folderId = JSONObject(body).getLong("id")
                mainHandler.post {
                    runIfAlive {
                        // 만든 폴더로 바로 등록한다.
                        registerNow(token, roomId, folderId, content, isUrl)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("ShareActivity", "폴더 생성 실패", e)
                mainHandler.post {
                    runIfAlive {
                        promptNewFolder(
                            token,
                            roomId,
                            content,
                            isUrl,
                            errorMessage = "폴더를 만들지 못했어요. 다시 시도해주세요",
                        )
                    }
                }
            }
        }
    }

    // ---- 3단계: 등록(폴더 확정 즉시 자동 등록, 2026-08-09) ----

    /**
     * 방·폴더가 확정된 순간(기존 폴더 선택 또는 새 폴더 생성 직후) 공유된 값을 제목으로 그대로
     * 등록한다. 제목을 따로 입력받지 않는다 — 사용자 확정.
     */
    private fun registerNow(
        token: String,
        roomId: Long,
        folderId: Long,
        content: String,
        isUrl: Boolean,
    ) {
        val progressDialog = AlertDialog.Builder(this)
            .setCustomTitle(makeTitleView("모아보기에 등록"))
            .setView(buildContainer(listOf(makeProgressRow("모아보기에 등록하고 있어요"))))
            .setCancelable(false)
            .create()
        progressDialog.show()

        executor.execute {
            try {
                val payload = JSONObject().apply {
                    put("title", content)
                    if (isUrl) put("url", content) else put("text", content)
                }
                httpRequest(
                    "POST",
                    "/rooms/$roomId/archive/folders/$folderId/items/pending",
                    token,
                    payload.toString(),
                )
                mainHandler.post {
                    runIfAlive {
                        progressDialog.dismiss()
                        Toast.makeText(this, "모아보기에 등록했어요", Toast.LENGTH_SHORT).show()
                        finish()
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("ShareActivity", "등록 실패", e)
                mainHandler.post {
                    runIfAlive {
                        progressDialog.dismiss()
                        showRegisterRetry(token, roomId, folderId, content, isUrl)
                    }
                }
            }
        }
    }

    /** 등록 실패 — 인라인 에러 + 다시 시도(같은 방·폴더로 재호출)/취소만 보여준다(제목 재입력 없음). */
    private fun showRegisterRetry(
        token: String,
        roomId: Long,
        folderId: Long,
        content: String,
        isUrl: Boolean,
    ) {
        lateinit var dialog: AlertDialog
        val views = mutableListOf<View>(makeErrorText("등록하지 못했어요. 다시 시도해주세요"))
        views.add(
            makePrimaryButton("다시 시도") {
                dialog.dismiss()
                registerNow(token, roomId, folderId, content, isUrl)
            }
        )
        views.add(makeCancelRow { dialog.dismiss(); finish() })

        dialog = AlertDialog.Builder(this)
            .setView(buildContainer(views))
            .setOnCancelListener { finish() }
            .create()
        dialog.show()
    }

    // ---- 공통 다이얼로그 UI 헬퍼(design.md 톤 커스텀 뷰, 2026-08-09) ----

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun buildContainer(views: List<View>): View {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(4), dp(20), dp(20))
        }
        views.forEach { container.addView(it) }
        return ScrollView(this).apply { addView(container) }
    }

    private fun makeTitleView(text: String): TextView = TextView(this).apply {
        this.text = text
        setTextColor(ShareTokens.foreground)
        textSize = 18f
        setTypeface(typeface, Typeface.BOLD)
        setPadding(dp(20), dp(20), dp(20), dp(8))
    }

    /** 방·폴더 행처럼 여러 개를 나열하는 리스트 아이템 — surfaceSoft 배경 + 왼쪽 정렬(design.md 카드 톤). */
    private fun makeListRow(
        label: String,
        textColor: Int = ShareTokens.foreground,
        onClick: () -> Unit,
    ): TextView = TextView(this).apply {
        text = label
        setTextColor(textColor)
        textSize = 16f
        gravity = Gravity.CENTER_VERTICAL or Gravity.START
        setPadding(dp(16), dp(14), dp(16), dp(14))
        background = GradientDrawable().apply {
            cornerRadius = dp(12).toFloat()
            setColor(ShareTokens.surfaceSoft)
        }
        isClickable = true
        isFocusable = true
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(4); bottomMargin = dp(4) }
    }

    /** 강조 CTA(만들기/다시 시도) — primary 채움 + 흰 글씨(design.md 버튼 톤). */
    private fun makePrimaryButton(label: String, onClick: () -> Unit): TextView = TextView(this).apply {
        text = label
        setTextColor(ShareTokens.onPrimary)
        textSize = 16f
        gravity = Gravity.CENTER
        setPadding(dp(16), dp(14), dp(16), dp(14))
        background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(ShareTokens.primary)
        }
        isClickable = true
        isFocusable = true
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) }
    }

    private fun makeCancelRow(onClick: () -> Unit): TextView = TextView(this).apply {
        text = "취소"
        setTextColor(ShareTokens.foreground)
        textSize = 16f
        gravity = Gravity.CENTER
        setPadding(dp(16), dp(12), dp(16), dp(12))
        isClickable = true
        isFocusable = true
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(4) }
    }

    private fun makeErrorText(message: String): TextView = TextView(this).apply {
        text = message
        setTextColor(ShareTokens.danger)
        textSize = 14f
        gravity = Gravity.CENTER
        setPadding(0, 0, 0, dp(8))
    }

    private fun makeProgressRow(message: String): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, dp(8))
        }
        val spinner = ProgressBar(this).apply {
            indeterminateTintList = android.content.res.ColorStateList.valueOf(ShareTokens.primary)
        }
        row.addView(spinner)
        val label = TextView(this).apply {
            text = message
            setTextColor(ShareTokens.muted)
            textSize = 14f
            setPadding(dp(12), 0, 0, 0)
        }
        row.addView(label)
        return row
    }

    private fun showFinishingDialog(message: String) {
        AlertDialog.Builder(this)
            .setMessage(message)
            .setPositiveButton("확인") { d, _ -> d.dismiss() }
            .setOnDismissListener { finish() }
            .show()
    }

    /** 2xx가 아니면 예외를 던진다. 호출부는 백그라운드 스레드에서 실행할 것. */
    private fun httpRequest(
        method: String,
        path: String,
        token: String,
        jsonBody: String?,
    ): String {
        val url = URL(BuildConfig.API_BASE_URL + path)
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.setRequestProperty("Authorization", "Bearer $token")
            if (jsonBody != null) {
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true
                val bytes = jsonBody.toByteArray(StandardCharsets.UTF_8)
                connection.outputStream.use { it.write(bytes) }
            }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val responseBody = stream?.let { readAll(it) } ?: ""
            if (code !in 200..299) {
                throw IllegalStateException("HTTP $code: $responseBody")
            }
            return responseBody
        } finally {
            connection.disconnect()
        }
    }

    private fun readAll(stream: java.io.InputStream): String {
        BufferedReader(InputStreamReader(stream, StandardCharsets.UTF_8)).use { reader ->
            return reader.readText()
        }
    }
}

/**
 * specs/design.md · app/lib/design/tokens.dart 미러링(네이티브 토큰 생성은 하지 않음) — iOS
 * ShareViewController의 UIConstants와 짝. [ShareActivity]의 커스텀 다이얼로그 뷰들이 쓴다.
 */
private object ShareTokens {
    val primary = 0xFFFF385C.toInt()
    val onPrimary = 0xFFFFFFFF.toInt()
    val foreground = 0xFF222222.toInt()
    val muted = 0xFF6A6A6A.toInt()
    val border = 0xFFDDDDDD.toInt()
    val surfaceSoft = 0xFFF7F7F7.toInt()
    val surface = 0xFFFFFFFF.toInt()
    val danger = 0xFFC13515.toInt()
}
