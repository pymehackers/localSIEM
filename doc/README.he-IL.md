# localSIEM

קובץ README זה זמין גם בשפות:\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), he-IL, [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## מה זה

מערכת SIEM קלה ומודולרית שפועלת על אותו מחשב/שרת שעליו היא מגנה. Alpine ו-Debian (בינתיים).

## מודולים

כל שירות של השרת נמצא במעקב של מודול, שמלמד את localSIEM היכן נמצאים הלוגים של השירות הזה, איך לקרוא אותם ואילו כללים חלים. מתקינים, מעדכנים ומסירים מודולים מממשק האינטרנט, שמוריד אותם מהמאגר [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules). כיום יש שניים:

- **apache2** (Apache + ModSecurity): מאחד את לוג הגישה, לוג השגיאות ולוג הביקורת של ModSecurity של כל בקשה.
- **privesc** (הסלמת הרשאות): עוקב אחר מה שמורץ בשרת ומתריע על השלבים של הסלמה ל-root.

מודול לעולם אינו מתקין דבר בשרת: אם חסר לו משהו שהוא צריך, הוא אומר לכם מה להתקין ונשאר מושבת עד שזה קיים.

## צילומי מסך

![סקירה כללית של localSIEM](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## התקנה

יש להריץ בתור `root`.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

האפשרות `--allow-from`: כתובות ה-IP המורשות לפתוח את ממשק האינטרנט (`https://<server>:10443`).

## קריאת התיעוד

להמשך קריאה:

- כדי ללמוד איך להתקין, להגדיר ולהשתמש ב-localSIEM: [doc/MANUAL.he-IL.md](MANUAL.he-IL.md).
- כדי להבין איך הוא בנוי (למפתחים ולמודלים של בינה מלאכותית): [doc/CODE.he-IL.md](CODE.he-IL.md).
- למודולים ולתיעוד שלהם: [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules).
