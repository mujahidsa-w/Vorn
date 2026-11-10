package com.vexoapp.vexo.data

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await

/**
 * Login uses a username + password. Firebase Auth needs an email,
 * so each username maps to a synthetic email: <username>@vexo.local.
 * The real display name is stored in Firestore.
 */
class AuthRepository(
    private val auth: FirebaseAuth = FirebaseAuth.getInstance(),
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance()
) {
    val currentUid: String? get() = auth.currentUser?.uid

    suspend fun signUp(username: String, displayName: String, password: String) {
        val key = normalize(username)
        require(Regex("^[a-z0-9_]{3,20}$").matches(key)) {
            "اسم المستخدم لازم يكون 3-20 حرف (إنجليزي، أرقام، _)"
        }
        require(displayName.isNotBlank()) { "الاسم مطلوب" }
        require(password.length >= 6) { "كلمة السر لازم تكون 6 أحرف على الأقل" }

        val taken = db.collection("usernames").document(key).get().await().exists()
        check(!taken) { "اسم المستخدم مستخدم، جرّب غيره" }

        val result = auth.createUserWithEmailAndPassword(emailFor(key), password).await()
        val uid = result.user!!.uid

        db.runTransaction { tx ->
            tx.set(db.collection("usernames").document(key), mapOf("uid" to uid))
            tx.set(
                db.collection("users").document(uid),
                mapOf("uid" to uid, "name" to key, "displayName" to displayName.trim())
            )
        }.await()
    }

    suspend fun signIn(username: String, password: String) {
        auth.signInWithEmailAndPassword(emailFor(normalize(username)), password).await()
    }

    suspend fun loadProfile(uid: String): UserProfile? =
        db.collection("users").document(uid).get().await().toObject(UserProfile::class.java)

    fun signOut() = auth.signOut()

    private fun normalize(username: String) = username.trim().lowercase()
    private fun emailFor(key: String) = "$key@vexo.local"
}
