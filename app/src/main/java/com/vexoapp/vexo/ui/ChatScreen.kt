package com.vexoapp.vexo.ui

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaPlayer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.vexoapp.vexo.audio.VoiceRecorder
import com.vexoapp.vexo.data.ChatMessage
import com.vexoapp.vexo.data.ChatRepository
import com.vexoapp.vexo.data.MessageType
import com.vexoapp.vexo.data.Room
import com.vexoapp.vexo.data.UserProfile
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import androidx.compose.foundation.gestures.detectTapGestures

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    room: Room,
    me: UserProfile,
    repo: ChatRepository,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var input by remember { mutableStateOf("") }
    var recording by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val recorder = remember { VoiceRecorder(context) }

    LaunchedEffect(room.id) {
        repo.observeMessages(room.id).collectLatest { messages = it }
    }
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    val micPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (!granted) error = "لازم تسمح بالمايك لتسجيل الصوت" }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(room.title) },
                navigationIcon = { TextButton(onClick = onBack) { Text("رجوع") } }
            )
        },
        bottomBar = {
            Column(Modifier.padding(8.dp)) {
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = input,
                        onValueChange = { input = it },
                        placeholder = { Text("اكتب رسالة") },
                        modifier = Modifier.weight(1f),
                        maxLines = 4
                    )
                    Spacer(Modifier.width(8.dp))
                    if (input.isNotBlank()) {
                        Button(onClick = {
                            val text = input
                            input = ""
                            scope.launch {
                                runCatching { repo.sendText(room.id, me, text) }
                                    .onFailure { error = it.message }
                            }
                        }) { Text("إرسال") }
                    } else {
                        // Hold to record, release to send.
                        Button(
                            onClick = {},
                            modifier = Modifier.pointerInput(Unit) {
                                detectTapGestures(
                                    onPress = {
                                        val granted = ContextCompat.checkSelfPermission(
                                            context, Manifest.permission.RECORD_AUDIO
                                        ) == PackageManager.PERMISSION_GRANTED
                                        if (!granted) {
                                            micPermission.launch(Manifest.permission.RECORD_AUDIO)
                                            return@detectTapGestures
                                        }
                                        try {
                                            recorder.start()
                                            recording = true
                                            val released = tryAwaitRelease()
                                            recording = false
                                            if (released) {
                                                val uri = recorder.stop()
                                                if (uri != null) {
                                                    scope.launch {
                                                        runCatching { repo.sendAudio(room.id, me, uri) }
                                                            .onFailure { error = it.message }
                                                    }
                                                }
                                            } else {
                                                recorder.cancel()
                                            }
                                        } catch (e: Exception) {
                                            recording = false
                                            recorder.cancel()
                                            error = "ما قدرت أسجّل الصوت"
                                        }
                                    }
                                )
                            }
                        ) { Text(if (recording) "..." else "🎤") }
                    }
                }
            }
        }
    ) { padding ->
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(messages, key = { it.id }) { msg ->
                MessageBubble(msg, mine = msg.senderId == me.uid)
            }
        }
    }
}

@Composable
private fun MessageBubble(msg: ChatMessage, mine: Boolean) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = if (mine) Alignment.End else Alignment.Start
    ) {
        Text(msg.senderName, style = MaterialTheme.typography.labelSmall)
        Surface(
            shape = RoundedCornerShape(12.dp),
            color = if (mine) MaterialTheme.colorScheme.primaryContainer
            else MaterialTheme.colorScheme.surfaceVariant
        ) {
            if (msg.type == MessageType.AUDIO.name) {
                AudioBubble(msg.audioUrl)
            } else {
                Text(msg.text, modifier = Modifier.padding(10.dp))
            }
        }
    }
}

@Composable
private fun AudioBubble(url: String) {
    var playing by remember { mutableStateOf(false) }
    val player = remember(url) { MediaPlayer() }
    DisposableEffect(url) { onDispose { player.release() } }

    Text(
        if (playing) "⏸ صوت" else "▶ رسالة صوتية",
        modifier = Modifier
            .padding(10.dp)
            .clickable {
                if (playing) {
                    player.stop(); playing = false
                } else {
                    player.reset()
                    player.setDataSource(url)
                    player.setOnCompletionListener { playing = false }
                    player.prepareAsync()
                    player.setOnPreparedListener { it.start(); playing = true }
                }
            }
    )
}
