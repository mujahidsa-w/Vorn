package com.vexoapp.vexo.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.vexoapp.vexo.data.AuthRepository
import kotlinx.coroutines.launch

@Composable
fun AuthScreen(repo: AuthRepository, onSignedIn: () -> Unit) {
    var isSignUp by remember { mutableStateOf(false) }
    var username by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Vexo", style = MaterialTheme.typography.displaySmall)
        Spacer(Modifier.height(32.dp))

        if (isSignUp) {
            OutlinedTextField(
                value = displayName, onValueChange = { displayName = it },
                label = { Text("الاسم الظاهر") }, singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(12.dp))
        }
        OutlinedTextField(
            value = username, onValueChange = { username = it.trim() },
            label = { Text("اسم المستخدم (إنجليزي)") }, singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = password, onValueChange = { password = it },
            label = { Text("كلمة السر") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth()
        )

        error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }

        Spacer(Modifier.height(20.dp))
        Button(
            enabled = !busy && username.isNotBlank() && password.isNotBlank(),
            onClick = {
                busy = true; error = null
                scope.launch {
                    try {
                        if (isSignUp) repo.signUp(username, displayName, password)
                        else repo.signIn(username, password)
                        onSignedIn()
                    } catch (e: Exception) {
                        error = e.message ?: "صار خطأ"
                    } finally {
                        busy = false
                    }
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            else Text(if (isSignUp) "إنشاء حساب" else "تسجيل الدخول")
        }

        TextButton(onClick = { isSignUp = !isSignUp; error = null }) {
            Text(if (isSignUp) "عندي حساب، سجّل دخول" else "ما عندي حساب، سجّل جديد")
        }
    }
}
