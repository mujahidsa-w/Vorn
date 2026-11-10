package com.vexoapp.vexo.data

import com.google.firebase.Timestamp

data class UserProfile(
    val uid: String = "",
    val name: String = "",
    val displayName: String = ""
)

data class Room(
    val id: String = "",
    val title: String = "",
    val game: String = ""
)

enum class MessageType { TEXT, AUDIO }

data class ChatMessage(
    val id: String = "",
    val senderId: String = "",
    val senderName: String = "",
    val type: String = MessageType.TEXT.name,
    val text: String = "",
    val audioUrl: String = "",
    val createdAt: Timestamp? = null
)
