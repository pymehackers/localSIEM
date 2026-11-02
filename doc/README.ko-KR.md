# localSIEM

이 README는 다음 언어로도 제공됩니다:\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), ko-KR, [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## 소개

보호 대상과 같은 PC/서버에서 실행되는 가볍고 모듈화된 SIEM입니다. Alpine과 Debian을 지원합니다(현재 기준).

## 모듈

서버의 각 서비스는 모듈이 감시합니다. 모듈은 그 서비스의 로그 위치, 읽는 방법, 적용되는 규칙을 localSIEM에 알려 줍니다. 모듈은 웹에서 설치, 업데이트, 제거하며, 웹이 [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) 저장소에서 내려받습니다. 현재 모듈은 두 가지입니다.

- **apache2**(Apache + ModSecurity): 각 요청의 액세스 로그, 오류 로그, ModSecurity 감사 로그를 하나로 묶습니다.
- **privesc**(권한 상승): 서버에서 실행되는 것을 감시하고 root로의 권한 상승 단계를 경고합니다.

모듈은 서버에 아무것도 설치하지 않습니다. 필요한 것이 없으면 무엇을 설치해야 하는지 알려 주고, 그것이 갖춰질 때까지 비활성 상태로 남습니다.

## 스크린샷

![localSIEM 개요](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## 설치

`root`로 실행하십시오.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: 웹(`https://<server>:10443`)을 열 수 있는 IP입니다.

## 문서 읽기

다음 문서를 참고하십시오.

- [doc/MANUAL.ko-KR.md](MANUAL.ko-KR.md): 설치, 설정, 사용 방법을 설명합니다.
- [doc/CODE.ko-KR.md](CODE.ko-KR.md): 내부 구조를 설명합니다(개발자 및 AI 모델용).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules): 모듈과 모듈 문서입니다.
