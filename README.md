# Vexo: شات جيمنغ لأندرويد (MVP)

الميزات الحالية:
- تسجيل دخول وإنشاء حساب باسم مستخدم وكلمة سر
- غرف دردشة (حسب اللعبة)
- رسائل نصية فورية
- رسائل صوتية (اضغط مطولاً على 🎤 وأفلت للإرسال)

الميزات الجاية: الاتصال الصوتي والفيديو (WebRTC) والإشعارات.

## التشغيل

1. افتح مجلد `vexo-chat` في Android Studio (Ladybug أو أحدث).
2. Android Studio بيولّد Gradle Wrapper تلقائياً عند أول فتح.
3. في Firebase Console (مشروع `ms-company-e7166`):
   - **Authentication** ← فعّل Email/Password
   - **Firestore** ← أنشئ قاعدة بيانات، وانسخ محتوى `firestore.rules`
   - **Storage** ← فعّل، وانسخ محتوى `storage.rules`
   - (Storage يحتاج خطة Blaze)
4. أنشئ غرفة تجريبية يدوياً: Firestore ← collection `rooms` ← document بحقول:
   - `title` (string): مثلاً "عام - Valorant"
   - `game` (string): "Valorant"
5. اضغط Run.

## ملاحظات أمان

- `app/google-services.json` فيه API key. لا ترفعه على GitHub عام. أضفه لـ `.gitignore`.
- من Google Cloud Console قيّد الـ API key على package name `com.vexoapp.vexo`.
- قواعد Firestore الحالية تمنع إنشاء الغرف من التطبيق؛ تنشئها من الـ Console.

## ملاحظة عن التسجيل

تسجيل الدخول باسم المستخدم يتم عبر Firebase Auth بإيميل وهمي `<username>@vexo.local`، فما تحتاج إيميل حقيقي. اسم المستخدم لازم يكون إنجليزي وفريد.
