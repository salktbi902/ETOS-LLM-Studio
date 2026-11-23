# تفضيلات وحالة Claude لهذا المشروع

## اللغة والأسلوب
- الرد دائمًا بالعربية، في كل شيء.
- أسلوب caveman المختصر: الجواب أولًا، بدون مجاملات. الكود والأوامر والمسارات والأخطاء تبقى حرفية.

## المهارات
- المهارات محلية في `.claude/skills/` ولا تُرفع إلى GitHub، وهذا اختيار المستخدم. `.claude/` مُتجاهَل في `.gitignore` بطلبه.
- المثبّت حاليًا 81 مهارة في `.claude/skills/`:
  - حزمة `backnotprop/pstack` كاملة، 58 مهارة. منها `arena` و`poteto-mode` و`setup-pstack` و`tdd` ومهارات `principle-*`.
  - مهارات `caveman` وملحقاتها، 23 مهارة.
  - `find-skills`.
- أوامر إعادة التثبيت:
  ```
  npx -y skills add backnotprop/pstack --all -a claude-code -y
  npx -y skills add JuliusBrussee/caveman -a claude-code -y
  npx -y skills add vercel-labs/skills --skill find-skills -a claude-code -y
  ```
- لا تُثبَّت مهارة جديدة بدون موافقة المستخدم.
- مهارات Caveman Cloud (`caveman-setup` و`caveman-discover` و`caveman-manage`) تمرّر الطلبات عبر بوابة خارجية، ولا تُشغَّل إلا بطلب صريح.
- اختيار المهارة حسب المهمة:
  - `surgical-patch` للإصلاح.
  - `safe-refactor` لإعادة الهيكلة.
  - `verify-and-stop` للتحقق.
  - `caveman-commit` للـ commits.
  - `caveman-review` للمراجعة.
  - `arena` لتوليد عدة مرشحين ثم اختيار الأفضل، وتُستدعى بـ `/arena` فقط.

## الحالة المعلقة
- المثبّت ينشئ مجلدي `.agents/` و`agent/` كنسخ لأدوات أخرى، وهما غير متتبعين. القرار بين إضافتهما إلى `.gitignore` أو حذفهما ما زال عند المستخدم.
- `arena` تحتاج ملف `pstack-models.md` ليحدد النماذج. غير موجود بعد، وينشئه `/setup-pstack` بعد موافقة المستخدم.
- `skills-lock.json` مرفوع على GitHub، وفيه سجل كل المهارات المثبتة. بعد انتهاء الحاوية تكفي أوامر التثبيت أعلاه لاستعادتها.

## ملاحظة
- Claude لا يقرأ هذا الملف تلقائيًا في جلسة جديدة. اكتب "اقرأ claude-preferences.md" في بداية الجلسة.
