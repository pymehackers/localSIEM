# localSIEM 사용자 매뉴얼

이 MANUAL은 다음 언어로도 제공됩니다:\
[de-DE](MANUAL.de-DE.md), [en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md), [fr-FR](MANUAL.fr-FR.md), [he-IL](MANUAL.he-IL.md), [hi-IN](MANUAL.hi-IN.md), [it-IT](MANUAL.it-IT.md), [ja-JP](MANUAL.ja-JP.md), ko-KR, [pt-BR](MANUAL.pt-BR.md), [pt-PT](MANUAL.pt-PT.md), [ru-RU](MANUAL.ru-RU.md), [zh-CN](MANUAL.zh-CN.md)

[설치](README.ko-KR.md) · [코드 참조](CODE.ko-KR.md)

## 목차

1. [localSIEM이 하는 일](#what)
2. [설치](#installation)
3. [Apache 및 ModSecurity 요구 사항](#requirements)
4. [진단](#doctor)
5. [SOC 연결](#soc)
6. [로그인과 계정](#signin)
7. [두 가지 대시보드](#dashboards)
8. [개요](#overview)
9. [검색](#search)
10. [요청 카드와 피벗](#card)
11. [실시간 보기](#live)
12. [알림](#alerts)
13. [모듈](#modules)
14. [관리](#administration)
15. [상태 경고와 대처 방법](#health)
16. [보존과 디스크](#retention)
17. [명령줄](#cli)

<a id="what"></a>
## 1. localSIEM이 하는 일

localSIEM은 설치된 서버의 서비스를 서비스마다 하나씩 있는 **모듈**로 감시합니다. 그 서버의 로그만 읽으며, 다른 컴퓨터에서 로그를 받지 않습니다. **Apache + ModSecurity** 모듈은 Apache 웹을 감시합니다. 요청마다 세 가지 레코드, 즉 `access.log`의 줄, `error.log`의 줄들, ModSecurity 감사 로그의 레코드를 그 요청의 `UNIQUE_ID`로 결합합니다. 모든 것은 검색할 수 있도록 저장됩니다. 그런 다음 localSIEM이 SOC로 보내야 할 것을 결정합니다.

localSIEM은 보호 대상인 Debian 또는 Alpine 서버에서 그 서버의 웹과 나란히, 시스템 사용자 `localsiem`의 서비스 두 개로 실행됩니다. localSIEM 자체의 웹은 포트 10443에서 수신하며, 포트 80이나 443은 절대 사용하지 않고 서버의 웹도 건드리지 않습니다. SOC(선택 사항, 5절) 외에도 가장 중요한 알림을 **Telegram**으로 보낼 수 있고(14절), SOC 분석가에게 검색 필드 하나와 시간 범위로 이루어진 **검색 도구**를 제공합니다(9절). 비밀번호, 쿠키, 토큰, 요청 본문은 절대 서버 밖으로 내보내지 않으며, 메모리를 적게 사용하고(평상시 약 100 MB, 최대 약 200 MB) 디스크를 가득 채우지 않습니다(16절).

**SOC로는 아직 아무도 해결하지 않은 것만 보냅니다.**

| 상황 | SOC로 보내나요? |
|---|---|
| ModSecurity가 1–2단계에서(애플리케이션이 요청을 받기 전에) 요청을 차단함 | **아니요.** localSIEM에 남아 검색할 수 있으며, 그 IP의 다음 알림에 횟수로 표시됩니다. |
| ModSecurity가 3–4단계에서(애플리케이션이 이미 요청을 실행한 후) 응답을 차단함 | 예 |
| ModSecurity가 `DetectionOnly`일 때의 규칙 일치(아무것도 차단되지 않음) | 예 |
| 차단 임계값 미만의 규칙 일치 | 예, 심각도 `low`로 |
| localSIEM 규칙의 신호(무차별 대입, 웹 셸, 민감한 파일, 열거, 데이터베이스 오류) | 예 |
| 상태 문제와 흔적 삭제 가능성 | 예 |

**SOC로 보내는 것의 심각도**

| 상황 | 심각도 |
|---|---|
| 차단되지 않은 규칙 일치, 3xx·4xx·5xx 응답 | 중간 |
| 차단되지 않은 규칙 일치, 2xx 응답 | 높음 |
| 3–4단계에서 차단됨 | 높음 |
| 성공 징후: 차단되지 않은 데이터 유출 또는 웹 셸 규칙(950–955), 직후의 SQL 오류, 새 `.php`에 대한 2xx POST | 심각 |
| 차단 임계값 미만(대개 애플리케이션의 오탐) | 낮음(설정에서 구성 가능) |

**그룹화.** 10분 기간 동안 모듈, vhost, IP, 범주, 심각도별로 알림 하나가 생성됩니다. 심각 알림은 즉시 전송되고, 나머지는 60초 동안 기다려 한꺼번에 발생한 이벤트를 모은 뒤 횟수와 함께 전송됩니다. 요청을 수천 개 보내는 스캐너도 알림 수천 개가 아니라 몇 개만 만듭니다. 심각도가 올라가면(예: 같은 공격이 이제 200 응답을 받으면) 그것은 별도의 알림입니다.

**SOC로 절대 보내지 않는 것:** 요청 또는 응답 본문, 쿠키, `Authorization` 헤더, 비밀번호, 토큰(마스킹한 형태로도 보내지 않음), 그리고 1–2단계에서 이미 차단된 것(횟수로만 보냄). localSIEM은 무엇이든 저장하기 전에 민감한 값(`password`, `pass`, `pwd`, `passwd`, `token`, `secret`, `api_key`, `apikey`, `auth`, `session` 및 `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `Proxy-Authorization` 헤더)을 `***`로 마스킹합니다.

**모듈.** localSIEM의 코어(저장, 검색, 규칙, 그룹화, SOC 전송, 상태 점검)는 모든 서비스에 공통이며, 각 모듈은 한 서비스에 고유한 것을 추가합니다. Apache + ModSecurity 모듈(`apache2`)은 `localSIEM-modules` 저장소(GitHub)에서 제공되며, localSIEM 설치 프로그램이 아니라 웹에서만 설치, 업데이트, 제거합니다. 이 모듈을 설치해도 Apache나 ModSecurity는 설치되지 않습니다. 모든 모듈은 같은 방식으로 웹에서 설치, 업데이트, 제거합니다. 13절에서 모듈을 설치하고 업데이트하는 방법, 상태를 확인하는 방법, 켜고 끄는 방법, 구성하는 방법을 설명합니다.

<a id="installation"></a>
## 2. 설치

설치는 두 단계로 이루어집니다. localSIEM 코어를 설치한 다음 모듈을 설치합니다(아래 2단계). root로, GitHub에서 바로 실행하십시오:

```bash
# Debian 13
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
# Alpine 3.24 (먼저: apk add bash curl)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
```

localSIEM 웹은 항상 **HTTPS 포트 10443**에서 수신합니다. 설치 프로그램은 이 포트가 비어 있는지 확인하고, 다른 서비스가 사용 중이면 중지합니다. 동작과 옵션은 `bash -s --` 뒤에 붙입니다. 설치 프로그램은 필요한 것(`venv`가 포함된 Python 3.13, OpenSSL, CA 인증서, ACL 도구, logrotate, curl, tar)을 확인하고 없는 것을 설치합니다. 이렇게 파이프로 실행하면 `https://github.com/PYMEHackers/localSIEM`의 `main` 브랜치를 내려받고, 프로젝트 사본에서 실행하면(`bash deploy/install-update-reinstall-debian.sh --install`) 그 사본을 설치합니다.

**동작.** 설치 프로그램에는 항상 동작 하나가 필요하며, 동작을 지정하지 않으면 중지하고 동작 목록을 보여 줍니다:

| 동작 | 용도 |
|---|---|
| `--install` | localSIEM이 없는 서버에 localSIEM을 설치합니다. localSIEM의 흔적(`/opt/localsiem`, localSIEM의 서비스 또는 `localsiem` 사용자, 도중에 실패한 설치의 흔적 포함)을 하나라도 발견하면 중지하고 `--update`와 `--reinstall`을 안내합니다. |
| `--update` | 설치된 localSIEM을 업데이트합니다. 데이터, 계정, 설정, 모듈, 이전에 지정한 옵션(아래 참조)을 유지합니다. |
| `--reinstall [--yes]` | 설치된 localSIEM을 `--uninstall`처럼(아래 참조) 모든 데이터와 함께 삭제하고, 새 비밀번호로 처음부터 다시 설치합니다. 먼저 `yes`를 입력하라고 요청하며(`--yes`를 지정하면 묻지 않으며, 터미널이 없을 때는 이 옵션이 필요합니다), 새 사본을 내려받고 옵션을 확인하기 전에는 아무것도 삭제하지 않습니다. 이전 설치의 옵션은 유지되지 않으므로 다시 지정하십시오. |
| `--uninstall [--yes]` | 서버에서 localSIEM과 모든 데이터를 삭제합니다(아래 참조). 다른 옵션 없이 단독으로 사용합니다. |

`--update`와 `--reinstall`은 localSIEM이 설치되어 있지 않으면 중지합니다. 이때는 `--install`을 사용하십시오.

`--install`, `--update`, `--reinstall`의 옵션:

| 옵션 | 용도 |
|---|---|
| `--allow-from LIST` | 웹을 열 수 있는 IP와 CIDR(쉼표로 구분): SOC와 관리자 |
| `--soc-url URL` | 기본값 `https://soc.pymehackers.com` |
| `--soc-token TOKEN` | SOC에서 발급한 이 클라이언트의 수집 토큰. 선택 사항: SOC가 없어도 localSIEM은 단독으로 작동합니다(5절) |
| `--soc-ca-file PATH` | 사설 인증서를 사용하는 SOC(테스트 서버)에만 필요 |
| `--domain NAME` | 인증서와 SIEM 주소에 사용할 서버 이름(기본값: 호스트 이름) |
| `--certificate PATH --private-key PATH` | 사용할 인증서. 지정하지 않으면 localSIEM은 `--domain`의 Let's Encrypt 인증서가 있으면 그것을 복사하고(갱신될 때마다 다시 복사), 없으면 자체 서명 인증서를 만듭니다. |
| `--retention-days N`, `--max-disk SIZE` | 보존(16절) |
| `--enable-mfa`, `--disable-mfa` | 2단계 인증 켜기(모든 계정에 필수) 또는 끄기. 지정하지 않으면 새 설치에서는 꺼져 있고, 업데이트에서는 관리 › 설정에서 선택한 값을 유지합니다(14절). |
| `--rotate-credentials` | 새 JWT 서명 비밀 값을 만들어 `/root/webapp-credentials.txt`에 기록합니다 |
| `--ref REF` | 내려받을 localSIEM의 브랜치 또는 태그(기본값 `main`) |
| `--source-url URL` | GitHub의 아카이브 대신 설치할 localSIEM 아카이브(`.tar.gz`)(미러) |
| `--modules-repository URL`, `--modules-ref REF` | 웹이 모듈을 설치하고 업데이트할 때 사용하는 저장소(또는 `.tar.gz` 아카이브)와 브랜치 또는 태그(13절). 기본값: `https://github.com/PYMEHackers/localSIEM-modules`, `main` 브랜치. |

**항상 최신 버전.** GitHub는 `raw.githubusercontent.com`의 파일을 변경할 때마다 최대 5분 동안 캐시에 보관합니다. 그래서 위 명령은 캐시가 없는 GitHub API를 통해 설치 프로그램을 읽습니다. 그런 다음 설치 프로그램은 그 API에 브랜치가 가리키는 커밋을 물어 정확히 그 커밋을 내려받으며, 경로상의 모든 서버에 캐시된 사본으로 응답하지 말라고 요청합니다. 토큰이 없으면 GitHub는 IP 주소마다 시간당 60개의 API 요청을 허용합니다. 거부되면 명령은 `403`으로 실패하며(잠시 기다렸다가 다시 실행하십시오), 설치 프로그램의 질의만 실패하면 설치 프로그램은 경고를 표시하고 브랜치를 내려받습니다.

옵션은 `/opt/localsiem/config/install.env`에 기억됩니다. 옵션 없이 `--update`를 실행하면 기억된 옵션이 유지됩니다. 업데이트하려면:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --update
```

설치 프로그램 로그는 `/root/webapp-install.log`이고, 설치 프로그램이 만든 비밀번호는 `/root/webapp-credentials.txt`에 있습니다(둘 다 모드 600). 진행 상황은 번호가 붙은 단계(`[3/12] Getting localSIEM`)로 표시되며, 완료된 것은 `✓`, 경고는 `!`, 실패는 `✗`, 정보는 `·`로 나타내고, 터미널에서는 색으로 표시합니다(`NO_COLOR=1` 또는 `LOCALSIEM_COLOR=never`로 색을 끕니다). apt-get 또는 apk, curl, tar, pip의 출력은 로그에만 기록되며, 그중 하나가 실패하면 화면에 마지막 20줄이 표시됩니다. 로그에는 같은 줄이 색 없이, 시각은 저장 형식으로 기록됩니다. 마지막에는 활성화된 모든 모듈의 진단을 실행하고(4절) 요약을 보여 줍니다. 요약에는 웹 주소(SOC에 알려 줄 SIEM 주소이기도 함), 자격 증명 파일, 로그, SOC 상태가 나오고 그 뒤에 다음 단계가 이어집니다. 실패하면 어느 단계에서 멈췄는지 알려 줍니다.

**제거.** `--uninstall`은 서버에서 localSIEM을 삭제합니다. 서비스를 중지하고 제거하며, `/opt/localsiem`(코드, 설정, 모든 이벤트와 알림이 담긴 데이터베이스, 인증서, 모듈), `localsiem` 사용자, `setup-modules`가 부여한 로그 읽기 권한, 이전 버전의 Apache 모듈(1.2.0 이하)의 `--configure-apache` 옵션이 추가한 Apache 구성(`localsiem.conf`)(Apache의 configtest와 reload 포함), logrotate 파일, Let's Encrypt 훅, `/root/webapp-credentials.txt`의 localSIEM 항목(파일에 다른 내용이 남지 않으면 파일도 삭제)을 삭제합니다. 먼저 `yes`를 입력하라고 요청합니다(`--yes`를 지정하면 묻지 않으며, 터미널이 없을 때는 이 옵션이 필요합니다). 서버에 localSIEM의 흔적이 남아 있지 않으면 «Nothing of localSIEM was found on this server.»라고 표시합니다. 설치 프로그램 로그, 설치 프로그램이 추가한 패키지, `mod_unique_id`(Debian), Apache 로그는 남으며, 그 구성 파일 때문에 Apache가 기록한 `localsiem_access.log`와 `modsec_audit.log`도 남습니다. localSIEM은 Apache 로그를 절대 변경하거나 삭제하지 않습니다. 제거하려면:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

**재설치.** 한 번에 처음부터 다시 시작하려면 `--reinstall`을 사용하십시오. 같은 방식으로 모든 것을 삭제하고 localSIEM을 다시 설치합니다(옵션을 다시 지정하십시오):

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --reinstall --allow-from 203.0.113.10 --soc-token TOKEN
```

**2. 모듈.** localSIEM 설치 프로그램은 **모듈을 하나도** 설치하지 않습니다. localSIEM을 모듈을 받을 준비가 된 상태로 두며, 업데이트할 때는 이미 설치된 모듈(과 그 로그의 읽기 권한)을 유지합니다. 모듈은 **웹에서만** 설치합니다. 모듈 › 설치 가능(13절)에는 `localSIEM-modules` 저장소의 모듈 중 아직 설치되지 않은 모듈이 나열되며, 그 저장소에는 자체 설치 프로그램이 없습니다. localSIEM은 그 저장소에서 모듈을 내려받아 모듈 폴더(저장소의 `mod-<name>/`)를 `/opt/localsiem/modules/<name>/`에 복사하고(`tests/` 폴더는 복사하지 않으며, 다시 설치한 모듈은 이전 설정을 되찾습니다) 수집기를 다시 시작합니다. 모듈 업데이트와 제거도 웹에서 합니다. 저장소에 더 새로운 버전이 있을 때의 **업데이트**와 **제거**이며, 둘 다 모듈 › 설치됨에 있습니다(13절).

모듈의 로그를 읽으려면 root 권한이 필요하므로, 모듈을 설치하면 웹이 대화 상자에 서버에서 root로 실행할 명령을 보여 줍니다:

```bash
/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py setup-modules
```

이 명령은 설치된 각 모듈이 선언한 로그 폴더(Apache 모듈은 `/var/log/apache2`, 3.7절)에 대한 읽기 권한을 다음 로테이션 파일까지 포함하여 `localsiem` 사용자에게 부여하고, localSIEM을 다시 시작한 다음 `localsiem`으로 진단을 실행합니다. 언제든 다시 실행할 수 있습니다. localSIEM이 부여하는 이 읽기 권한이 root가 모듈을 위해 하는 일의 전부입니다.

**모듈을 설치해도 모듈이 감시하는 소프트웨어는 설치되지 않으며**, 그 밖의 어떤 것도 설치되지 않습니다. 모듈은 서버에 이미 있는 것으로 작동하며 `/opt/localsiem/` 밖의 어떤 것도 변경하지 않습니다. 새 모듈은 작성자가 정한 대로 켜진 상태 또는 꺼진 상태로 시작합니다. 단, 서버에 모듈에 필요한 것(Apache 모듈의 경우 Apache와 ModSecurity 2)이 없으면 **꺼진 상태로** 설치되고, 웹에 무엇이 없는지 표시되며, **재구성**이 그것을 찾을 때까지 스위치가 잠긴 상태로 유지됩니다(13절). 모듈의 상태는 **모듈 › 설치됨**에서 확인합니다(13절).

<a id="requirements"></a>
## 3. Apache 및 ModSecurity 요구 사항

Apache + ModSecurity 모듈의 요구 사항은 다음과 같습니다. Apache와 ModSecurity 2 자체를 먼저 설치해야 하며, 이것들이 없으면 모듈을 켤 수 없습니다(13절). localSIEM은 Apache 구성을 스스로 변경하지 않으며, Apache 로그나 그 형식, 기록 방식도 변경하지 않습니다. 모듈은 서버가 이미 기록하는 로그를 읽고 그에 맞춥니다. 모듈의 진단(4절)은 각 요구 사항을 확인합니다. CRS가 포함된 ModSecurity와 `SecRuleEngine`(1번), `mod_unique_id`(2번), 읽기 권한(7번)에 대해서는 충족되지 않은 항목마다 정확한 설정 조각이나 명령을 보여 주어 직접 적용할 수 있게 하며, 로그(3~6번)는 변경을 제안하지 않고 설명만 합니다.

1. **OWASP CRS가 포함된 ModSecurity 2**, `SecRuleEngine On` 또는 `DetectionOnly`로 설정. 둘 다 작동합니다. `DetectionOnly`에서는 아무것도 차단되지 않으므로 모든 일치 항목이 SOC로 갑니다.
2. **`mod_unique_id`**: ModSecurity 2가 작동하려면 반드시 필요하며(없으면 아무것도 검사하지 않으며, Alpine은 기본적으로 이 모듈을 불러오지 않습니다), 각 요청의 세 레코드를 결합하는 데 쓰입니다.
3. **액세스 로그**: Apache가 기록하는 그대로. 어떤 형식이든 작동합니다(`combined`, `vhost_combined`, `common` 또는 구성에 있는 어떤 `LogFormat`이든). 각 줄은 클라이언트 IP, 메서드, URI, 상태 코드, 시각으로 해당 요청과 결합되며(«약한 상관관계»), vhost는 `%v`에서, 없으면 감사 레코드의 Host 헤더와 포트에서 가져옵니다. 형식에 밀리초, `%v`, `%{UNIQUE_ID}e`도 있으면(일부 서버가 이미 기록하는 `localsiem_combined` 줄처럼) 각 줄은 `UNIQUE_ID`로 해당 요청과 결합되며, `%D`가 있으면 localSIEM은 요청의 소요 시간도 얻습니다. 형식에 클라이언트 IP, 시각, 요청 줄 또는 상태 코드가 없는 액세스 로그도 그대로 읽지만, 그 줄들은 해당 요청과 결합할 수 없습니다. 그런 요청은 ModSecurity 감사 로그에서 볼 수 있습니다. 형식에 지시자가 전혀 없는 `CustomLog`는 모든 줄에 같은 텍스트를 기록하므로 읽지 않습니다.
4. **`mod_remoteip`**: 로그에 어떤 IP가 기록될지를 결정합니다. 웹이 프록시나 로드 밸런서 뒤에 있는데 Apache가 이 모듈을 사용하지 않으면 로그에는 프록시의 IP가 기록되며, 알림과 IP 기반 규칙도 마찬가지가 됩니다. 진단과 상태 경고 «Real client IP missing»(15절)이 이를 알려 줍니다.
5. **ModSecurity 감사 로그**: ModSecurity가 기록하는 그대로(직렬 또는 동시, JSON 또는 네이티브, 기록된 파트 그대로). 감사 로그가 없으면(`SecAuditEngine Off` 또는 `SecAuditLog` 없음) localSIEM은 `error.log`만으로 판단하며, 요청 카드에 헤더나 규칙 목록이 없습니다. 파트 `H`가 없으면 감사 로그에서 수행된 조치를 읽을 수 없습니다. 파트 `E`(응답 본문)는 기록되더라도 절대 SOC로 보내지 않으며, 파트 `K`(실행된 모든 규칙의 전체 텍스트)는 저장하지 않습니다. 동시 유형(트랜잭션마다 파일 하나)에서는 ModSecurity가 보통 모드 600으로 파일을 만들며, localSIEM은 `localsiem`이 읽을 수 있을 때만 이 파일을 읽습니다(7번).
6. **소스에서의 마스킹**: ModSecurity가 디스크의 감사 로그를 마스킹하지 않으면(`sanitise` 동작) 그 파일에 비밀번호와 쿠키가 담길 수 있습니다. localSIEM은 이를 저장하기 전에 마스킹하며, 절대 SOC로 보내지 않습니다.
7. **로그에 대한 `localsiem` 사용자의 읽기 권한**. 2절의 root용 명령(`manage.py setup-modules`)이 설치된 모듈이 선언한 폴더(Apache 모듈은 `/var/log/apache2`)에 대해 이 권한을 부여하며, localSIEM 설치 프로그램은 업데이트할 때마다 다시 부여합니다. Debian에서는 `localsiem`을 `adm` 그룹에 추가하고, Alpine에서와 마찬가지로 ACL을 통해 `localsiem`에게 해당 폴더의 읽기 권한을 부여합니다. 기본 ACL도 설정하므로 다음 로테이션 파일도 읽을 수 있습니다. 다른 폴더에 직접 추가한 로그(13절)에도 이 권한이 필요합니다. 예: `setfacl -m g:localsiem:rx /srv/logs`, `setfacl -d -m g:localsiem:r /srv/logs`, `setfacl -m g:localsiem:r /srv/logs/*.log`. localSIEM은 로그를 읽기만 합니다. 로그에 쓰거나, 로테이션하거나, 잘라내거나, 옮기거나, 삭제하지 않습니다. 로그를 따라가기 시작할 때(처음 시작할 때, 모듈을 설치하거나 켠 후, 또는 root가 읽기 권한을 부여한 후) 로그의 끝에서 시작합니다. 로그에 이미 있던 내용은 과거 기록이므로 절대 알림을 발생시키지 않습니다. 나중에 만들어진 vhost의 로그만 처음부터 읽습니다(5 MB 이하일 때).

<a id="doctor"></a>
## 4. 진단

모듈마다 자체 진단이 있습니다. Apache 모듈의 진단은 3절의 모든 요구 사항을 확인하고, 충족되지 않은 각 항목을 해결하는 설정 조각이나 명령을 보여 줍니다. 로그(형식, `mod_remoteip`, 감사 로그, 마스킹)는 변경을 제안하지 않고 설명만 하며, 찾은 소스(그리고 파이프 로그처럼 읽을 수 없는 소스)를 나열합니다. 진단은 localSIEM을 설치할 때마다, 그리고 2절의 root용 명령을 실행할 때마다 마지막에 실행되며, 각 모듈의 페이지(**모듈 › 설치됨 › 구성**, 13절, «다시 탐색하고 진단 실행» 버튼)에 표시되고, 활성화된 모든 모듈에 대해 언제든 실행할 수 있습니다:

```bash
runuser -u localsiem -- /opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor   # Debian
su -s /bin/sh localsiem -c "/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor"   # Alpine
```

`✓`는 정상, `!`는 제한적으로 작동, `✗`는 반드시 수정해야 함, `·`는 일부 상황에만 해당함을 뜻합니다(터미널에서는 색으로 표시되며, UTF-8을 쓸 수 없는 곳에서는 `+`, `!`, `x`, `-`). 불러올 수 없는 모듈은 맨 처음에 `✗ Module <name> not loaded: <reason>`으로 표시됩니다. 꺼진 모듈에는 진단이 없습니다. 요구 사항(13절)이 있는 모듈이면 진단이 대신 그 요구 사항을 보여 주므로 모듈을 켤 수 있는지 알 수 있습니다.

<a id="soc"></a>
## 5. SOC 연결

localSIEM을 SOC에 연결하는 것은 선택 사항입니다. SOC가 없으면(토큰이 없거나 **SOC로 알림 전송**이 꺼져 있으면) localSIEM은 단독으로 작동합니다. 모든 알림을 **알림** 탭에 «전송 안 됨»으로 보관하며, 나중에 SOC를 구성하더라도 그 알림은 보내지 않습니다. 그때부터는 새 알림만 SOC로 갑니다. 채널(Telegram)은 SOC가 있든 없든 작동합니다.

SOC 관리자는 다음을 합니다:

1. 클라이언트용 수집 토큰을 만들어(한 번만 표시됨) 전달합니다. 이 토큰을 `--soc-token` 또는 **관리 › SOC**에서 설정하십시오.
2. `https://<server>:<port of localSIEM>`을 클라이언트의 **SIEM 주소**로 설정합니다(설치 프로그램과 관리 › SOC에 표시됨). 알림을 담당하는 분석가는 이 링크로 와서 조사합니다.
3. SOC의 발신 IP를 알려 줍니다. 이 IP를 허용 IP(`--allow-from` 또는 관리 › 설정)에 추가하고 **방화벽에서 포트를 이 IP와 관리자에게만 여십시오**.

localSIEM은 5분마다 **하트비트**를 보냅니다. SOC가 일정 시간(기본값 60분) 동안 알림도 하트비트도 받지 못하면 SOC 팀에 경고합니다. 알림은 영구 대기열에서 기다립니다. 네트워크가 끊기거나 재시작해도 알림을 잃지 않으며, 알림을 다시 보내도 SOC에서 중복되지 않습니다. 클라이언트의 알림 번호가 모두 소진되었다고 SOC가 응답하면 localSIEM은 전송을 중지하고 대기열을 유지하며 이를 관리 › SOC에 표시합니다.

각 알림에는 고정된 규칙 이름, localSIEM 검색에 붙여 넣을 정확한 쿼리가 담긴 설명, 그리고 세부 정보가 들어 있습니다. 세부 정보는 vhost, 클라이언트 IP, 메서드, URI(마스킹됨), 응답, 사용자 에이전트, ModSecurity 데이터(엔진, 조치, 단계, 점수, 임계값, 규칙, 일치한 데이터), 그룹(횟수, 최초 및 최종 시각, 샘플 `UNIQUE_ID`), 그리고 IP의 **컨텍스트**(최근 1시간 동안의 요청과 차단된 요청, 차단된 규칙, 처음 관측된 시각)입니다.

<a id="signin"></a>
## 6. 로그인과 계정

`https://<server>:10443/`을 여십시오. 로그인 페이지는 로고, 사용자 이름, 비밀번호, **계속**, 그리고 그 아래의 언어와 테마로만 이루어진 양식입니다. 계정은 관리자가 만들며 공개 가입은 없습니다. 비밀번호는 8자 이상입니다. **2단계 인증**은 기본적으로 꺼져 있습니다. 관리자가 켜면(관리 › 설정, 14절) 모든 계정에 필수가 됩니다. 다음 로그인 시 인증 앱(Google Authenticator, Microsoft Authenticator, Aegis, FreeOTP...; «PYMEHackers localSIEM»으로 표시됨)으로 QR 코드를 스캔하고 코드를 입력하면, 그 후로는 로그인할 때마다 앱의 코드를 요구합니다. 여러 번 실패하면 몇 분 동안 로그인이 잠깁니다.

**토큰을 사용한 직접 액세스.** 관리자는 분석가에게 액세스 URL `https://<server>:10443/auth/login/auto?token=...`을 줄 수 있습니다(사용자 › 액세스 토큰, 14절). 허용된 주소에서 이 URL을 열면 비밀번호나 2차 인증 없이 즉시 로그인되고 사용자 대시보드의 개요가 열립니다. 사이트의 다른 페이지를 열려면 `&next=/user/dashboard/search/?q=...`를 추가하십시오. 토큰이 작동하지 않으면 로그인 페이지에 그 이유(알 수 없는 토큰, 만료된 토큰, 폐기된 토큰, 계정이 비활성화되었거나 더 이상 분석가가 아님)가 표시됩니다. URL은 비밀번호처럼 보관하십시오. URL을 가진 사람은 누구나 만료되거나 폐기될 때까지 그 계정으로 로그인할 수 있습니다. 비밀번호나 토큰을 사용한 모든 로그인과 모든 실패한 시도는 기록됩니다(로그인 기록, 14절).

로그인하면 대시보드의 **개요**로 이동합니다(7절). 검색 링크(예: SOC에서 온 링크)를 열면 필요한 경우 로그인 페이지가 열리고, 그다음 **그 검색이 매개변수와 함께 그대로** 열립니다.

역할: **분석가**(사용자 대시보드에서 작업: 개요, 검색, 실시간 보기, 알림, 모듈 상태, 계정)와 **관리자**(관리자 대시보드에서 작업: 같은 내용에 모듈 구성과 관리가 추가됨). 언어(de-DE, en-GB, en-US, es-AR, es-ES, fr-FR, he-IL, hi-IN, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, ru-RU, zh-CN), 테마(시스템, 밝게, 어둡게), UTC 시계는 대시보드의 모든 페이지 제목 표시줄에 있습니다. 로그인 페이지에서는 **계속** 아래에 있으며, 이 브라우저에서 마지막으로 선택한 값으로 시작합니다(선택한 적이 없으면 브라우저와 시스템의 값). **계속**을 누를 때 표시된 언어가 계정의 언어가 됩니다. 대시보드는 어느 브라우저에서든 사용자가 바꿀 때까지 그 언어를 유지합니다. 시각은 항상 UTC이며 기본 형식 `2026/10/29@13:59:59.723`으로 표시됩니다. localSIEM이 기록하는 파일(내보내기, `/root/webapp-credentials.txt`, 설치 프로그램 로그)과 SOC로 보내는 알림은 저장 형식 `2026-10-29@13-59-59.723`을 사용하며, 이것도 UTC입니다.

<a id="dashboards"></a>
## 7. 두 가지 대시보드

역할마다 자체 대시보드가 있으며, 주소를 보면 어느 대시보드에 있는지 알 수 있습니다. 사이드바에는 맨 위에 로고, 탭(그룹 사이에 구분선), 맨 아래에 **로그아웃**이 있습니다.

| | 관리자 대시보드 | 사용자 대시보드 |
|---|---|---|
| 대상 | 관리자 | 분석가 |
| 주소 | `/admin/dashboard/<tab>/` | `/user/dashboard/<tab>/` |
| 탭 | 개요, 검색, 실시간, 알림; 모듈(설치됨, 설치 가능), 사용자(계정, 액세스 토큰), SOC, 채널(일반, Telegram), 설정, 검색 감사, 로그인 기록; 계정 | 개요, 검색, 실시간, 알림, 모듈(상태만), 계정 |

모든 탭에는 자체 주소가 있으며(예: `/admin/dashboard/logins/`), `/admin/dashboard/` 또는 `/user/dashboard/`는 개요를 엽니다. 탭의 섹션에도 주소가 있습니다. `/admin/dashboard/users/`는 `/admin/dashboard/users/accounts/`를 열고 액세스 토큰은 `/admin/dashboard/users/tokens/`에 있습니다. `/admin/dashboard/modules/`는 `/admin/dashboard/modules/installed/`를 열고 설치 가능한 모듈은 `/admin/dashboard/modules/installable/`에 있습니다. 다른 대시보드의 주소를 열면 자신의 대시보드의 같은 탭으로 이동합니다. 관리자가 `/user/dashboard/search/?q=...` 링크(SOC의 일반적인 링크)를 열면 `/admin/dashboard/search/`에서 같은 검색을 보게 되고, 분석가가 관리 탭을 열면 사용자 대시보드의 개요로 이동합니다.

**분석가가 보는 것.** 조사에 필요한 모든 것: 개요, 요청 카드가 포함된 검색, 실시간 보기, 알림, 각 모듈의 상태(켜짐 또는 꺼짐, 작동 여부, 카운터). 분석가는 모듈을 켜거나 끄거나 구성할 수 없고, 모듈의 진단이나 규칙을 볼 수 없으며, 사용자, 액세스 토큰, SOC 연결, 설정, 검색 감사, 로그인 기록을 관리할 수 없습니다.

<a id="overview"></a>
## 8. 개요

두 대시보드의 첫 번째 탭입니다. 15초마다 새로 고쳐지며 다음을 보여 줍니다:

- **이벤트(24시간)**와 그중 알림이 발생한 이벤트 수, ModSecurity가 이미 처리한 것(보관되며 알림 없음)인 **차단됨(24시간)**, 그중 SOC 전송 대기 중인 수가 함께 표시되는 **알림(24시간)**, 그리고 활성화된 모듈 중 «켜짐, 정상 작동»인 모듈 수를 보여 주는 **작동 중인 모듈**(모두 작동하면 녹색).
- **최근 24시간 활동**: 시간당 이벤트. 각 막대의 파란색 부분은 ModSecurity가 차단한 것입니다. 시간대를 클릭하면 해당 시간대의 이벤트 검색이 열립니다.
- **모듈 상태**: 각 모듈의 상태(13절)와 읽고 있는 것. «모듈 보기»를 누르면 모듈 탭이 열립니다.
- **시스템**: 수집기 실행 여부(와 버전), 실행 시작 시각, SOC 연결 상태, 마지막 하트비트, SOC 전송 대기 중인 알림, 디스크 여유 공간, 최대 크기 대비 데이터베이스 크기.
- **최근 알림**: 가장 최근 알림 6개(심각도, 규칙, IP, 횟수, 상태, 최종 시각). «모든 알림 보기»를 누르면 알림 탭이 열립니다.

<a id="search"></a>
## 9. 검색

**검색** 탭에는 검색 필드 하나와 시간 범위(최근 15분, 1시간, 24시간, 7일, 30일 또는 기본 형식의 사용자 지정 범위)가 있습니다.

| 구문 | 의미 |
|---|---|
| `word` | 원본(마스킹된) 텍스트에서 전체 텍스트 검색, URL 디코딩된 텍스트도 포함 |
| `"exact phrase"` | 구문 |
| `field:value` | 필드가 값과 같음(텍스트 필드는 대소문자를 구분하지 않음) |
| `field:*part*` | 와일드카드 |
| `status:>=500`, `status:400..499`, `status:4xx` | 숫자 필드의 비교와 범위 |
| `a b` / `a AND b`, `a OR b`, `NOT a` / `-a`, `( )` | 연산자와 괄호 |

| 그룹 | 필드 |
|---|---|
| 네트워크 | `ip`, `vhost`, `host` |
| 요청 | `method`, `uri`, `path`, `query`, `status`, `bytes`, `duration`(마이크로초), `ua`, `referer` |
| 출처 | `uid`(UNIQUE_ID), `module`, `source`(`access`/`error`/`audit`) |
| ModSecurity | `rule`(CRS ID 또는 `localsiem:<rule>`), `category`, `phase`, `score`, `engine`(`on`/`detection-only`) |
| 알림 | `severity`, `action`(`blocked`/`none`), `alert`(SOC 코드), `sent`(`yes`/`no`) |
| 품질 | `parse`(`ok`/`partial`/`unparsed`) |

예:

- `ip:203.0.113.7` — 한 IP의 모든 기록
- `rule:942100` — 해당 CRS 규칙과 일치한 요청
- `status:200 action:none category:sqli` — 차단되지 않고 200 응답을 받은 SQL 인젝션
- `uri:*wp-login*`
- `"union select"`
- `uid:ZTx1kH8AAQEAAB2gTkAAAAAB` — 단일 요청
- `alert:c00007a0001F` — SOC 알림 하나의 요청
- `(category:sqli OR category:xss) sent:no -status:404`

범주: `sqli`, `xss`, `lfi`, `rfi`, `rce`, `php`, `java`, `fixation`, `generic`, `protocol`, `multipart`, `scanner`, `method`, `data-leakage`, `webshell`, 그리고 localSIEM 규칙의 범주인 `bruteforce`, `enumeration`, `sensitive-file`, `db-error`, 여기에 `health-*`.

구문 오류는 필드 아래에 오류 위치와 함께 표시됩니다. 제한 시간(5초)보다 오래 걸리는 검색은 범위를 좁히라고 안내합니다.

결과 페이지에는 다음이 표시됩니다:

- 시간에 따른 **히스토그램**. 각 막대의 파란색 부분은 ModSecurity가 차단한 것입니다. 막대 위를 드래그하거나 막대 하나를 클릭하면 범위가 좁혀집니다.
- 쿼리의 **요약**: 요청이 가장 많은 IP, 가장 많이 요청된 경로, HTTP 코드, 가장 빈번한 규칙. 값을 클릭하면 쿼리에 추가됩니다.
- **결과 표**(시각, 소스, IP, 메서드, URI, 코드, 조치, 규칙, 알림): 최신 항목이 먼저 표시되며 «더 불러오기»로 더 볼 수 있습니다.
- CSV 또는 JSON으로 **내보내기**(마스킹된 데이터, 최대 10 000행, 시각은 저장 형식 `2026-10-29@13-59-59.723`)와 **링크 복사**(절대 시각 사용). 링크 형식은 `/user/dashboard/search/?q=<query>&from=<native time>&to=<native time>`입니다(관리자가 복사하면 `/admin/dashboard/search/...`). 어느 대시보드의 링크든 두 역할 모두에서 작동합니다.

모든 검색과 내보내기는 기록되며(누가, 무엇을, 언제) 관리자가 볼 수 있습니다. 로그에는 개인 정보가 들어 있기 때문입니다.

<a id="card"></a>
## 10. 요청 카드와 피벗

행을 클릭하면 요청 카드가 열립니다. 시각, vhost, 클라이언트 IP, 메서드, URI, 코드, 크기, 소요 시간, 사용자 에이전트, `UNIQUE_ID`, 상관관계, 수행된 조치, ModSecurity 엔진, 단계, 점수와 임계값, 범주, 심각도, 알림, 그리고 각 레코드의 파싱된 내용(메시지와 데이터가 포함된 일치한 규칙, 요청 헤더와 마스킹된 본문, 응답 헤더, 오류 줄, 원본 줄)이 표시됩니다. 각 레코드의 모듈은 자신이 보여 줄 수 있는 것을 추가합니다(Apache 모듈은 감사 레코드에서 헤더와 본문을 재구성합니다).

카드의 참고 표시: ModSecurity의 흔적이 전혀 없는 403은 **불확실**로 표시됩니다(차단으로 집계하지 않음). **약한 상관관계**는 액세스 로그에 `UNIQUE_ID`가 없어서 액세스 로그 줄을 클라이언트 IP, 메서드, URI, 상태 코드, 시각으로 해당 요청과 결합했다는 뜻입니다. **데이터베이스 오류**는 그 요청에 대해 데이터베이스 오류가 나타났다는 뜻입니다.

피벗: **이 IP**(그 IP의 모든 활동), **±5분**(요청 전후의 타임라인), **규칙 …**(일치한 각 규칙), **이 범주**, **이 UNIQUE_ID**.

<a id="live"></a>
## 11. 실시간 보기

**실시간** 탭은 수집기가 새 이벤트를 저장하는 즉시(5초 상관관계 기간이 지난 후) 최신 이벤트를 맨 위에 표시합니다. 필터는 검색 구문을 사용합니다. **일시 중지**는 업데이트를 멈추며, 재개하면 가장 최신 이벤트부터 이어집니다.

<a id="alerts"></a>
## 12. 알림

**알림** 탭에는 localSIEM이 생성한 알림이 SOC 코드, 심각도, 규칙, IP, vhost, 횟수, 최초 및 최종 시각, 상태와 함께 나열됩니다:

| 상태 | 의미 |
|---|---|
| 버퍼에 있음 | 전송되기 전에 한꺼번에 발생한 이벤트를 모으는 중(60초) |
| 대기열에 있음 | SOC를 기다리는 중(네트워크 장애, SOC 응답 없음) |
| 전송됨 | SOC가 수락함. SOC 코드가 표시됩니다 |
| 거부됨 | SOC가 이 알림을 거부함. 대기열의 나머지는 계속 전송됩니다. 관리 › SOC에서 다시 대기열에 추가할 수 있습니다. |
| 전송 안 됨 | 구성된 SOC가 없었거나 SOC 전송이 꺼져 있었음. 알림은 localSIEM에 남으며 나중에도 전송되지 않습니다(SOC는 선택 사항, 5절) |

행을 클릭하면 설명, **알림의 요청**(최대 50개, 가장 오래된 것부터 표시. 검색에서처럼 하나를 클릭하면 요청, 헤더, ModSecurity 규칙, 원본 줄이 담긴 요청 카드가 열림), 기간, `external_id`, SOC로 전송된 정확한 알림이 표시됩니다. **검색**을 누르면 그룹의 검색이 열립니다. 알림이 열려 있는 동안에는 목록이 새로 고쳐지지 않습니다.

<a id="modules"></a>
## 13. 모듈

관리자 대시보드의 **모듈** 탭에는 각각 자체 주소가 있는 두 섹션이 있습니다. 기본으로 열리는 **설치됨**(`/admin/dashboard/modules/installed/`, `/admin/dashboard/modules/`도 이곳으로 이동)과 모듈을 설치하는 **설치 가능**(`/admin/dashboard/modules/installable/`, 아래 참조)입니다. 분석가에게는 섹션 없이 설치된 모듈 목록만 있습니다(`/user/dashboard/modules/`).

**설치됨**에는 설치된 모듈이 한 행에 하나씩, 전체 너비로, 모듈 페이지의 머리글처럼 배치되어 나열됩니다. 맨 위에 이름, ID, 버전이 있고, 그 아래에 **상태**, 요약, 상태의 이유, 그리고 모듈이 켜져 있으면 카운터(읽고 있는 소스, 최근 1시간의 줄 수, 마지막 데이터, 최근 24시간의 이벤트와 차단된 요청, 진단 결과)가 있습니다. 관리자에게는 이름 오른쪽에 스위치가, 행 맨 아래에 버튼이 함께 표시됩니다. 페이지는 10초마다 새로 고쳐집니다. 설치된 모듈이 없으면 «설치 가능 탭에서 모듈을 설치하십시오.»라고 표시됩니다(분석가에게는 «설치된 모듈이 없습니다. 관리자가 모듈 › 설치 가능에서 설치합니다.»).

| 상태 | 의미 |
|---|---|
| 켜짐, 정상 작동 | 켜져 있고, 수집기가 불러왔으며, 소스를 읽고 있습니다. 진단의 경고는 참고 사항으로 나열되며 상태를 바꾸지 않습니다. |
| 켜짐, 경고 있음 | 켜져 있지만 소스가 없거나, 아직 존재하지 않는 소스가 있거나, 수집기가 시작된 후에 설치되었습니다(`localsiem` 서비스를 다시 시작하십시오). |
| 오류 | 불러올 수 없거나(이유가 표시됨), 진단에서 오류가 보고되었거나, 읽을 수 없는 소스가 있습니다(`localsiem` 사용자의 권한, 3.7절). |
| 변경 사항 적용 중… | 방금 켜거나 껐으며, 수집기가 변경 사항을 적용하는 중입니다(몇 초). |
| 꺼짐 | 꺼져 있습니다. localSIEM은 이 모듈의 로그를 읽지 않고 알림도 보내지 않습니다. 이미 저장된 것은 유지됩니다. 이유가 «이 서버에 모듈에 필요한 것이 없습니다: …»이면 요구 사항 없이 설치된 것이므로 아직 켤 수 없습니다(아래의 요구 사항과 재구성 참조). |
| 알 수 없음 | 수집기가 실행 중이 아닙니다(`localsiem` 서비스). 아무것도 읽고 있지 않습니다. |

**분석가**는 이 목록만 봅니다. **관리자**는 각 행에서 다음도 사용할 수 있습니다:

- 각 모듈을 켜거나 끄는 **스위치**. 끌 때는 확인을 요청합니다. 변경 사항은 아무것도 다시 시작하지 않고 즉시 적용됩니다. 서버에 모듈에 필요한 것이 없는 동안에는 스위치가 잠깁니다(«꺼짐: 요구 사항 누락»).
- **구성**: 모듈 페이지를 엽니다(`/admin/dashboard/modules/installed/<name>/`. 이전 주소 `/admin/dashboard/modules/<name>/`도 이곳으로 이동):
  - 상태, 모듈이 설치된 폴더, 스위치, «설치된 모듈로 돌아가기»(설치됨으로 돌아감), «다시 탐색하고 진단 실행»이 있는 머리글. 요구 사항이 있는 모듈은 «재구성» 버튼도 있으며, 모듈이 꺼져 있거나 요구 사항이 하나라도 충족되지 않은 동안에는 **요구 사항**(아래 참조)도 표시됩니다.
  - **설정**: 모듈 자체 설정 양식. «설정 저장»을 누르면 즉시 적용됩니다.
  - **소스**: 모듈이 읽는 로그(종류, 경로, vhost, 최근 1시간의 줄 수와 파싱되지 않은 줄 수, 마지막 데이터, 상태)와, 그 아래에 찾았지만 읽지 않는 로그와 그 이유.
  - **진단**: 요구 사항 검사. 충족되지 않은 각 항목을 해결하는 설정 조각이나 명령이 «복사» 버튼과 함께 표시됩니다(로그는 설명만 함).
  - **규칙**: 모듈의 각 규칙과 그 스위치(«켜짐»), 심각도, 임계값, 기간(임계값과 기간은 임계값 규칙과 시퀀스 규칙에만 해당). «규칙 저장»을 누르면 즉시 적용됩니다.
- **업데이트**: `localSIEM-modules` 저장소에 모듈의 더 새로운 버전이 있을 때 나타납니다. 설치됨을 열 때마다 localSIEM은 저장소를 확인합니다. 확인하는 동안 «저장소에서 새 버전을 확인하는 중…»이라고 표시되며, 확인에 실패하면 «저장소에서 새 버전을 확인할 수 없었습니다: <error>»라고 표시되고 목록은 평소처럼 작동합니다. 방문할 때마다 저장소를 내려받지 않도록 브라우저는 응답을 10분 동안 재사용합니다. 설치 가능의 «저장소 확인»은 항상 다시 내려받으며, 모듈을 설치, 업데이트, 제거하면 보관된 응답이 폐기됩니다. 10초마다 하는 새로 고침은 저장소를 절대 내려받지 않습니다. 더 새로운 버전이 있는 모듈은 행에 «저장소에 X 버전이 있습니다(설치된 버전: Y).»라는 안내와 **업데이트** 버튼이 표시됩니다. 그 버전에 더 새로운 localSIEM이 필요하면 안내에 버튼이 없고 «저장소에 X 버전이 있지만 localSIEM Z 이상이 필요합니다. 설치하려면 localSIEM을 업데이트하십시오.»라고 표시됩니다. **업데이트**는 확인을 요청합니다(«모듈 업데이트»). localSIEM은 저장소에서 새 버전을 내려받아 설치된 버전과 교체하고 수집기를 다시 시작합니다. 설정은 유지되며, 모듈은 이전처럼 켜진 상태 또는 꺼진 상태로 유지됩니다. 실행되는 동안 버튼에는 «업데이트 중…»이 표시되고, 마지막에 «<module>을(를) X 버전으로 업데이트했습니다.»라는 메시지가 표시됩니다. «<module> 업데이트 완료» 대화 상자는 할 일이 더 있을 때만 열립니다. 새 버전이 다른 로그를 읽으면 root용 명령(`manage.py setup-modules`, 2절, «복사» 포함)을 보여 주고, 수집기가 응답하지 않았으면 `localsiem` 서비스를 다시 시작하라고 요청합니다.
- **제거**: 설치된 각 모듈의 행(불러올 수 없는 모듈 포함)과 모듈 페이지에 있습니다. 확인하면 localSIEM은 `/opt/localsiem/modules/<name>/`를 삭제하고 그 모듈 없이 수집기를 다시 시작합니다. 모듈의 로그 읽기와 알림 전송이 중지됩니다. 이미 저장된 이벤트와 알림은 계속 검색할 수 있으며, 모듈 설정(과 규칙 변경 사항)은 `settings.json`에 남아 다시 설치하면 되살아납니다. root가 `localsiem`에게 부여한 로그 읽기 권한은 회수되지 않습니다. 다른 모듈이 그 폴더를 읽지 않으면 직접 제거할 수 있습니다. 예: `setfacl -R -x g:localsiem /var/log/apache2`와 `setfacl -d -x g:localsiem /var/log/apache2`.

**설치 가능**(관리자 전용)에는 «설치 가능한 모듈» 카드가 있습니다. `localSIEM-modules` 저장소(기본값 `https://github.com/PYMEHackers/localSIEM-modules`, `main` 브랜치. 설치 프로그램 옵션 `--modules-repository`와 `--modules-ref`로 변경)의 모듈 중 이 서버에 아직 설치되지 않은 모듈이 표시됩니다. «저장소 확인»을 누르면 저장소를 내려받아 이 모듈들을 나열하며, 각 모듈에는 이름, ID, 버전, 요약과 버튼 또는 안내가 표시됩니다:

| 버튼 또는 안내 | 의미 |
|---|---|
| 요구 사항 | 모듈이 서버에서 필요로 하는 것과 이를 설치하는 명령을 보여 줍니다(아래 참조) |
| 설치 | 모듈을 설치합니다 |
| localSIEM X 이상 필요 | 설치할 수 없습니다. 먼저 localSIEM을 업데이트하십시오 |
| 저장소의 모듈이 유효하지 않습니다 | 설치할 수 없습니다 |

**요구 사항**을 누르면 «<module>: 요구 사항» 대화 상자가 열리며, 모듈 자체가 선언한(`module.json`의 `install_requirements`) 서버에서 필요한 것과 이를 설치하는 명령이 표시됩니다. 모듈을 설치해도 모듈이 감시하는 소프트웨어는 설치되지 않으므로, 모듈을 설치하기 **전에** 서버에서 이 명령을 실행하십시오. 대화 상자에는 이 서버의 시스템(«이 서버: Debian GNU/Linux 13 (trixie)»)에 맞는 명령이 각각 «복사»와 함께 두 번 표시됩니다. **root로 실행**과 **sudo를 사용하여 실행**(같은 명령 앞에 `sudo`를 붙인 것)이므로, 서버의 터미널에 root로 또는 sudo 사용 권한이 있는 사용자로 붙여 넣을 수 있습니다. 모듈의 참고 사항이 먼저 표시됩니다(예: Alpine에는 ModSecurity 2 패키지가 없다는 것). 모듈이 이 서버의 시스템에 대한 명령을 선언하지 않으면 대화 상자에는 모듈이 선언한 모든 시스템(Debian과 Alpine)의 명령이 표시되고, 아무것도 선언하지 않으면 «이 모듈은 서버에 설치할 항목을 선언하지 않습니다.»라고 표시됩니다. localSIEM은 이 명령을 절대 실행하지 않습니다.

저장소의 모든 모듈이 이미 설치되어 있으면 그렇게 알려 줍니다(«저장소의 모든 모듈이 이미 설치되어 있습니다.»). 이미 설치된 모듈은 이 목록에 나타나지 않으며, 설치됨에서 업데이트합니다(위의 **업데이트**). 웹은 모듈을 재설치하거나 이전 버전을 설치하지 않습니다. 모듈을 재설치하려면 제거한 다음 여기에서 다시 설치하십시오(설정은 유지됩니다).

이 목록이 모듈을 설치하는 유일한 방법입니다. localSIEM은 모듈을 내려받아 `module.json`을 확인하고, 모듈 폴더(저장소의 `mod-<name>/`)를 `/opt/localsiem/modules/<name>/`에 복사한 다음(`tests/` 폴더 제외. 다시 설치한 모듈은 이전 설정을 되찾습니다) 수집기를 다시 시작하며, 수집기는 몇 초 안에 모듈을 불러옵니다. 모듈은 목록에서 사라지고 «<module> 설치 완료» 대화 상자에 다음에 할 일이 표시됩니다:

- `localsiem`이 모듈의 로그를 읽게 하려면 root 권한이 필요하므로, 대화 상자에 서버에서 **root로 실행할 명령**이 «복사» 버튼과 함께 표시됩니다. 읽기 권한을 부여하고 localSIEM을 다시 시작하는 `manage.py setup-modules`(2절)입니다. 이 명령을 실행하기 전까지는 로그를 읽을 수 없으므로 모듈에 «오류»가 표시될 수 있습니다.
- 첫 설치 시 서버에 모듈에 필요한 것이 없으면 모듈은 꺼진 상태로 설치되며, 대화 상자에는 명령 대신 없는 것이 나열되고, 그것이 갖춰지면 설치됨에서 모듈을 열고(**구성**) **재구성**을 누르라는 안내가 표시됩니다(아래 참조).

대화 상자에는 «닫기»와 설치됨을 여는 «설치된 모듈 보기», 두 개의 버튼이 있습니다. 이 목록과 설치됨의 새 버전 확인을 위해 서버가 GitHub(HTTPS)에 연결할 수 있어야 합니다.

**요구 사항과 재구성.** 모듈을 설치해도 모듈이 감시하는 소프트웨어는 설치되지 않습니다. 모듈은 켜기 전에 서버에 있어야 하는 것을 선언할 수 있습니다. Apache 모듈에는 Apache(그 구성: `apache2.conf`, `httpd.conf` 또는 **Apache 구성 파일** 설정의 파일)와 불러온 상태의 ModSecurity 2(`mod_security2`. ModSecurity 3은 해당되지 않음)가 필요합니다. 첫 설치 시 이것들이 없으면 모듈은 **꺼진 상태로** 설치되고(«꺼짐», 이유는 «이 서버에 모듈에 필요한 것이 없습니다: …») 스위치가 **잠깁니다**. 모듈 페이지에는 꺼져 있는 동안에도 진단처럼 요구 사항(제목, 세부 내용, 없는 것을 설치하는 명령과 «복사»)이 나열됩니다. 없는 것을 설치했으면(그리고 Apache가 표준이 아닌 위치에 있으면 **Apache 구성 파일**을 설정하고 설정을 저장했으면) **재구성**을 누르십시오. localSIEM이 저장된 설정으로 다시 찾습니다.

- 모든 것을 찾으면 스위치 잠금을 해제하지만 모듈을 켜지는 않습니다. 모듈은 스위치로 직접 켜십시오. 2절의 root용 명령도 표시되므로 실행하십시오. 모듈을 설치한 후에 만들어진 로그(`/var/log/apache2`)는 root가 부여하는 읽기 권한이 있어야만 읽을 수 있기 때문입니다.
- 아직 없는 것이 있으면 요구 사항에 다시 표시됩니다.
- 모듈이 이미 켜져 있으면 재구성은 소스를 다시 탐색하고 진단도 실행합니다.

켜져 있던 모듈이 나중에 요구 사항을 잃으면(누군가 ModSecurity를 제거하면) 모듈은 켜진 상태로 유지됩니다. 진단과 상태 경고 «ModSecurity is no longer loaded»(15절)가 이를 보고하며, 모듈을 끄면 바로 그 경고가 나오지 않게 됩니다. 수집기는 시작할 때와 설정이 바뀔 때 요구 사항을 확인하며, 주기적으로 확인하지는 않습니다. `manage.py modules`와 `manage.py doctor`도 요구 사항을 보여 줍니다(17절).

**Apache 모듈 끄기와 켜기.** **모듈 › 설치됨**에서 «Apache + ModSecurity»의 스위치를 사용하고 확인하십시오. 꺼져 있는 동안 localSIEM은 Apache 로그를 읽지 않고, 진단과 규칙도 실행하지 않으며, 이 모듈의 알림도 보내지 않습니다. 이미 저장된 이벤트는 계속 검색할 수 있습니다. 다시 시작하려면 스위치를 다시 켜십시오(Apache와 ModSecurity가 있을 때만 가능). 수집기는 각 로그에서 멈췄던 위치부터(그 사이에 일어난 로테이션을 따라가며) 이어서 읽으므로, 모듈이 꺼져 있던 동안 Apache가 기록한 내용도 읽고 필요한 알림을 보냅니다.

**Apache 모듈 설정**(모듈 › 설치됨 › Apache + ModSecurity › 구성):

| 설정 | 용도 |
|---|---|
| 아래 소스만 사용 | Apache 구성에서 로그를 탐색하지 않고 직접 추가한 소스만 읽습니다 |
| 직접 추가한 소스 | 탐색된 로그 외에 읽을 로그(아래 참조) |
| Apache 구성 파일 | 비워 두면 자동으로 찾습니다(Debian은 `/etc/apache2/apache2.conf`, Alpine은 `/etc/apache2/httpd.conf`). 재구성도 이곳에서 Apache를 찾습니다 |
| 탐색 간격(초) | 새 vhost와 로그를 찾기 위해 Apache 구성을 다시 읽는 주기(기본값 3600) |
| ModSecurity 차단 임계값 | 0: CRS 구성(`tx.inbound_anomaly_score_threshold`)에서 읽으며, 값이 없으면 5 |
| 새 PHP 파일 학습 기간(일) | 처음 며칠 동안은 처음 보는 PHP 파일을 새 파일로 보고하지 않습니다(`apache-webshell` 규칙, 기본값 3) |

**로그 직접 추가.** **직접 추가한 소스**에서 «소스 추가»를 누르고 **종류**(access.log, error.log 또는 ModSecurity 감사 로그), **경로**(절대 경로), 필요하면 **Vhost**, **LogFormat**(자체 형식의 액세스 로그인 경우), **감사 로그 유형**(직렬 또는 동시), **감사 저장 폴더**(동시 감사 로그인 경우)를 입력하십시오. «삭제»는 소스를 삭제합니다. «설정 저장»을 누르십시오. 수집기가 즉시 소스를 다시 탐색하고 새 로그가 **소스**에 나타납니다. 읽을 수 없는 것으로 표시되면 `localsiem`에게 그 폴더의 읽기 권한을 부여하십시오(3.7절).

**`apache` 모듈에서 `apache2` 모듈로.** localSIEM 2.1까지 Apache 모듈의 이름은 `apache`였으며, 지금은 `apache2`입니다(저장소의 `mod-apache2/` 폴더, `/opt/localsiem/modules/apache2/`에 설치, 페이지 `/admin/dashboard/modules/installed/apache2/`). `apache`가 있던 서버에 `apache2`를 설치하면 두 모듈이 모두 불러온 상태가 됩니다. 이전 모듈이 Apache 로그를 계속 차지하고(두 모듈이 같은 소스를 찾음), `apache2`는 이전 모듈이 제거될 때까지 소스를 표시하지 않으며, `apache`의 설정은 저절로 옮겨지지 않습니다. 마이그레이션하려면:

1. `apache` 모듈 페이지(구성)에서 변경한 설정을 적어 두십시오: 직접 추가한 소스, Apache 구성 파일, 탐색 간격, 차단 임계값, 학습 기간.
2. 모듈 › 설치 가능에서 `apache2`를 설치하십시오.
3. `apache` 모듈을 제거하십시오: 모듈 › 설치됨의 해당 행이나 모듈 페이지에서 **제거**. 수집기가 다시 시작되고 그때부터 `apache2`가 Apache 로그를 읽습니다.
4. `apache2` 페이지를 열고 그 설정을 다시 입력하여 저장하십시오. (대신 root로 `/opt/localsiem/config/settings.json`의 `"modules"` 안에서 `"apache"` 아래에 있는 내용을 `"apache2"`로 복사한 다음 localSIEM을 다시 시작할 수도 있습니다.)

규칙은 ID(`apache-bruteforce`…)와 변경 사항을 유지하며, 각 로그에서 읽은 위치와 상태 경고의 기록도 유지됩니다. `apache2`는 `apache`가 멈춘 곳에서 이어서 읽으며 아무것도 두 번 읽지 않습니다. `apache` 모듈이 저장한 이벤트는 계속 검색할 수 있습니다(`module:apache`).

<a id="administration"></a>
## 14. 관리

다음 탭은 관리자 대시보드에만 있습니다:

- **모듈**(13절): 두 섹션으로 구성됩니다. **설치됨**(`/admin/dashboard/modules/installed/`)은 각 모듈의 스위치가 있는 목록과 **구성**(모듈의 요구 사항과 재구성, 설정, 소스, 진단, 규칙), **업데이트**(저장소에 더 새로운 버전이 있을 때), **제거**를 제공하고, **설치 가능**(`/admin/dashboard/modules/installable/`)은 아직 설치되지 않은 저장소의 모듈을 **요구 사항**, **설치**와 함께 보여 줍니다. 모듈은 이곳에서만 설치, 업데이트, 제거합니다.
- **사용자 › 계정**(`/admin/dashboard/users/accounts/`): 계정 만들기(비밀번호가 생성되어 한 번만 표시되며, 첫 로그인 시 변경해야 함), 비밀번호 또는 2단계 인증 재설정, 활성화 또는 비활성화, 역할 변경, 삭제. 활성 관리자가 항상 한 명 이상 있습니다.
- **사용자 › 액세스 토큰**(`/admin/dashboard/users/tokens/`): 활성 분석가 계정에 대해 **토큰 생성**(관리자는 항상 비밀번호로, 2단계 인증이 켜져 있으면 2차 인증까지 사용하여 로그인합니다). 레이블(선택 사항)과 유효 기간 7일, 30일, 90일(기본값), 180일 또는 365일을 지정합니다. 액세스 URL `https://<server>:10443/auth/login/auto?token=...`은 «복사» 버튼과 함께 **한 번만** 표시되므로 분석가에게 전달하십시오(6절). 목록에는 각 토큰의 계정과 레이블, 마지막 4자, 상태(활성, 만료됨, 폐기됨, 또는 계정이 비활성화되었거나 더 이상 분석가가 아니면 사용 불가), 생성 시각과 생성자, 만료 시각, 마지막 사용(시각과 IP)이 표시됩니다. **폐기**는 토큰을 즉시 중지하며, 토큰으로 이미 열린 세션은 만료될 때 종료됩니다. 토큰으로 연 세션은 2차 인증도 비밀번호 변경도 요구하지 않습니다. 실패한 시도는 로그인의 일시 잠금에 집계됩니다.
- **SOC**: URL, 토큰(전체가 표시되지 않음), CA 파일(선택 사항), **연결 테스트**(하트비트 전송), 전송 상태, 마지막 하트비트, 마지막 오류, 대기열(대기 중, 전송됨, 거부됨), **지금 대기열 전송**. SOC에 알려 줄 SIEM 주소도 있습니다. SOC는 선택 사항입니다(5절).
- **채널**(`/admin/dashboard/channels/`): **일반**(기본으로 열림)과 **Telegram**, 두 섹션으로 구성됩니다. localSIEM이 SOC에 전달하는 알림과 별도로 사용자에게 보내는 메시지입니다(아래 참조).
- **설정**: 보존, 최대 디스크 사용량, 허용 IP(자신의 주소가 목록에 있어야 함), 2단계 인증(기본값은 꺼짐. 켜면 모든 계정에 필수가 되며, 아직 설정하지 않은 계정은 본인 계정을 포함하여 즉시 로그아웃되고 다음 로그인 시 설정합니다. 끄면 이미 설정된 인증 앱은 다시 켤 때를 위해 유지됩니다), 검색 제한 시간, 내보내기 제한, 그룹화 기간과 버퍼, 상관관계 기간, 임계값 미만의 심각도. 변경 사항은 즉시 적용됩니다. 규칙은 더 이상 이곳에 없으며, 각 모듈에서 구성합니다(모듈 › 설치됨 › 구성).
- **검색 감사**: 누가 언제 무엇을 검색했는지.
- **로그인 기록**(`/admin/dashboard/logins/`): localSIEM의 모든 로그인과 모든 실패한 시도(최신 항목이 먼저 표시): 시각, 계정, 방식(비밀번호, 비밀번호 및 2차 인증, 또는 액세스 토큰), 결과(성공 또는 실패), 실패 사유(잘못된 사용자 이름 또는 비밀번호, 잘못된 2차 인증 코드, 여러 번 실패하여 잠김, 로그인 시간 초과, 알 수 없는/만료된/폐기된 토큰, 비활성화된 계정, 분석가 계정이 아님), IP, 브라우저. 결과로 필터링할 수 있으며, **더 불러오기**는 이전 항목을 불러옵니다. 알림과 같은 기간(기본값 365일) 동안 보관됩니다.

수집기, 디스크, 데이터베이스의 상태는 개요(8절)에 있습니다.

### 채널: 사용자에게 보내는 메시지(Telegram)

localSIEM은 모든 알림을 SOC로 전달하는 것과 별도로, 가장 중요한 알림을 **채널**로 보낼 수 있습니다. 현재 채널은 **Telegram**입니다.

**일반**(`/admin/dashboard/channels/general/`):

- **채널로 메시지 보내기**: 모든 채널을 한꺼번에 켜거나 끕니다.
- **최소 심각도**: 이 심각도 이상의 알림이 전송됩니다(기본값: 높음).
- **메시지 언어**: 웹의 15개 언어 중 하나(기본값 en-US). 알림의 규칙과 설명은 localSIEM이 작성한 그대로 유지됩니다.
- 각 채널의 표: 상태(꺼짐, 구성되지 않음, 작동 중 또는 오류), 보낸 메시지, 마지막으로 보낸 메시지, 마지막 오류.

**Telegram**(`/admin/dashboard/channels/telegram/`):

1. Telegram에서 **@BotFather**를 열고 `/newbot`을 보낸 다음 안내에 따르십시오. **봇 토큰**(`123456789:AA...`. 콜론 앞의 숫자가 봇 ID)을 받게 됩니다.
2. 봇과의 채팅을 열고 **시작**을 누르십시오(또는 메시지를 받을 그룹에 봇을 추가하거나, 메시지를 받을 채널에 봇을 관리자로 추가하십시오). 봇은 먼저 말을 걸어 온 적이 없는 상대에게 메시지를 보낼 수 없습니다.
3. **채팅 ID**를 확인하십시오. 봇에게 아무 메시지나 보낸 다음 브라우저에서 `https://api.telegram.org/bot<token>/getUpdates`를 여십시오. ID는 `"chat":{"id":` 뒤의 숫자입니다. 그룹 ID는 `-`로, 채널 ID는 `-100`으로 시작합니다. 공개 채널이나 그룹은 `@username`으로도 지정할 수 있습니다.
4. 토큰과 채팅 ID를 입력하고 **Telegram으로 메시지 보내기**를 선택한 다음 **저장하고 테스트 메시지 보내기**를 누르십시오. Telegram이 거부하면 안내에 그 이유가 표시됩니다(예: `Unauthorized`: 잘못된 토큰, `Bad Request: chat not found`: 잘못된 채팅 ID이거나 아무도 시작을 누르지 않음).

토큰은 서버의 `/opt/localsiem/config/telegram-bot-token`(모드 600)에 보관되며 전체가 표시되지 않습니다. **토큰 삭제**는 토큰을 삭제하고 Telegram을 끕니다. 서버가 `https://api.telegram.org`(발신 포트 443)에 연결할 수 있어야 합니다.

각 메시지에는 심각도, 규칙, 설명, 모듈, 이벤트 수, 최초 및 최종 시각(UTC), 그리고 그 이벤트를 보여 주는 검색이 담깁니다. localSIEM은 1초에 최대 한 개의 메시지를 보냅니다. Telegram이 응답하지 않으면 몇 번 다시 시도하며, Telegram이 메시지를 거부하면(잘못된 토큰, 알 수 없는 채팅, 차단된 봇) 메시지를 버리고 오류를 표시합니다. 대기 중인 메시지는 localSIEM이 다시 시작되면 사라집니다. 채널은 사용자에게 알리는 수단일 뿐이며, SOC는 여전히 모든 알림을 받습니다.

<a id="health"></a>
## 15. 상태 경고와 대처 방법

이 경고도 SOC로 전송되며(규칙 `localSIEM health: …`), 반복되지 않도록 그룹화됩니다:

| 경고 | 심각도 | 대처 방법 |
|---|---|---|
| 로테이션이 아닌 방식으로 로그가 잘리거나, 사라지거나, 교체됨 | 높음 | 누군가 흔적을 지우고 있을 수 있습니다. 그 시각에 서버에 접근한 사람과 서버의 다른 로그를 확인하십시오. |
| ModSecurity를 더 이상 불러오지 않음(ModSecurity is no longer loaded) 또는 엔진이 Off로 전환됨 | 높음 | 아무도 의도적으로 하지 않았다면 보호가 비활성화된 것입니다. Apache 구성과 최근 변경 사항을 확인하십시오. |
| 로그 소스를 읽을 수 없음 | 중간 | 대개 로테이션 후의 권한 문제입니다. 2절의 명령(`manage.py setup-modules`)을 root로 다시 실행하거나 `localsiem`에게 읽기 권한을 부여하십시오(3.7절). 이 경고는 localSIEM이 이전에 읽을 수 있었던 로그에서만 발생합니다. 한 번도 읽을 수 없었던 로그(2절의 명령을 실행하기 전의 방금 설치한 모듈)는 모듈 상태에만 표시됩니다(«오류», 읽을 수 없는 소스가 있음). |
| 로그 소스가 오랫동안(24시간) 조용함 | 중간 | Apache가 여전히 그 파일에 기록하는지 확인하십시오(로깅 변경, 디스크 가득 참). |
| 실제 클라이언트 IP 누락(Real client IP missing) | 중간 | 거의 모든 요청이 하나의 사설 주소에서 옵니다. 웹이 프록시 뒤에 있고 Apache가 프록시의 IP를 기록하므로, IP 기반 규칙이 그 요청에 대해 작동하지 않습니다. |
| 파싱되지 않은 줄이 많음(5 % 초과) | 낮음 | 로그 형식이 바뀌었습니다. 모듈 페이지(모듈 › 설치됨 › 구성)에서 «다시 탐색하고 진단 실행»을 눌러 모듈이 새 형식을 읽게 하십시오. 진단은 각 로그의 형식을 설명합니다. |
| 디스크 여유 공간 부족, 또는 공간 부족으로 보존 데이터 축소 | 중간 | 공간을 확보하거나 최대 디스크 사용량을 늘리십시오. 그동안 localSIEM은 세부 정보를 덜 저장합니다. |

<a id="retention"></a>
## 16. 보존과 디스크

이벤트는 90일, 알림은 365일 동안 보관됩니다. 데이터베이스는 최대 크기(기본값: 디스크의 15 %와 10 GB 중 작은 값)를 넘어 커지지 않습니다. 가장 오래된 이벤트부터 작은 단위로 삭제되며, 그 공간은 디스크로 반환됩니다. 디스크 여유 공간이 적으면 localSIEM은 용량이 큰 세부 정보(감사 레코드의 헤더와 본문)를 저장하지 않고, 거의 없으면 알림에 관련된 이벤트만 저장하며 SOC에 경고합니다. 값은 `--retention-days`와 `--max-disk`(예: `--max-disk 5G`) 또는 관리 › 설정에서 변경하십시오.

<a id="cli"></a>
## 17. 명령줄

root로 `/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py`를 실행합니다:

| 명령 | 용도 |
|---|---|
| `list-users` | 계정과 각 계정의 2단계 인증 |
| `create-user NAME --role admin\|analyst --credentials /root/webapp-credentials.txt` | 생성된 비밀번호로 새 계정 만들기 |
| `reset-password NAME --credentials /root/webapp-credentials.txt` | 새 비밀번호(다음 로그인 시 변경) |
| `reset-mfa NAME` | 다음 로그인 시 2단계 인증을 다시 설정 |
| `doctor` (`--json`) | 활성화된 모든 모듈의 요구 사항과 소스, 그리고 꺼져 있고 요구 사항이 있는 모듈의 경우 켜기 전에 필요한 것(`localsiem`으로 실행, 4절) |
| `modules` | 설치된 모듈: 이름, 버전, 활성화/비활성화/불러오지 않음 여부, 폴더, 그리고 모듈 아래에 서버에 없는 요구 사항. 불러올 수 없는 모듈과 그 이유도 표시 |
| `read-paths` | 설치된 모듈이 읽는 폴더(`setup-modules`와 설치 프로그램이 `localsiem`에게 이 폴더의 읽기 권한을 부여함) |
| `soc-test` | SOC로 하트비트를 보냅니다 |
| `setup-modules` | root로 실행하며, 웹이 모듈 설치 후, 모듈이 읽는 로그를 바꾸는 업데이트 후, 그리고 재구성 시 보여 주는 명령입니다. 설치된 모듈의 폴더에 대한 `localsiem`의 읽기 권한 부여(ACL, 다음 로테이션 포함, Debian에서는 `adm` 그룹), localSIEM 재시작, `localsiem`으로 진단 실행. `--no-restart`(설치 프로그램이 사용)를 지정하면 읽기 권한만 부여합니다. |

모듈은 웹에서만 설치, 업데이트, 제거합니다(13절). 이를 위한 명령은 없습니다.

서비스: localSIEM은 시스템 사용자 `localsiem`의 두 서비스, 즉 수집기(`localsiem`)와 웹(`localsiem-web`)으로 실행됩니다. `systemctl status localsiem localsiem-web`으로 상태를 보고 `systemctl restart localsiem localsiem-web`으로 다시 시작하며(Debian), Alpine에서는 `rc-service localsiem status; rc-service localsiem-web status`와 `rc-service localsiem restart; rc-service localsiem-web restart`를 사용합니다. `/opt/localsiem/modules/`에서 모듈을 직접 복사하거나 삭제한 후에는 두 서비스를 모두 다시 시작하십시오(웹은 모듈을 설치, 업데이트, 제거할 때 스스로 다시 시작합니다). 로그: `journalctl -u localsiem -u localsiem-web`(Debian) 또는 `/opt/localsiem/log/`(Alpine). 수집기는 시작할 때 각 모듈과 그 버전, 켜짐/꺼짐 여부가 담긴 `Modules: ...` 줄을 기록하고, 요구 사항이 충족되지 않은 모듈에 대해서는 `Module <name>: requirements missing: ...`을 기록합니다.

**서버의 파일**

| 경로 | 내용 |
|---|---|
| `/opt/localsiem/webapp/` | 코어 코드 |
| `/opt/localsiem/modules/` | 설치된 모듈(모듈마다 폴더 하나, `apache2/`). 웹이 `localSIEM-modules`에서 설치 |
| `/opt/localsiem/venv/` | Python 의존성(시스템의 것과 분리) |
| `/opt/localsiem/config/` | 설정, 설치 프로그램 옵션(`install.env`), SOC 토큰과 비밀 값(모드 600) |
| `/opt/localsiem/db/` | 데이터베이스 |
| `/opt/localsiem/certificates/` | 웹 인증서 |
| `/opt/localsiem/log/`, `/opt/localsiem/run/` | 로그(Alpine)와 런타임 파일 |
| `/root/webapp-install.log`, `/root/webapp-credentials.txt` | 설치 프로그램 로그와 설치 프로그램이 만든 비밀번호(모드 600) |
