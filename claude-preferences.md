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
- دفعة 2026-11-28، من مقطع techit عن أقوى إضافات Claude، بموافقة المستخدم. كُشف على كل مستودع قبل التثبيت:
  - `humanizer` من `blader/humanizer`: يشيل علامات الكتابة الآلية، وأساسه للإنجليزي.
  - `karpathy-guidelines` من `multica-ai/andrej-karpathy-skills`.
  - حزمة `obra/superpowers`، 15 مهارة، منها `brainstorming` و`systematic-debugging` و`writing-plans` و`using-superpowers`. تتقاطع مع pstack. خطاف SessionStart حقها ما انثبت، لأن مثبّت المهارات ينسخ المهارات بس.
  - حزمة `nextlevelbuilder/ui-ux-pro-max-skill`، 7 مهارات: `ui-ux-pro-max` و`design` و`design-system` و`ui-styling` و`brand` و`banner-design` و`slides`.
  - `impeccable` من `pbakaus/impeccable`: مفردات تصميم ومراجعة واجهات.
  - المهارات الأساسية من `heygen-com/hyperframes`، 6 مهارات: `hyperframes` و`hyperframes-cli` و`hyperframes-registry` و`media-use` و`reverse-any-video` و`style-sampling`. فيها وحدة telemetry داخل `media-use`.
  - `graphify`: أداة سطر أوامر تنثبت بـ uv، ومهارة على مستوى المشروع. أضافت قسمها في `CLAUDE.md` و`.claude/CLAUDE.md`، وخطافات تذكّر باستخدام الخريطة.
  - GSD من `gsd-build/get-shit-done` بملف التعريف الأساسي (`--minimal`): أوامر `/gsd-*` وخطافات في `.claude/settings.json`. الخطافات تحذّر وما تمنع: فحص التحديثات من npm، ومراقبة السياق، وحماية من حقن التعليمات، وفحص القراءة قبل التعديل. الباقي يتفعّل من الإعدادات.
- ما انثبت من نفس الدفعة:
  - `claude-mem`: ذاكرته تنحفظ على الجهاز وتنمسح مع الحاوية السحابية، ويشغّل خدمة في الخلفية تسجّل كل نشاط. يفيد على جهاز المستخدم فقط: `npx claude-mem install`.
  - `career-ops`: مشروع مستقل للبحث عن وظائف، ينشأ في مجلد خاص بـ `npx @santifer/career-ops init` وينزّل Chromium. ما يناسب يكون داخل هذا المستودع.
- أوامر إعادة التثبيت:
  ```
  npx -y skills add backnotprop/pstack --all -a claude-code -y
  npx -y skills add JuliusBrussee/caveman -a claude-code -y
  npx -y skills add vercel-labs/skills --skill find-skills -a claude-code -y
  npx -y skills add ryunana/xbloom-studio-recipe-skill -a claude-code -y
  npx -y skills add blader/humanizer -a claude-code -y
  npx -y skills add multica-ai/andrej-karpathy-skills -a claude-code -y
  npx -y skills add obra/superpowers -a claude-code -y
  npx -y skills add nextlevelbuilder/ui-ux-pro-max-skill -a claude-code -y
  npx -y skills add pbakaus/impeccable -a claude-code -y
  npx -y skills add heygen-com/hyperframes --skill hyperframes --skill hyperframes-cli --skill hyperframes-registry --skill media-use --skill reverse-any-video --skill style-sampling -a claude-code -y
  uv tool install graphifyy && graphify install --project
  npx -y get-shit-done-cc@latest --claude --local --minimal
  ```
- أمر `graphify install --project` يعيد كتابة قسم graphify في `CLAUDE.md`. بعد تشغيله تأكد إن سطر `@claude-preferences.md` باقي في أول الملف.
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
- خريطة graphify للمشروع ما انبنت بعد. تنبني بـ `/graphify .` لما يحتاجها المستخدم.

## ملاحظة
- `CLAUDE.md` في جذر المستودع يستورد هذا الملف بسطر `@claude-preferences.md`، فـ Claude يقرأه تلقائيًا في كل جلسة.
- `CLAUDE.md` مُتجاهَل في `.gitignore` من المشروع الأصلي، فأُضيف للمستودع بـ `git add -f`. أي تعديل عليه بعدها ينرفع عادي.
