package com.vexoapp.vexo

import android.app.Application
import com.google.firebase.FirebaseApp

class VexoApp : Application() {
    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
    }
}
