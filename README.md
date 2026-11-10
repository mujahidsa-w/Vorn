# Vexo

شات جيمنغ بـ Flutter، يشتغل على أندرويد وآيفون.

## الميزات
- تسجيل دخول وإنشاء حساب باسم مستخدم وكلمة سر (Firebase Auth)
- غرف دردشة حسب اللعبة
- رسائل نصية فورية (Firestore)
- رسائل صوتية: اضغط مطولاً على الميكروفون وأفلت للإرسال (Firebase Storage)

## البناء
الـ workflow في `.github/workflows/flutter.yml` بيبني:
- **APK** للأندرويد (artifact: `vexo-android-apk`)
- **IPA غير موقع** للآيفون (artifact: `vexo-ios-unsigned-ipa`)

الـ workflow بيولّد مجلدات `android/` و`ios/` تلقائياً عن طريق `flutter create`، فما بنحتاج نرفعها.

## Firebase
- إعدادات Firebase بالكود في `lib/firebase_options.dart` (مشروع `ms-company-e7166`).
- قواعد Firestore في `firestore.rules`، وقواعد Storage في `storage.rules`. انسخهم بالـ Console.
- فعّل Email/Password من Authentication، وأنشئ Firestore وStorage.
- أنشئ غرفة يدوياً في Firestore: collection `rooms` وفيه document بحقول `title` و`game`.

## تنبيه أمني
قيّد مفاتيح الـ API من Google Cloud Console (Android key على package `com.vexoapp.vexo`، وiOS key على bundle `com.vexoapp.vexo`).
