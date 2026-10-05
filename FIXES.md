# تقرير إصلاح WHAH AI — الإصدار 1.1.0

## المشاكل التي تم إصلاحها

### 1. عدم الاتصال بالمزود
- تحسين بناء رابط `_url` لتجنب تكرار `/chat/completions`
- إضافة رؤوس صحيحة لـ OpenRouter و Gateway
- مهلة اتصال 120 ثانية مع رسائل خطأ عربية واضحة
- زر **اختبار الاتصال** داخل الإعدادات

### 2. file_picker 13.x (كسر API)
- استبدال `FilePicker.platform.pickFiles(allowMultiple:, withData:)` 
  بـ `FilePicker.pickFiles()` الذي يعيد `List<PlatformFile>` مباشرة
- استخدام `file.lengthSync()` بدل `file.size`

### 3. النسخ واللصق
- إضافة `import 'package:flutter/services.dart'`
- زر لصق من الحافظة في شريط الإدخال
- نص الرسائل قابل للتحديد والنسخ (SelectableRegion + Markdown selectable)

### 4. الواجهة (تصميم Claude / أزرق خفيف)
- ألوان أزرق فاتح (`#3B82F6`, `#F0F7FF`)
- فقاعات محادثة مستديرة
- شريط جانبي بتدرج أزرق
- دعم RTL كامل + `flutter_localizations`

### 5. السرعة (مثل GPT / Claude)
- Streaming مفعّل افتراضياً
- خيار تفعيله/إيقافه من الإعدادات
- fallback تلقائي للوضع العادي إذا فشل البث

### 6. مزودو الذكاء
- OpenRouter / OpenAI / Groq / NVIDIA NIM / Together
- **Gateway** و **Custom** للإدخال اليدوي الكامل

### 7. Features جديدة
- **Skills**: برمجة، تحليل بيانات، تحويل مستند، تلخيص، ترجمة، أفكار
- **التطبيقات المرتبطة**: إدخال اسم + رابط (GitHub وغيره) وحفظها
- سجل محادثات مع حذف
- System Prompt قابل للتعديل
- رفع ملفات (أي نوع)

## كيفية الرفع إلى GitHub

```bash
git clone https://github.com/tayebi7/whah-ai.git
cd whah-ai
# انسخ محتويات whah-ai-fixed فوق المشروع
cp -r path/to/whah-ai-fixed/* .
git add .
git commit -m "fix: connection, file_picker 13, UI Claude-blue, skills, streaming"
git push origin main
```

بعد الدفع: تبويب Actions → حمّل APK من Artifacts.
