# ترجمة Happy للعربية (قيد العمل)

ترجمة عربية لتطبيق [Happy](https://github.com/slopus/happy) (عميل جوال لـ Claude Code وCodex، رخصة MIT)، تمهيدًا لإرسالها لأصحاب المشروع.

## الملفات
- `0001-add-arabic-translation.patch`: كل التعديلات في commit واحد، مبني على الـ commit المكتوب في `BASE_COMMIT`. الملفات المولّدة مستبعدة منه وتنبني بأوامر التوليد تحت.

## وش فيه
- **النصوص المشتركة:** `packages/happy-i18n/translations/ar.json`، فيه 909 نص مشترك بين الآيفون وأندرويد.
- **قاعدة الجمع العربية `plural-ar`:** فيها حالات صفر ومفرد ومثنى و3–10 و11–99 وغيرها. أُضيفت في:
  - ملف الترجمات `catalogs.mjs`، مع اختبار لها.
  - كود الآيفون في `TranslationCatalog.swift`.
  - مولّد أندرويد.
- **قائمة اللغات:** العربية أُضيفت في الآيفون (`AppLanguage.swift`) وأندرويد (`Languages.kt`).
- **نصوص أندرويد الخاصة:** 2230 نص في `values-ar/strings_*.xml` على 56 ملف، فيها 42 نص جمع بالحالات الست.
- **اختبارات أندرويد:** تحدّثت للغة الجديدة في `AndroidStringsTranslatedTest` و`LanguageTest` و`TranslationResourcesTest`.

## طريقة التطبيق
```sh
git checkout "$(cat BASE_COMMIT)"
git am 0001-add-arabic-translation.patch
node packages/happy-ios/scripts/generate-translations.mjs
node packages/happy-android/tools/translations/generate.mjs
node --test packages/happy-i18n/catalogs.test.mjs
```

## الحالة
- **تم وتجرّب:**
  - تطبيق التعديلات على نسخة جديدة من المشروع.
  - أوامر التوليد للآيفون وأندرويد.
  - اختبارات `catalogs.test.mjs`، ونجحت 3 من 3.
  - نسخة مطابقة لفحص `AndroidStringsTranslatedTest`، وما فيها ولا مشكلة.
- **باقي في الآيفون، ولازم قبل الإرسال:** حوالي 250 نص خاص بالآيفون في `NativeTranslations*.swift`، وفي ملفات `HappyUI/Strings` (`HeaderStatus` و`MessageSelection` و`ChatActions`). اختبارات Swift تشترط إن كل لغة في `AppLanguage.supported` مكتملة فيها.
- **باقي: اتجاه الواجهة من اليمين لليسار.** واجهة الآيفون مبنية بإطارات يدوية في `HappyLayout`، وأندرويد يحتاج تجربة على جهاز.
- **ما تجرّب:** اختبارات Gradle وSwift نفسها، لأن Android SDK وأدوات Swift مو موجودة في الجلسة السحابية.
- **الإرسال لأصحاب المشروع:** نسخة المشروع على GitHub (fork) وPull Request تنتظر موافقة صاحب الحساب.
