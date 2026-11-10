package com.vexoapp.vexo.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.vexoapp.vexo.data.Room
import com.vexoapp.vexo.data.ChatRepository
import kotlinx.coroutines.flow.collectLatest

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoomsScreen(repo: ChatRepository, onOpen: (Room) -> Unit, onSignOut: () -> Unit) {
    var rooms by remember { mutableStateOf<List<Room>>(emptyList()) }
    LaunchedEffect(Unit) {
        repo.observeRooms().collectLatest { rooms = it }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("الغرف") },
                actions = { TextButton(onClick = onSignOut) { Text("خروج") } }
            )
        }
    ) { padding ->
        if (rooms.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = androidx.compose.ui.Alignment.Center) {
                Text("ما في غرف بعد")
            }
        } else {
            LazyColumn(Modifier.padding(padding)) {
                items(rooms) { room ->
                    ListItem(
                        headlineContent = { Text(room.title) },
                        supportingContent = { Text(room.game) },
                        modifier = Modifier.clickable { onOpen(room) }
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
