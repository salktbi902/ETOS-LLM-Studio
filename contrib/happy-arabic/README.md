# ترجمة Happy للعربية (قيد العمل)

ترجمة عربية لتطبيق [Happy](https://github.com/slopus/happy) (عميل جوال لـ Claude Code وCodex، رخصة MIT)، تمهيدًا لإرسالها لأصحاب المشروع.

## الملفات
- `ar.json`: النصوص المشتركة بين الآيفون وأندرويد، 909 نص، تنحط في `packages/happy-i18n/translations/ar.json`.
- `happy-arabic-wip.patch`: تعديلات الكود، مبنية على الـ commit المكتوب في `BASE_COMMIT`:
  - قاعدة جمع عربية `plural-ar` (صفر، مفرد، مثنى، 3–10، 11–99، غيرها) في `catalogs.mjs` وفي Swift وفي مولّد أندرويد.
  - اختبار لقاعدة الجمع العربية في `catalogs.test.mjs`.
  - إضافة العربية لقائمة اللغات في الآيفون (`AppLanguage.swift`) وأندرويد (`Languages.kt`).

## طريقة التطبيق
```sh
git checkout "$(cat BASE_COMMIT)"
git apply happy-arabic-wip.patch
cp ar.json packages/happy-i18n/translations/ar.json
node packages/happy-ios/scripts/generate-translations.mjs
node packages/happy-android/tools/translations/generate.mjs
node --test packages/happy-i18n/catalogs.test.mjs
```

## الحالة
- تم: النصوص المشتركة كاملة، وقاعدة الجمع، وتشغيل المولّدين. اختبارات `catalogs.test.mjs` نجحت (3 من 3).
- باقي في الآيفون (لازم قبل الإرسال): حوالي 250 نص خاص بالآيفون في `NativeTranslations*.swift` وملفات `HappyUI/Strings` (`HeaderStatus` و`MessageSelection` و`ChatActions`). اختبارات Swift تشترط إن كل لغة في `AppLanguage.supported` مكتملة فيها.
- باقي في أندرويد (اختياري): حوالي 2800 نص خاص بأندرويد في `res/values-*/strings_*.xml`. الناقص منها يظهر بالإنجليزي.
- باقي: اتجاه الواجهة من اليمين لليسار. واجهة الآيفون مبنية بإطارات يدوية في `HappyLayout`، فقلب الاتجاه يحتاج شغل وتجربة على جهاز.
- ما تجرّب: اختبارات Swift وأندرويد، لأن أدواتها مو موجودة في الجلسة السحابية.
- الإرسال لأصحاب المشروع (fork وPull Request) ينتظر موافقة صاحب الحساب.
