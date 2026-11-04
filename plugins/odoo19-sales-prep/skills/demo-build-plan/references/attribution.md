<!-- ЗГЕНЕРОВАНО з shared/attribution.md скриптом scripts/sync-shared.sh.
     Не правити тут — правки затираються. Канонічне джерело: shared/attribution.md -->

# Звідки взяті ідеї

> Канонічне джерело: `shared/attribution.md`. У плагіни потрапляє копією через
> `scripts/sync-shared.sh`. **Правити тільки тут.**

Реєстр запозичень фази продажів: що в нас зʼявилось, звідки, під якою ліцензією
і як саме взято. **Чужого тексту дослівно в скілах немає** — усе переказано своїми
словами українською і переписано під Odoo 19 та нашу воронку. Чужий код не
копіювався і не запускався.

**Як взято:** «переказ» — своїми словами з атрибуцією; «ідея» — тільки принцип,
текст і критерії свої.

| Що в нас | Де | Джерело (репозиторій @ коміт, файл) | Ліцензія | Як |
|---|---|---|---|---|
| Виміри закупки В1–В7, банк питань покупця, «що клієнт знайде сам», «що слухає клієнт», перевірка покриття | `buyer_diligence.md`; `presale-pack-builder`, `offer-finalizer` (Pre-save); `defence-brief`; `demo-runbook` | salespeak-ai/buyer-eval-skill @ `ebb0e06`: `references/scoring.md`, `references/deep-eval.md` (D4, D6), `references/report-format.md` §7, `references/evidence-model.md` §6 | MIT | переказ |
| Сходи доказів «як це побачить клієнт»; правило «результат тримається на документі або референсі» | `buyer_diligence.md` §2; `defence-brief` | buyer-eval-skill @ `ebb0e06`, `references/evidence-model.md` §2, §3a, §4 | MIT | переказ |
| Усна ціна й «без доплат» — тільки текстом у КП | `offer-finalizer` | buyer-eval-skill @ `ebb0e06`, `references/scoring.md` правило 3 | MIT | ідея |
| Пріоритет питання і «хто відповідає» | `data-completeness-scorer` | buyer-eval-skill @ `ebb0e06`, `references/report-format.md` §5–6 | MIT | переказ |
| Хто написав рядок чатера; контрольна вибірка виграшів; рядок «Виключення» в патерні | `loss-pattern-analyzer` | LMTYdotcom/skills @ `18667e0`, `skills/competitive-win-loss-analysis/SKILL.md` і `references/METHODOLOGY.md` | MIT, © LMTY | ідея / переказ |
| Статус-кво як обовʼязкове заперечення; «не на часі» ≠ «дорого» | `defence-brief`, `loss-pattern-analyzer` | J. Care, *Mastering Technical Sales*, 4th ed., гл. 25; конспект tokenaissance/mastering-technical-sales @ `8717c96`, `references/part5-career-growth.md` | книга — тільки ідея; конспект MIT | ідея |
| Проблема ≠ симптом ≠ хотілка; вердикт «демо / умовно / пауза» з критеріями, що не усереднюються; стрес-тест економіки | `demo-build-plan`, `offer-finalizer` | hangljoe/AI-PreSales-Skills @ `ab0752b`: `skills/critical-business-issue-finder`, `skills/tfq` (+ `references/scoring-model.md`), `skills/business-case-stress-tester` | MIT (скіли); тексти книги автора — **не використані** | ідея; критерії й пороги свої |
| Закрите питання клієнту з рекомендованим варіантом, «Інше», «Ще не вирішили» | `data-completeness-scorer` | SB-Celebal/claude-sow-creation @ `a2c4f18`, `sow-intake/SKILL.md` | **ліцензії немає** | тільки ідея, текст свій |
| «Смак показують»: 3–5 варіантів зі ставкою, критерій із реакції | `demo-debrief` | Neeeophytee/finding-unknowns-skills @ `ca5696a`, `skills/brainstorm-prototypes/SKILL.md` | MIT, © 2026 Neeeophytee | ідея |
| Нестисні блоки Odoo; позначка аналога «до / з AI-збіркою» | `preliminary-estimate` | antondrob/ai-first-estimation @ `6a492dc`, `SKILL.md` | MIT | ідея; перелік блоків свій |
| Риск-буфер із причиною; крос-перевірка двома методами; `stale_after` значень | `preliminary-estimate`, `deal_journal_template.md` (інваріант 9) | Leanware-io/software-estimation-skills @ `e5a989a`: `plugins/software-cost-estimate/.../SKILL.md` (кроки 5, 9), `plugins/ai-savings-pass/.../data/savings-2026-10.json` | MIT | переказ / ідея |

Розбори джерел і рішення «що брати» — у хабі `tnizhnikovskyi-todo/claude_-skills`,
гілка `claude/admiring-cannon-25jueb`, `catalog/<джерело>/README.md`, розділ «Что взять».
