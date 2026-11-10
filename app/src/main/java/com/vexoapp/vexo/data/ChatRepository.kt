package com.vexoapp.vexo.data

import android.net.Uri
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.util.UUID

class ChatRepository(
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance(),
    private val storage: FirebaseStorage = FirebaseStorage.getInstance()
) {
    /** Rooms are created in Firestore (collection "rooms"), e.g. one per game. */
    fun observeRooms(): Flow<List<Room>> = callbackFlow {
        val reg = db.collection("rooms").addSnapshotListener { snap, err ->
            if (err != null) return@addSnapshotListener
            trySend(snap?.documents?.mapNotNull { doc ->
                doc.toObject(Room::class.java)?.copy(id = doc.id)
            }.orEmpty())
        }
        awaitClose { reg.remove() }
    }

    fun observeMessages(roomId: String): Flow<List<ChatMessage>> = callbackFlow {
        val reg = db.collection("rooms").document(roomId).collection("messages")
            .orderBy("createdAt", Query.Direction.ASCENDING)
            .limitToLast(200)
            .addSnapshotListener { snap, err ->
                if (err != null) return@addSnapshotListener
                trySend(snap?.documents?.mapNotNull { doc ->
                    doc.toObject(ChatMessage::class.java)?.copy(id = doc.id)
                }.orEmpty())
            }
        awaitClose { reg.remove() }
    }

    suspend fun sendText(roomId: String, sender: UserProfile, text: String) {
        val body = text.trim()
        if (body.isEmpty()) return
        post(roomId, sender, MessageType.TEXT, text = body)
    }

    suspend fun sendAudio(roomId: String, sender: UserProfile, localFile: Uri) {
        val path = "voice/$roomId/${UUID.randomUUID()}.m4a"
        val ref = storage.reference.child(path)
        val meta = StorageMetadata.Builder().setContentType("audio/mp4").build()
        ref.putFile(localFile, meta).await()
        val url = ref.downloadUrl.await().toString()
        post(roomId, sender, MessageType.AUDIO, audioUrl = url)
    }

    private suspend fun post(
        roomId: String,
        sender: UserProfile,
        type: MessageType,
        text: String = "",
        audioUrl: String = ""
    ) {
        val data = hashMapOf(
            "senderId" to sender.uid,
            "senderName" to sender.displayName,
            "type" to type.name,
            "text" to text,
            "audioUrl" to audioUrl,
            "createdAt" to com.google.firebase.firestore.FieldValue.serverTimestamp()
        )
        db.collection("rooms").document(roomId).collection("messages").add(data).await()
    }
}
