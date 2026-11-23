# تفضيلات وحالة Claude لهذا المشروع

## اللغة والأسلوب
- الرد دائمًا بالعربية، في كل شيء.
- أسلوب caveman المختصر: الجواب أولًا، بدون مجاملات. الكود والأوامر والمسارات والأخطاء تبقى حرفية.

## معلومات المستخدم
- مكينة القهوة: xBloom Studio.
- وصفات xBloom تُكتب بالعربية، مع أن مهارة `xbloom-studio-recipe` تكتب بالصينية افتراضيًا.
- التحضير الفعلي على المكينة يحتاج جهاز المستخدم: بلوتوث قريب من المكينة، وبايثون، ومكتبة `bleak`، وإغلاق تطبيق xBloom على الجوال. الجلسة السحابية تصمم الوصفات فقط.

## المهارات
- المهارات محلية في `.claude/skills/` ولا تُرفع إلى GitHub، وهذا اختيار المستخدم. `.claude/` مُتجاهَل في `.gitignore` بطلبه.
- `.agents/` و`agent/` نسخ ينشئها المثبّت لأدوات أخرى، ومُتجاهَلة في `.gitignore` بقرار المستخدم.
- المثبّت حاليًا 82 مهارة في `.claude/skills/`:
  - حزمة `backnotprop/pstack` كاملة، 58 مهارة. منها `arena` و`poteto-mode` و`setup-pstack` و`tdd` ومهارات `principle-*`.
  - مهارات `caveman` وملحقاتها، 23 مهارة.
  - `find-skills`.
  - `xbloom-studio-recipe` من `ryunana/xbloom-studio-recipe-skill`: وصفات xBloom Studio وتحضيرها بالبلوتوث. رُوجعت كاملة قبل التثبيت (commit `5c429fa`).
- أوامر إعادة التثبيت:
  ```
  npx -y skills add backnotprop/pstack --all -a claude-code -y
  npx -y skills add JuliusBrussee/caveman -a claude-code -y
  npx -y skills add vercel-labs/skills --skill find-skills -a claude-code -y
  npx -y skills add ryunana/xbloom-studio-recipe-skill -a claude-code -y
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
  - `xbloom-studio-recipe` لوصفات القهوة على xBloom Studio.

## الحالة المعلقة
- `arena` تحتاج ملف `pstack-models.md` ليحدد النماذج. غير موجود بعد، وينشئه `/setup-pstack` بعد موافقة المستخدم.
- مهارة `xbloom-studio-recipe` نُسخ معها `CLAUDE.md` و`AGENTS.md`، وهما قواعد المساهمة في مستودعها ولا تخص هذا المشروع. قرار حذفهما عند المستخدم.
- `skills-lock.json` مرفوع على GitHub، وفيه سجل كل المهارات المثبتة. بعد انتهاء الحاوية تكفي أوامر التثبيت أعلاه لاستعادتها.

## ملاحظة
- Claude لا يقرأ هذا الملف تلقائيًا في جلسة جديدة. اكتب "اقرأ claude-preferences.md" في بداية الجلسة.
