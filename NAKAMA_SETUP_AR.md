# إعداد Nakama لمشروع VORN

## ما أُضيف إلى المشروع
- `nakama_server/docker-compose.yml`: Nakama + PostgreSQL للتجربة المحلية.
- `nakama_server/data/modules/index.js`: Match authoritative مبدئي، Matchmaker، حد 10 لاعبين، حجز مقاعد للدفعة الجديدة، والسماح بالانضمام المتأخر عندما يوجد مقعد.
- `nakama_server/.env.example`: مفاتيح محلية يجب تغييرها.
- نظام ENet القديم بقي كما هو كخيار احتياطي. لم أبدّل واجهة اللعب إليه بشكل غير مختبر.

## تشغيل السيرفر محلياً على Windows
1. ثبّت Docker Desktop وشغّله.
2. افتح PowerShell داخل مجلد `nakama_server`.
3. انسخ `.env.example` إلى `.env` وغيّر كل كلمات المرور والمفاتيح.
4. نفّذ `docker compose up -d`.
5. لوحة الإدارة المحلية: `http://127.0.0.1:7351`، واجهة API: `http://127.0.0.1:7350`.
6. راقب السجل بالأمر `docker compose logs -f nakama`.

## ربط Godot 4
نزّل Nakama Godot 4 SDK من المستودع الرسمي:
https://github.com/heroiclabs/nakama-godot
ثم اتبع صفحة التثبيت الرسمية وأضف `Nakama.gd` كـ Autoload:
https://heroiclabs.com/docs/nakama/client-libraries/godot/

## ما لم يكتمل بعد
هذه المرحلة تجهّز خدمة Nakama الخلفية وتسجيل المباراة والـ matchmaking. عميل Godot داخل اللعبة لم يُحوّل بعد من ENet إلى Nakama، ومزامنة اللاعب تحتاج ربطاً واختباراً مع `match.gd` و`remote_actor.gd`. كما أن احتساب ضرر الرصاص النهائي يحتاج نقل فحص التصادم والـ raycast وقواعد الأسلحة إلى محاكاة موثوقة على الخادم؛ لا يجوز الوثوق بنتيجة إصابة يرسلها العميل.

## الاستضافة العامة
Docker Compose هنا للتجربة المحلية فقط. للعب من أجهزة عبر الإنترنت يجب نشر Nakama على خادم عام، وفتح المنافذ المطلوبة، وتأمين الاتصال عبر HTTPS/WSS وreverse proxy. لا يوجد خادم عام تم إنشاؤه أو نشره تلقائياً بهذه الحزمة.
