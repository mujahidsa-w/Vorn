package com.vexoapp.vexo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import com.vexoapp.vexo.data.AuthRepository
import com.vexoapp.vexo.data.ChatRepository
import com.vexoapp.vexo.data.Room
import com.vexoapp.vexo.data.UserProfile
import com.vexoapp.vexo.ui.AuthScreen
import com.vexoapp.vexo.ui.ChatScreen
import com.vexoapp.vexo.ui.RoomsScreen
import com.vexoapp.vexo.ui.theme.VexoTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val auth by lazy { AuthRepository() }
    private val chat by lazy { ChatRepository() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            VexoTheme { AppRoot() }
        }
    }

    @Composable
    private fun AppRoot() {
        var profile by remember { mutableStateOf<UserProfile?>(null) }
        var openRoom by remember { mutableStateOf<Room?>(null) }
        var loading by remember { mutableStateOf(true) }
        val scope = rememberCoroutineScope()

        LaunchedEffect(Unit) {
            val uid = auth.currentUid
            if (uid != null) profile = runCatching { auth.loadProfile(uid) }.getOrNull()
            loading = false
        }

        val me = profile
        when {
            loading -> Unit
            me == null -> AuthScreen(auth) {
                scope.launch { profile = auth.currentUid?.let { auth.loadProfile(it) } }
            }
            openRoom == null -> RoomsScreen(
                repo = chat,
                onOpen = { openRoom = it },
                onSignOut = { auth.signOut(); profile = null }
            )
            else -> ChatScreen(
                room = openRoom!!,
                me = me,
                repo = chat,
                onBack = { openRoom = null }
            )
        }
    }
}
