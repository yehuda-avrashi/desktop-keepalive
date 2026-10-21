<div dir="rtl">

# desktop-keepalive

פלאגין לקלוד קוד שמשאיר את קלוד דסקטופ פתוח בווינדוס, ומחזיר את הסשנים לנייד אחרי כל הפעלה מחדש.

## הבעיה

קלוד דסקטופ נסגר מדי פעם, וכמעט אף פעם לא בגלל קריסה. יש ארבע סיבות:
1. עדכון שקט של האפליקציה.
2. הפעלה מחדש של ווינדוס בלילה.
3. עומס של יותר מדי סשנים פתוחים.
4. סגירה ידנית.

בכל פעם כזו כל הסשנים מתנתקים מהנייד, והם לא חוזרים לבד. סשן מתחבר שוב רק כשהוא מריץ תור.

## מה הפלאגין עושה

| חלק | מה הוא עושה |
|---|---|
| **שומר ווינדוס** | בודק כל 5 דקות, וגם דקה אחרי הכניסה למחשב. אם קלוד סגור, הוא מחכה 90 שניות ופותח אותו. אם אחרי סגירה נשאר תהליך ישן תקוע, הוא עוצר אותו ופותח את קלוד מחדש. |
| **משימת השכמה** | משימה מתוזמנת של קלוד שרצה כל 15 דקות. אחרי הפעלה מחדש היא שולחת הודעה קצרה לסשנים האחרונים, והם חוזרים לנייד. |
| **הוק** | עונה על משימת ההשכמה בעצמו, בלי המודל. בלעדיו כל בדיקה עולה בערך 250 אלף טוקנים, 96 פעמים ביום. הוא גם מעביר לארכיון את הריצות הישנות של המשימה. אם ההוק נכשל, המודל עושה את העבודה לפי ההוראות שבמשימה. |
| **סקיל `keepalive-setup`** | מתקין, בודק ומסיר את המערכת. |
| **סקיל `keepalive-guide`** | איך זה עובד, אבחון של "קלוד נסגר", עבודה עם סשנים מהנייד והמוקשים הידועים. |

המערכת עובדת רק בווינדוס, עם קלוד דסקטופ.

## התקנה

1. בטרמינל של קלוד קוד:
   ```
   /plugin install desktop-keepalive --marketplace yehuda-avrashi/desktop-keepalive
   ```
   לענות `y` להוספת המרקטפלייס, ולבחור את ההיקף user.
   אפשר גם מכל חלון PowerShell:
   ```
   claude plugin marketplace add yehuda-avrashi/desktop-keepalive
   claude plugin install desktop-keepalive@desktop-keepalive --scope user
   ```2. לפתוח סשן חדש ולכתוב: "תתקין את keepalive". הסקיל `keepalive-setup` יעשה את השאר:
   - יתקין את השומר.
   - ייצור את משימת ההשכמה.
   - יגדיר את האפליקציה.
   - יסביר איך עוצרים את ההפעלה מחדש של ווינדוס בלילה.

## הגדרות (`/config` ← desktop-keepalive)

| הגדרה | ברירת מחדל | משמעות |
|---|---|---|
| `wakeCount` | 3 | כמה מהסשנים האחרונים להעיר |
| `alwaysWakeSessionIds` | ריק | מזהי סשנים שמתעוררים תמיד, מופרדים בפסיק. למשל סשן קבוע שמעיר סשנים אחרים לבקשתך מהנייד. |
| `wakeMessage` | הודעה בעברית | ההודעה שנשלחת לכל סשן |
| `taskId` | `wake-sessions-after-restart` | המזהה של משימת ההשכמה |
| `archiveOldRuns` | true | להעביר לארכיון ריצות שהסתיימו (לא מוחק) |

## השהיה

כשצריך לסגור את קלוד לגמרי, למשל כדי לערוך את `claude_desktop_config.json`, יוצרים את הקובץ:
`%USERPROFILE%\.claude\state\desktop-keepalive\watchdog-pause`
ומוחקים אותו בסוף. אם שוכחים, ההשהיה פגה לבד אחרי 3 שעות.

## יומנים

| יומן | נתיב | מתי נכתבת בו שורה |
|---|---|---|
| השומר | `%USERPROFILE%\.claude\keepalive\claude-watchdog.log` | רק כשהשומר פעל |
| ההשכמה | `%USERPROFILE%\.claude\state\desktop-keepalive\wake.log` | רק בהפעלה מחדש אמיתית, או כשההוק העביר את העבודה למודל |

</div>

---

# desktop-keepalive (English)

A Claude Code plugin that keeps Claude Desktop running on Windows and brings your sessions back to the phone after every restart.

**Why:** Claude Desktop restarts more often than it seems (silent self-updates, Windows update reboots, load, manual quits). Each restart disconnects every session from Remote Control, and a session reconnects only when it runs a turn.

**What's inside**
- **Watchdog** (Windows Task Scheduler, every 5 min + at logon): relaunches Claude after a 90 s grace period; detects and stops a stuck leftover process after Quit (which otherwise makes Claude start signed out).
- **Wake task** (Claude scheduled task, every 15 min): after a restart, messages your most recent sessions so they reconnect to the phone. Skips child sessions, task runs and sessions already connected.
- **Hook**: answers the wake task without the model (0 tokens instead of ~250K per check) and archives finished task runs. Falls back to the model on any failure.
- **Skills**: `keepalive-setup` (install / check / remove) and `keepalive-guide` (how it works, diagnosing closures, phone workflows, known traps).

**Install**
```
/plugin install desktop-keepalive --marketplace yehuda-avrashi/desktop-keepalive
```
Then, in a new session: "set up keepalive". Options live under `/config` → desktop-keepalive (see the table above). Windows only.
