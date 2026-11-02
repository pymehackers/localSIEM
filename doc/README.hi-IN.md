# localSIEM

यह README इन भाषाओं में भी उपलब्ध है:\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), hi-IN, [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## यह क्या है

एक हल्का और मॉड्यूलर SIEM, जो उसी PC/सर्वर पर चलता है जिसकी वह सुरक्षा करता है। Alpine और Debian (फ़िलहाल)।

## मॉड्यूल

सर्वर की हर सेवा पर एक मॉड्यूल नज़र रखता है, जो localSIEM को सिखाता है कि उस सेवा के लॉग कहाँ हैं, उन्हें कैसे पढ़ना है और कौन से नियम लागू होते हैं। मॉड्यूल वेब से इंस्टॉल, अपडेट और अनइंस्टॉल किए जाते हैं, जो उन्हें [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) रिपॉज़िटरी से डाउनलोड करता है। अभी दो मॉड्यूल हैं:

- **apache2** (Apache + ModSecurity): हर अनुरोध के access लॉग, error लॉग और ModSecurity के ऑडिट लॉग को जोड़ता है।
- **privesc** (प्रिविलेज एस्केलेशन): सर्वर पर जो चलाया जाता है उस पर नज़र रखता है और root तक पहुँचने के चरणों की चेतावनी देता है।

कोई मॉड्यूल सर्वर पर कभी कुछ इंस्टॉल नहीं करता: अगर उसे ज़रूरत की कोई चीज़ नहीं मिलती, तो वह आपको बताता है कि क्या इंस्टॉल करना है और तब तक बंद रहता है जब तक वह मौजूद न हो।

## स्क्रीनशॉट

![localSIEM का अवलोकन](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## इंस्टॉलेशन

इसे `root` के रूप में चलाएँ।

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: वे IP जिन्हें वेब (`https://<server>:10443`) खोलने की अनुमति है।

## दस्तावेज़ पढ़ें

आगे देखें:

- [doc/MANUAL.hi-IN.md](MANUAL.hi-IN.md), इसे इंस्टॉल करना, सेट करना और इस्तेमाल करना सीखने के लिए।
- [doc/CODE.hi-IN.md](CODE.hi-IN.md), यह समझने के लिए कि यह कैसे बना है (डेवलपरों और AI मॉडलों के लिए)।
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules), मॉड्यूल और उनके दस्तावेज़ों के लिए।
