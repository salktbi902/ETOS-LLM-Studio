# تفضيلات Claude لهذا المشروع

## اللغة والأسلوب
- الرد دائمًا بالعربية، في كل شيء.
- أسلوب caveman المختصر (مهارة `caveman`): الجواب أولًا، بدون مجاملات.
- الكود والأوامر والمسارات والأخطاء تبقى حرفية كما هي.

## المهارات
- المهارات محلية في `.claude/skills/` وغير مرفوعة (`.claude/` مُتجاهَل في `.gitignore` بطلب المستخدم).
- لإعادة تثبيتها:
  ```
  npx -y skills add vercel-labs/skills --skill find-skills -a claude-code -y
  npx -y skills add JuliusBrussee/caveman -a claude-code -y
  ```
- لا تُثبَّت مهارة جديدة بدون موافقة المستخدم.
- مهارات Caveman Cloud (`caveman-setup` و`caveman-discover` و`caveman-manage`) تمرّر الطلبات عبر بوابة خارجية، ولا تُشغَّل إلا بطلب صريح.
- اختيار المهارة حسب المهمة: `surgical-patch` للإصلاح، `safe-refactor` لإعادة الهيكلة، `verify-and-stop` للتحقق، `caveman-commit` للـ commits، `caveman-review` للمراجعة.
