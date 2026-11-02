# localSIEM 코드 참조

이 CODE는 다음 언어로도 제공됩니다:\
[de-DE](CODE.de-DE.md), [en-GB](CODE.en-GB.md), [en-US](CODE.md), [es-AR](CODE.es-AR.md), [es-ES](CODE.es-ES.md), [fr-FR](CODE.fr-FR.md), [he-IL](CODE.he-IL.md), [hi-IN](CODE.hi-IN.md), [it-IT](CODE.it-IT.md), [ja-JP](CODE.ja-JP.md), ko-KR, [pt-BR](CODE.pt-BR.md), [pt-PT](CODE.pt-PT.md), [ru-RU](CODE.ru-RU.md), [zh-CN](CODE.zh-CN.md)

## 목차

1. [아키텍처와 설계](#architecture)
2. [모듈 맵](#modules)
3. [주요 심볼](#symbols)
4. [주요 호출 경로](#flows)
5. [라우트와 진입점](#routes)
6. [영향 분석](#impact)
7. [확장 지점](#extensions)
8. [측정된 리소스 사용량](#resources)

[설치](README.ko-KR.md) · [사용자 매뉴얼](MANUAL.ko-KR.md)

<a id="architecture"></a>
## 1. 아키텍처와 설계

localSIEM은 **하나의 Linux 서버**를 위한 경량 SIEM으로, 바로 그 서버에 설치됩니다(서버마다 localSIEM 하나). 서버의 서비스 로그(자신의 서버 로그만 해당하며, 원격 입력은 없음)를 읽어 검색 가능한 데이터베이스에 저장하고, 아직 사람의 판단이 필요한 것을 가려내어 PYMEHackers SOC(`soc.pymehackers.com`)로 보냅니다. SOC 분석가는 localSIEM의 검색 도구로 알림을 조사합니다. 버전 2.2.0([backend/core/config.py](../backend/core/config.py)의 `cVersion`).

### 기본 원칙: «조치가 취해지지 않은 것은 SOC로»

SOC에 도달하는 모든 것은 아직 아무도 해결하지 않은 것입니다:

| 상황 | `action` | SOC로? |
|---|---|---|
| ModSecurity가 1-2단계에서 차단함(애플리케이션이 요청을 받지 않음) | `blocked` | 아니요: localSIEM에 저장되어 검색할 수 있으며, 그 IP의 다음 알림의 `context`에 집계됨 |
| ModSecurity가 3-4단계에서 차단함(애플리케이션이 이미 요청을 실행함) | `none` | 예 |
| 엔진이 `DetectionOnly`일 때의 규칙 일치 | `none` | 예 |
| 이상 임계값 미만의 규칙 일치 | `none` | 예(심각도 `low`, 구성 가능) |
| 모듈 규칙의 신호(무차별 대입, 웹 셸...)와 상태 신호 | `none` | 예 |

조치가 취해지지 않은 모든 일치는 점수와 관계없이 SOC로 갑니다. 민감한 데이터(비밀번호, 쿠키, `Authorization`, 토큰, 요청 본문)는 무엇이든 저장하기 전에 마스킹되며 절대 SOC로 전송되지 않습니다.

### 두 개의 프로세스, 하나의 기록자

| 서비스 | 프로세스 | 역할 |
|---|---|---|
| `localsiem` | [backend/collector.py](../backend/collector.py) | 모듈을 불러오고, 소스를 읽고, 파싱하고, 상관 분석하고, 규칙을 적용하고, 저장하고, 그룹화하고, SOC로 보내고, 하트비트를 보냅니다. **이벤트 데이터베이스에 쓰는 유일한 프로세스입니다.** |
| `localsiem-web` | [backend/server.py](../backend/server.py) | 자체 포트(항상 10443, `config.cWebPort`)에서 HTTPS를 직접 제공하는 FastAPI + uvicorn. 이벤트 데이터베이스를 읽으며, 자체 데이터베이스(계정, 세션, 검색 감사)와 `settings.json`에만 씁니다. |

웹은 Unix 소켓 `/opt/localsiem/run/collector.sock`(JSON 줄)을 수집기에 명령을 내릴 때만 사용합니다. 관리자가 설정이나 모듈을 변경하거나 재구성을 누른 후 수집기가 즉시 적용하도록 하는 `reload`, `doctor`, 웹에서 모듈을 설치, 업데이트, 제거한 후의 `restart`, 그리고 SOC 대기열의 재시도와 재대기열 추가입니다. 수집기는 계속 이벤트 데이터베이스의 유일한 기록자입니다. 웹이 중지되어도 수집과 알림은 계속됩니다. 실시간 보기는 마지막 이벤트 ID를 기준으로 데이터베이스를 폴링합니다.

### 코어와 모듈

코어는 Apache에 대해 아무것도 모르며 **어떤 모듈도 이름으로 가져오지 않습니다**. 스토리지, 검색, 규칙 엔진, 그룹화, SOC 대기열, 하트비트, 상태 점검은 범용입니다([backend/core/](../backend/core/)). 서버의 각 서비스는 하나의 모듈입니다. 모듈은 `module.json`, `Module`([backend/core/module.py](../backend/core/module.py))의 하위 클래스 코드(탐색, 입력, 프레이밍과 파싱, 상관 분석, 수행된 조치의 결정, YAML 규칙, 보강, 진단, 요구 사항(`mRequirements`), 상태 신호, 웹 및 root 훅을 제공), 텍스트가 담긴 `locales/<language>.json`을 가진 폴더입니다.

레지스트리([backend/core/registry.py](../backend/core/registry.py))는 한 곳에서만 모듈을 찾습니다. 코어에는 자체 모듈이 없습니다:

| 위치 | 모듈 | 가져오는 방식 |
|---|---|---|
| `cModulesPath` = `/opt/localsiem/modules/<name>/`(개발용 사본에서는 `LOCALSIEM_MODULES_PATH`) | 웹만이 설치, 업데이트, 제거합니다(모듈 › 설치 가능, 그리고 모듈 › 설치됨의 업데이트와 제거, [backend/core/catalog.py](../backend/core/catalog.py)). `localSIEM-modules` 저장소(GitHub)에서 가져오며, 그 저장소에서 각 모듈의 폴더는 `mod-<name>/`입니다. localSIEM 설치 프로그램은 절대 설치하지 않습니다. 현재 `apache2`(access.log, error.log, ModSecurity 감사 로그, 폴더 `mod-apache2/`)와 `privesc`(권한 상승, 폴더 `mod-privesc/`)가 있으며, 그 프로젝트에 문서화되어 있습니다 | 네임스페이스 패키지 `localsiem_modules.<name>.<file>`: `__init__.py`가 없으며, 모듈은 자신의 파일을 상대 경로로, 코어를 `backend.core.*`로 가져옵니다 |

`module.json`에는 다음이 들어 있습니다: `id`(폴더 이름, 저장소에서는 `mod-` 제외: `[a-z][a-z0-9_]{1,31}`), `version`, `core`(필요한 최소 localSIEM 버전. 더 새로운 버전이 필요하면 불러오지 않음), `entry`(`"file:Class"`), `default_enabled`, `read_paths`(`manage.py setup-modules`와 설치 프로그램이 ACL을 통해 `localsiem`이 읽을 수 있게 하는 폴더), 그리고 `settings`: `{key, type, default, ...}`의 목록이며 type은 `boolean`, `integer`(`min`, `max`), `string`(`max_length`), `path`(절대 경로), `choice`(`choices`) 또는 `records`(`fields`, `max_items`. 직접 추가한 소스 같은 작은 레코드의 목록)입니다. 웹은 이 목록으로 설정 양식을 만들고, 레지스트리는 관리자가 저장한 값을 검증합니다(`fValidateSettings`). 이전 `module.json` 파일의 `setup_option`은 무시됩니다(`fReadManifest`). 모듈에는 셋업 옵션이 없습니다. `install_requirements`(선택 사항)에는 `{system: [command, ...]}`가 들어 있으며, system은 `debian` 또는 `alpine`입니다(`lSystems`). 모듈에 필요한 소프트웨어를 서버에 root로 설치하는 명령입니다. 웹은 이 명령을 보여 주기만 하며(모듈 › 설치 가능 › 요구 사항), 그대로의 형태와 앞에 `sudo`를 붙인 형태로 보여 주므로 각 항목은 단일 명령이어야 합니다. `fCheckInstallRequirements`는 `;`, `&`, `|`, `<`, `>`, 백틱, `$(`, 줄 바꿈, 그리고 20개를 넘는 명령을 거부합니다. 참고 사항은 모듈의 로캘에 넣습니다(모든 시스템용 `install_requirements.note`와 `install_requirements.<system>`).

모듈의 설정은 `settings.json`의 `modules.<name>` 아래에 있으며, `module.json`의 기본값 위에 적용됩니다(`fModuleSettings`, `Module.mModuleSettings`). `config.dDefaults`의 기본값에는 더 이상 어떤 모듈도 들어 있지 않습니다. `modules.<name>.enabled`는 아무것도 다시 시작하지 않고 모듈을 켜고 끕니다. 수집기는 그 모듈의 소스 탐색과 읽기, 진단, 상태 점검을 중지합니다. 불러오기에 실패한 모듈(잘못된 `module.json`, 더 새로운 `core`, 가져오기 오류, `mStart`의 예외)은 수집기 로그, `collector.status.module_errors`, 진단, 웹에 보고되며, 나머지 모듈은 계속 작동합니다.

**요구 사항.** 모듈을 설치해도 모듈이 감시하는 소프트웨어는 설치되지 않습니다. `Module.mRequirements()`는 모듈을 켜기 전에 서버에 있어야 하는 것을 `mDoctor` 형식의 검사(`{id, status: ok|error, title, detail, fix}`)로 반환합니다. 오류인 검사가 없으면 충족된 것이며, `[]`(기본값)는 요구 사항이 없다는 뜻으로 모듈은 이전처럼 동작합니다. 스토리지 없이 호출되며 매번 서비스의 구성을 읽을 수 있으므로, 요청마다 또는 주기마다 호출되지 않습니다. `fCheckRequirements`([backend/core/registry.py](../backend/core/registry.py))가 실행하며(예외는 충족되지 않은 것으로 간주) 그 결과가 보관됩니다. 수집기는 시작할 때와 다시 불러올 때(상태 `<name>.requirements`), 웹은 첫 설치 시, 모듈을 켤 때, 재구성 시(`WebContext.dRequirements`) 보관하며, 웹은 둘 중 최신 결과를 사용합니다. 웹에서 처음 설치할 때(이전 사본 없음) 모듈은 내려받은 저장소가 아니라 설치된 사본으로부터 만들어지며, 요구 사항이 충족되지 않고 관리자가 `modules.<name>.enabled`를 저장한 적이 없으면 거기에 `false`가 저장됩니다. 업데이트나 재설치는 이 값을 절대 바꾸지 않습니다. 요구 사항이 하나라도 충족되지 않는 동안에는 모듈을 켤 수 없습니다(422 `requirements_missing`, 잠긴 스위치). 재구성은 요구 사항을 다시 확인하고, 충족되면 스위치 잠금을 해제하고 root 명령을 보여 주지만 모듈을 켜지는 않습니다. 어떤 것도 모듈을 스스로 끄지 않습니다. 켜져 있는 모듈이 더 이상 요구 사항을 충족하지 않아도 켜진 상태로 유지되며, 진단과 상태 점검이 이를 보고합니다.

### 두 가지 대시보드

관리자는 항상 `/admin/dashboard/`에서 작업합니다(탭 `overview`, `search`, `live`, `alerts`, `modules`, `users`, `soc`, `channels`(섹션 `general/`(기본값)과 `telegram/`), `settings`, `audit`, `logins`, `account`. `modules`에는 `installed/`(기본값: 설치된 모듈, 한 행에 하나씩)와 `installable/`(저장소의 모듈 중 아직 설치되지 않은 것) 두 섹션이 있으며, 모듈 하나의 페이지는 `/admin/dashboard/modules/installed/<name>/`입니다). 분석가는 `/user/dashboard/`에서 작업합니다(`overview`, `search`, `live`, `alerts`, 읽기 전용이며 섹션이 없는 `modules`, `account`). 두 대시보드의 기본 탭은 `overview`이며, `/`와 로그인은 각 사용자를 자신의 대시보드 개요로 이동시킵니다. 다른 대시보드의 URL은 자신의 대시보드의 같은 탭으로 리디렉션됩니다(관리자가 `/user/dashboard/search/?q=...`를 요청하면 `/admin/dashboard/search/?q=...`로, 분석가가 `/admin/dashboard/users/`를 요청하면 `/user/dashboard/overview/`로 이동). 서버([backend/web/app.py](../backend/web/app.py))와 페이지의 라우터([frontend/assets/app.js](../frontend/assets/app.js)) 모두에서 그렇게 합니다. 사이드바에는 제목도 사용자 데이터도 없습니다. 로고, 구분선, 탭(그룹 사이에 구분선), 맨 아래에 구분선과 «로그아웃»이 있습니다. 소스, 진단, 규칙에는 더 이상 자체 탭이 없으며, 각 모듈 페이지의 일부입니다.

### 레코드, 이벤트, 그룹

- **레코드**는 읽은 그대로의 한 줄 또는 감사 항목 하나이며, 이미 마스킹되어 있습니다. 파일 위치와 함께 같은 트랜잭션에서 즉시 저장됩니다. 비정상 종료 후에는 둘 다 있거나 둘 다 없으므로 어떤 줄도 손실되거나 반복되지 않습니다.
- **이벤트**는 하나의 요청, 즉 모듈의 상관기가 결합한 레코드들입니다. Apache 모듈에서는 상관관계 기간(5초)이 지난 후 같은 `UNIQUE_ID`를 가진 레코드들이 결합됩니다. `UNIQUE_ID`가 없으면(Apache가 기본으로 기록하는 액세스 형식) 액세스 줄은 클라이언트 IP, 메서드, URI, 상태 코드, 시각(±2초)으로 해당 요청의 레코드와 짝지어지며, 이벤트는 약한 상관관계로 표시됩니다. 기간을 기다리는 레코드는 재시작 후에도 남습니다(`event_id IS NULL`).
- **그룹**은 하나의 SOC 알림입니다. 기간(10분) 안에서 모듈, vhost, IP, 범주, 심각도가 같은 탐지들입니다. 심각 그룹은 즉시 전송되고, 나머지는 한꺼번에 발생한 이벤트를 모으기 위해 60초 버퍼 동안 기다립니다.

### 스토리지

WAL 모드의 SQLite(`/opt/localsiem/db/localsiem.db`, 모드 600, `auto_vacuum = INCREMENTAL`)를 [backend/core/storage.py](../backend/core/storage.py)의 인터페이스 뒤에 두어, 향후 중앙 모드를 위해 PostgreSQL 구현을 추가할 수 있게 했습니다. 일반적인 필드에는 타입이 지정되고 인덱싱된 열이 있으며, 내용 없는 FTS5 테이블(`contentless_delete=1`)이 마스킹된 텍스트를 URL 디코딩된 형태로도 인덱싱하므로 `"union select"`로 `id=1%27%20UNION%20SELECT`도 찾을 수 있습니다. 감사 레코드는 축약된 텍스트(요청 줄, 호스트, 사용자 에이전트, 규칙 ID, 메시지와 데이터)만 인덱싱됩니다. 모든 쿼리는 매개변수를 사용합니다. 검색 트리는 `fCompileQuery`에서 자리 표시자가 있는 SQL로 컴파일되며, 사용자 텍스트를 이어 붙이는 일은 절대 없습니다. 개요와 모듈 페이지는 최근 24시간의 모듈별 카운트(`mModuleCounts`)와 알림 카운트(`mAlertCounts`)를 검색과 같은 시간 제한으로 읽습니다.

시각은 UTC로, 기본 저장 형식 `2026-10-29@13-59-59.723`(고정 너비, 텍스트로 정렬 가능)으로 저장되고, 표시 형식 `2026/10/29@13:59:59.723`으로 표시됩니다([backend/core/timeutil.py](../backend/core/timeutil.py)). Apache는 현지 시각을 기록하며, Apache 모듈이 이를 UTC로 변환합니다(access와 audit에는 오프셋이 있고, error.log는 서버의 시간대를 사용). 레코드로 기록되는 모든 것도 저장 형식을 사용합니다. 데이터베이스, 로그, 자격 증명 파일, 내보낸 CSV와 JSON 파일, SOC로 보내는 알림이 그렇습니다.

보존: 일수(90일)와 최대 크기(디스크의 15 %와 10 GB 중 작은 값) 기준. 가장 오래된 이벤트부터 짧은 배치로 삭제되며, 알림과 SOC 대기열은 더 오래(365일) 보관됩니다. 디스크 여유 공간이 적으면 용량이 큰 세부 정보(감사 헤더와 본문)를 더 이상 저장하지 않고, 거의 없으면 알림에 관련된 이벤트만 저장합니다. localSIEM은 디스크를 절대 가득 채우지 않습니다.

### 알아 둘 만한 설계 결정

- **localSIEM 설치 프로그램은 코어만 설치합니다.** GitHub에서 바로 실행되며(`curl -fsSL .../deploy/install-update-reinstall-debian.sh | bash -s -- ACTION options`), 완전한 사본 안에 있지 않으면(파이프로 실행되어 `BASH_SOURCE`가 `main`) `--ref`(또는 `--source-url`)의 브랜치 또는 태그 아카이브를 내려받습니다. 모든 것이 함수 안에 있고 `fMain`은 마지막 줄에서 실행되므로, 다운로드가 도중에 끊기면 아무것도 실행되지 않습니다. 어떤 명령도 stdin(스크립트 자체)을 읽지 않습니다. 명령에는 `< /dev/null`을 주고 질문은 `/dev/tty`에서 읽습니다. 없는 패키지를 설치하고(`dpkg-query` / `apk info -e`) 이미 설치된 모듈을 유지합니다. `--configure-*`(모듈에는 셋업 옵션이 없음)와 `--modules-from`은 거부합니다. 항상 정확히 하나의 동작이 필요합니다(`vAction`. 없으면 중지하고 동작 목록을 보여 줌). `--install`은 `fIsInstalled`가 localSIEM의 흔적(도중에 실패한 설치의 흔적 포함)을 하나라도 찾으면 중지하고, `--update`와 `--reinstall`은 하나도 찾지 못하면 중지합니다. `--update`는 모든 것(데이터, 계정, 설정, 모듈, `install.env`의 옵션)을 유지합니다. `--reinstall`은 먼저 확인을 요청하고(`fConfirmRemoval`), 새 사본을 내려받아 옵션을 확인한 다음에야 `--uninstall`처럼 모든 것을 삭제하고(`fRemoveInstallation`, 방금 내려받은 사본은 유지) 처음부터 설치합니다. 설치된 사본에서 실행하면 그 사본도 삭제되므로 localSIEM을 내려받습니다. 동작과 `--yes`는 `configure.py`에 전달되지 않습니다. `--uninstall`(단독 또는 `--yes`와 함께. `fUninstall`, 아무것도 내려받거나 설치하기 전에 실행)은 localSIEM이 서버에 둔 모든 것을 제거합니다. 서비스, `/opt/localsiem`, 사용자와 그룹, 읽기 경로의 ACL(`manage.py read-paths`와 `/var/log/apache2`), apache2 모듈 1.2.0 이하 버전에서 `--configure-apache`가 추가한 Apache의 `localsiem.conf`(`fRemoveApacheSetup`: configtest 후 reload. `localsiem_access.log*`는 남음: localSIEM은 로그를 절대 변경하거나 삭제하지 않음), logrotate, Let's Encrypt 훅, 자격 증명 파일의 localSIEM 블록입니다. `--yes`가 없으면 `/dev/tty`에서 확인을 묻습니다.
- **GitHub에서의 다운로드는 절대 캐시를 사용하지 않습니다.** `raw.githubusercontent.com`은 푸시 후 최대 5분 지난 파일을 제공하며(`Cache-Control: max-age=300`. 쿼리 문자열도 `Cache-Control: no-cache` 요청도 이를 우회하지 못함), 브랜치의 아카이브도 오래된 것일 수 있습니다. 그래서 문서화된 명령은 API(`api.github.com/repos/.../contents/...`, 캐시되지 않음)를 통해 설치 프로그램을 읽으며, 설치 프로그램(설치 프로그램의 `fResolveRef`)과 웹(모듈용, `catalog.py`의 `fResolveRef`) 모두 API에 브랜치의 커밋을 물어 절대 바뀌지 않는 그 커밋의 아카이브를 내려받습니다. 모든 다운로드는 `Cache-Control: no-cache`를 보냅니다. 토큰이 없으면 API는 IP 주소마다 시간당 60개의 요청을 허용하며, 응답이 없으면 브랜치의 아카이브를 내려받습니다(설치 프로그램은 경고를 표시).
- **채널은 사람을 위한 사본이지 두 번째 SOC가 아닙니다.** 수집기는 모든 알림을 SOC용 대기열에 넣고(영구 대기열. SOC가 없으면 전송 안 됨으로 보관) `ChannelSender`([backend/core/channels.py](../backend/core/channels.py))에도 넘깁니다. 이 클래스는 `channels.min_severity` 이상의 알림을 켜져 있고 설정된 각 채널로 보냅니다(Telegram: `sendMessage`, 일반 텍스트, `channels.language`). 목록은 메모리에 있으며(채널당 최대 200개 메시지), 1초에 메시지 하나씩 보내고, 429(`retry_after`)와 네트워크 오류 시 재시도합니다. 400, 401, 403, 404는 메시지를 즉시 버립니다. 재시작하면 대기 중이던 것은 사라지며, SOC는 여전히 모든 알림을 받습니다. 봇 토큰은 SOC 토큰과 같은 비밀 값입니다. `config/telegram-bot-token`(모드 600)에 있으며, 전체가 표시되거나 로그에 기록되지 않고, 토큰을 담은 URL도 절대 기록되지 않습니다.
- **SOC는 선택 사항입니다.** `fSocConfigured`([backend/core/soc.py](../backend/core/soc.py)): URL, 토큰, `soc_enabled`. 이것들이 없으면 `mProcessGroups`는 각 알림을 대기열에 넣는 대신 전송 안 됨으로 표시하고(`mSkipGroup`: 상태 `local`, 사유 `soc_not_configured`, «전송 안 됨»으로 표시), `SocSender.mCycle`은 대기 중이던 것에 같은 처리를 합니다(`mSkipPending`). 따라서 SOC는 구성된 이후의 알림만 받으며, 영영 없을지도 모르는 SOC를 위해 쌓이는 것은 없습니다. 채널은 SOC가 있든 없든 작동합니다.
- **모듈은 `localSIEM-modules` 저장소에서, 웹을 통해서만 제공됩니다**([backend/core/catalog.py](../backend/core/catalog.py)). 그 저장소에는 설치 프로그램이 없습니다. 웹은 모듈 › 설치 가능에서 저장소의 모듈 중 아직 설치되지 않은 것만 제공합니다. 모듈 › 설치됨에서는 저장소에 더 새로운 버전이 있는 설치된 모듈에 **업데이트**를 제공합니다(`fCatalog`: `newer`가 true이고 동작이 `update`. 동작이 `incompatible`이면 필요한 localSIEM에 대한 안내만 있고 버튼은 없음). 재설치나 다운그레이드 동작은 절대 제공하지 않습니다(모듈을 재설치하려면 제거한 후 설치). 업데이트는 설치와 같은 호출입니다(`POST /api/admin/module-catalog/{name}` → 설치된 사본 위에 `fInstall`). 설정과 켜짐/꺼짐 상태는 유지되며(`fFirstInstallation`은 이전 사본이 없었을 때만 실행됨), `access_changed`(`read_paths`가 교체된 사본의 것과 다름)는 root가 `setup-modules`를 다시 실행해야 하는지를 웹에 알려 줍니다. 브라우저는 `GET /api/admin/module-catalog`의 응답을 10분 동안 보관하며(`modules.js`의 `cCatalogSeconds`와 `fFetchCatalog`) 두 섹션이 이를 공유하므로, 설치됨을 열 때마다 저장소를 내려받지 않습니다. «저장소 확인»은 항상 다시 내려받으며, 모듈을 설치, 업데이트, 제거하면 응답을 잊습니다(`fForgetCatalog`). 아카이브는 `tarfile`의 `data` 필터로 풀며, `mod-<id>` 폴더만 모듈입니다(`fModuleFolders`. 접두사는 저장소의 폴더에만 붙으며, 설치된 폴더 `<id>/`, ID, 설정, URL, 옵션은 접두사 없는 이름을 사용하고, 접두사가 없는 폴더는 무시됨). 각 모듈은 코드를 가져오지 않고 `fReadManifest`로 확인되며, 설치된 사본 옆에서 이름 바꾸기로 설치됩니다. 웹은 `localsiem`으로 실행되며 로그 읽기 권한을 절대 부여하지 않습니다(root 권한이 필요함). 대신 root 명령을 보여 줍니다(`fRootCommand`: 같은 localSIEM의 `manage.py setup-modules`). 제거(`fRemove`)는 설치된 폴더를 이름 바꾸기로 옮긴 후 삭제하며, 모듈을 불러올 수 없을 때도 마찬가지입니다. 설정, 규칙 변경 사항, 이벤트, 알림, 읽기 위치는 남으며, root가 부여한 읽기 권한은 회수되지 않습니다. 설치, 업데이트, 제거 후 웹은 모듈을 다시 불러오고(`mReloadModules`) 수집기는 다시 시작합니다(IPC `restart`. systemd 또는 supervise-daemon이 다시 시작함). 모듈을 설치하기 전에 **요구 사항**은 이 서버의 시스템(`fServerSystem`: `/etc/alpine-release`, `/etc/debian_version`, 또는 `/etc/os-release`의 `ID`와 `ID_LIKE`)에 대한 모듈의 `install_requirements`를 그대로의 형태와 앞에 `sudo`를 붙인 형태로, 모듈의 참고 사항과 함께 보여 줍니다. 모듈이 그 시스템에 대해 아무것도 선언하지 않으면 모듈이 선언한 모든 시스템의 명령을 보여 줍니다. localSIEM은 이 명령을 절대 실행하지 않습니다.
- **로그 읽기 권한은 root로, 한 곳에서**: `manage.py setup-modules`(`fGrantReadAccess`: 설치된 모듈의 `read_paths`에 대해 다음 로테이션을 위한 기본 ACL이 포함된 ACL과 Debian의 `adm` 그룹)는 웹이 모듈 설치 후, `read_paths`를 바꾸는 업데이트 후(`access_changed`), 재구성 시 보여 주는 명령이며, 설치 프로그램이 업데이트할 때마다 실행하는 것입니다(`fGrantLogAccess`, `--no-restart` 사용).
- **localSIEM도 그 모듈도 서버의 구성을 절대 변경하지 않습니다**: 모듈에는 셋업 옵션이 없으며, root가 모듈을 위해 실행하는 것은 `manage.py setup-modules`뿐입니다(위 항목의 읽기 권한이며, 코어가 부여하고 모듈은 절대 부여하지 않음). 서버에서 모듈에 없는 것은 요구 사항과 진단에 그것을 해결하는 설정 조각이나 명령과 함께 표시되며(Apache의 경우: ModSecurity, CRS, `SecRuleEngine`, `mod_unique_id`), 관리자가 적용합니다.
- **Apache 관련 사항은 Apache 모듈에 있습니다**(`localSIEM-modules/mod-apache2/`). Apache 구성은 직접 파싱되며(그래서 탐색이 `apache2ctl` 없이 `localsiem`으로 작동함), ModSecurity 파트 K는 저장하기 전에 버려지고, 요청 카드에 표시되는 헤더와 본문은 마스킹된 원시 감사 레코드에서 재구성됩니다(`mDisplayRecord`). 코어는 각 레코드의 모듈에 묻기만 합니다(`WebContext.mModule`).
- **모듈은 재시작 없이 켜고 꺼집니다.** 웹은 `settings.json`을 쓰고 소켓으로 `reload`를 보냅니다. 수집기는 즉시 상태를 다시 게시하고, 웹은 저장한 것과 수집기가 적용한 것(`collector.status.modules`)을 비교하여 둘이 일치할 때까지 «pending»(웹에서는 «변경 사항 적용 중…»)을 표시합니다.
- **웹은 시작할 때 `module.json` 파일을 읽으며**, 모듈을 설치, 업데이트, 제거한 후에 다시 읽습니다(`mReloadModules`). 직접 복사하거나 제거한 모듈은 두 서비스를 모두 다시 시작해야 합니다(수집기가 모듈을 불러올 때까지 웹은 `not_loaded`로 표시).
- **모듈의 요구 사항은 중요한 시점에만 확인되며**(수집기 시작과 다시 불러오기, 첫 설치, 켜기, 재구성) 그 결과가 보관됩니다. 모듈이 요구 사항을 확인하기 위해 서비스의 구성을 읽을 수 있기 때문입니다. 웹은 내려받은 저장소의 코드를 절대 가져오지 않으며, 설치된 사본에서 확인합니다.
- **따라잡기**(한꺼번에 발생한 이벤트, 또는 중지된 동안 기록된 것): 소스가 읽기 할당량에서 멈추면 다음 주기가 즉시 시작됩니다. 같은 모듈에서 가장 느린 소스보다 5초(로그 시각 기준) 넘게 앞선 소스는 그 소스를 기다립니다. 그리고 뒤처진 모든 소스가 읽은 것보다 늦은 트랜잭션은 기다립니다(워터마크). 그래서 한 요청의 세 레코드는 항상 결합됩니다.
- **로그는 읽기만 합니다.** `FileTailer`는 모든 로그를 `O_RDONLY`로 엽니다. localSIEM의 어떤 것도 서비스의 로그에 쓰거나, 로테이션하거나, 잘라내거나, 이름을 바꾸거나, 옮기거나, 삭제하지 않습니다(localSIEM의 logrotate 파일은 `/opt/localsiem/log/`만 다룸). root가 localSIEM을 위해 로그에 하는 일은 읽기 권한 부여뿐입니다(`manage.py setup-modules`: `adm` 그룹과 ACL). 제거해도 apache2 모듈 1.2.0 이하 버전의 `localsiem.conf` 때문에 Apache가 기록한 `localsiem_access.log`는 남습니다.
- **로그의 기록 방식도 변경하지 않습니다.** 어떤 모듈도 서비스의 로깅 구성이나 로그 형식을 변경하지 않습니다(Apache의 경우: `LogFormat`, `CustomLog`, `GlobalLog`, `ErrorLog`, ModSecurity의 `SecAudit*` 지시자 모두 변경하지 않음). 모듈은 서버가 기록하는 그대로 로그를 읽고 그에 맞춥니다(어떤 `LogFormat`이든, `mod_remoteip`가 로그에 남기는 IP이든 아니든, 직렬 또는 동시, JSON 또는 네이티브 감사 로그든, 이미 `localsiem_combined` 줄을 기록하는 서버의 그 줄이든). 진단은 로그를 설명만 하며(형식, 감사 로그 파트, 마스킹, 로그에서 읽을 수 있는 것과 없는 것), 변경을 제안하지 않습니다. 로그가 아닌 요구 사항(Apache의 경우: ModSecurity, CRS, `SecRuleEngine`, `mod_unique_id`)과 읽기 권한에만 `fix`가 함께 제공됩니다.
- **모듈은 아무것도 설치하지 않으며 `/opt/localsiem/` 밖의 어떤 것도 변경하지 않습니다.** 시스템에 이미 있는 것으로 작동합니다. 패키지나 소프트웨어를 설치하지 않으며, `/opt/localsiem/` 밖에 서버의 파일, 구성, 로그를 쓰지 않습니다. 서버에 필요한 것이 없으면 요구 사항(`mRequirements`)이 이를 알리며, 요구 사항 없이 설치된 모듈은 요구 사항이 충족될 때까지 꺼진 상태(스위치 잠김)로 유지됩니다([코어와 모듈](#architecture)의 «요구 사항» 참조). 모듈에는 셋업 옵션이 없습니다. `read_paths`에 대한 읽기 권한은 모듈이 아니라 코어가 부여합니다(`manage.py setup-modules`, root로 실행). `install_requirements`의 명령은 관리자를 위한 것이며, 웹은 보여 주기만 합니다.
- **과거 기록에 대해서는 절대 알림을 발생시키지 않습니다.** 저장된 위치가 없는 소스는 끝에서 시작합니다(`Collector.mDiscover`). 단, 이 프로세스가 이미 그 모듈을 따라가고 있는 동안 나타난 소스(`sFollowedModules`: 새 vhost)는 5 MB 이하이면 처음부터 읽습니다. 따라서 첫 시작, 나중에 설치하거나 켠 모듈, root가 권한을 부여하기 전까지 읽을 수 없었던 파일, 재시작 어느 것도 오래된 줄을 읽지 않습니다. 각 파일의 위치는 열자마자 저장되며, 새로운 내용이 없을 때도 마찬가지이므로(`FileTailer.vOpenedUnsaved`) 재시작하면 그 위치부터 이어집니다. `--from-start`는 새 파일을 처음부터 읽습니다.
- **의존성은 가상 환경에**(`/opt/localsiem/venv/`) 두며, 절대 `pip --break-system-packages`를 사용하지 않습니다. pip가 클라이언트의 서비스가 사용하는 배포판 패키지(예: certbot)를 망가뜨리면 안 되기 때문입니다.
- **웹은 애플리케이션 자체가 허용 IP(와 루프백)로 제한합니다**(로그인 포함). 2단계 인증(TOTP, «PYMEHackers localSIEM»)은 기본적으로 꺼져 있습니다. 관리자가 설정(`mfa_enabled`)에서 모든 계정에 대해 켜며, 그때부터 필수가 됩니다. 설치 프로그램은 `--enable-mfa` 또는 `--disable-mfa`로만 이를 변경하므로(`install.env`에 없음), 업데이트해도 웹에서 선택한 값이 유지됩니다.
- **SOC의 SIEM 주소는 알림에 절대 담기지 않습니다.** `details`는 클라이언트의 모든 분석가가 볼 수 있으므로 쿼리(`details.localsiem.search`)만 보냅니다.
- **자신의 서버 로그만.** 원격 입력은 없습니다. 모든 모듈은 localSIEM이 실행되는 서버의 파일을 읽습니다. `configure.py`는 제거된 원격 입력의 옵션(`lRemovedOptions`: `--enable-http-input`, `--disable-http-input`, `--mode`)이 주어지면 «<option> no longer exists: localSIEM has no remote HTTP input, it only reads the logs of its own server.»라고 표시하고 중지하며, 실행할 때마다 이전 버전이 그 입력을 위해 보관한 것, 즉 `settings.json`의 `http_input`(`lRemovedSettings`, `fRemoveSettings`)과 `localsiem.env`의 변수 세 개(`lRemovedEnvironment`)를 제거합니다. 설치 프로그램은 `backend/`와 `frontend/`를 통째로 교체하므로, 업데이트하면 그 입력의 이전 파일도 제거됩니다. 이전 버전이 저장한 `http` 모듈의 이벤트는 보존 정책이 삭제할 때까지 데이터베이스에 남습니다.
- **15개 언어, 하나의 목록.** 웹, 모듈의 텍스트, 채널의 메시지, 문서는 de-DE, en-GB, en-US, es-AR, es-ES, fr-FR, he-IL, hi-IN, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, ru-RU, zh-CN으로 제공됩니다. [backend/core/config.py](../backend/core/config.py)의 `lLanguages`(계정, 모듈 텍스트, 채널에 허용되는 언어)와 `common.js`의 `cLanguages`(웹)는 알파벳순의 같은 목록입니다. en-US가 원본이자 대체 언어입니다. 어떤 언어에 없는 텍스트는 영어로 표시됩니다(`fT`, `fModuleText`, 채널의 `dTexts`). he-IL은 오른쪽에서 왼쪽으로 씁니다(`lRightToLeftLanguages`, `cRightToLeft`). `fLoadLanguage`가 페이지에 `dir="rtl"`을 설정하고, 스타일은 논리적 방향(`inline-start`, `inline-end`, `text-align: start`)만 사용하므로 레이아웃이 저절로 반전되며, `localsiem.css` 끝의 «Right to left» 블록이 나머지(`unicode-bidi: plaintext`가 적용된 기술 텍스트, 선택 상자의 화살표, 스위치의 손잡이, 좁은 화면의 메뉴)를 처리합니다. 히스토그램은 왼쪽에서 오른쪽으로 유지됩니다. 표시 형식의 시간은 왼쪽에서 오른쪽으로 분리됩니다(`fEl`의 `fTextNodes`: `<bdi dir="ltr">`). 언어를 바꾸면 열려 있는 화면을 다시 그립니다(`app.js`의 `fOnLanguage` → `fRoute`).

<a id="modules"></a>
## 2. 모듈 맵

| 모듈 | 경로 | 책임 | 의존 대상 | 사용처 |
|---|---|---|---|---|
| 수집기 | [backend/collector.py](../backend/collector.py) | 메인 루프: 모듈 불러오기, 소스, 레코드, 상관 분석, 이벤트, 규칙, 그룹, 보존, 상태 점검, 웹용 상태(모듈별 포함), 로컬 소켓 | core, registry | `localsiem` 서비스 |
| 웹 서버 | [backend/server.py](../backend/server.py) | `-h`/`--help` 외에는 옵션 없음(`fCheckArguments`: 다른 옵션은 모두 오류), 포트 해제, HTTPS를 사용하는 uvicorn | web | `localsiem-web` 서비스 |
| 관리 CLI | [backend/manage.py](../backend/manage.py) | 계정, 활성화된 모든 모듈의 진단(꺼진 모듈의 요구 사항 포함), 충족되지 않은 요구 사항이 함께 표시되는 모듈 목록, 모듈이 읽는 폴더, SOC 테스트. root로 `setup-modules`(모듈 로그의 읽기 권한 부여와 재시작: 웹이 보여 주는 명령이며 설치 프로그램도 실행함) | web.auth, registry | 설치 프로그램, root |
| 터미널 출력 | [backend/core/terminal.py](../backend/core/terminal.py) | 설치 프로그램과 같은 `manage.py`와 `configure.py`의 스타일: 표시가 붙은 결과 줄(`✓` 완료, `!` 경고, `✗` 실패, `·` 정보. UTF-8을 쓸 수 없는 곳에서는 `+ ! x -`), 흐리게 표시되는 세부 정보, 터미널에서만 색 사용(`LOCALSIEM_COLOR=always` 또는 `never`가 먼저 결정하고, 그다음 `NO_COLOR`, `TERM=dumb`, `isatty`) | — | manage, configure |
| 비밀번호 | [backend/security.py](../backend/security.py) | PBKDF2-SHA256(600 000회 반복) | — | web.auth, configure |
| 구성 | [backend/core/config.py](../backend/core/config.py) | 경로(`cModulesPath` 포함), 버전, 기본값, `settings.json`(`fSaveSettings`, `fRemoveSettings`), SOC 토큰, Telegram 봇 토큰, 비밀 값 | — | 전체 |
| 시각 | [backend/core/timeutil.py](../backend/core/timeutil.py) | 기본 형식, Apache 시각의 UTC 변환 | — | 전체 |
| 스토리지 인터페이스 | [backend/core/storage.py](../backend/core/storage.py) | 모든 스토리지가 구현하는 메서드 | — | storage_sqlite |
| SQLite 스토리지 | [backend/core/storage_sqlite.py](../backend/core/storage_sqlite.py) | 스키마, 레코드, 이벤트, 그룹, 대기열, 상태, 보존, 검색, 쿼리 컴파일러, 모듈별 카운트와 알림 카운트 | query | collector, web, modules |
| 검색 언어 | [backend/core/query.py](../backend/core/query.py) | 토크나이저와 트리로 변환하는 파서, 위치가 포함된 오류 | — | storage_sqlite, web |
| 파일 리더 | [backend/core/tailer.py](../backend/core/tailer.py) | 위치, 로테이션(create와 copytruncate), 잘림, 삭제, 교체, 적체 | — | collector |
| 모듈 레지스트리 | [backend/core/registry.py](../backend/core/registry.py) | 설치된 모듈 폴더(`cModulesPath`)를 찾고, `module.json`을 확인하고, 클래스를 불러오고(네임스페이스 패키지 `localsiem_modules`), 인스턴스를 만들고, 요구 사항을 확인하고(`fCheckRequirements`), 설정 기본값과 검증을 처리 | config, module, timeutil | collector, web, manage, catalog |
| 모듈 인터페이스 | [backend/core/module.py](../backend/core/module.py) | 기본 클래스 `Module`(훅, 요구 사항, `module.json` 위에 적용되는 설정, 켜기/끄기)과 줄 프레이머 | registry | 모든 모듈 |
| 규칙 엔진 | [backend/core/rules.py](../backend/core/rules.py) | YAML 규칙: 일치, 임계값, 시퀀스. 웹을 위한 모듈 규칙 폴더 설명 | PyYAML | collector, api_modules |
| 그룹화 | [backend/core/grouping.py](../backend/core/grouping.py) | 그룹, 기간, 버퍼, `external_id` | storage | collector |
| SOC 전송 | [backend/core/soc.py](../backend/core/soc.py) | 알림 형식, 클라이언트, 전송 스레드, 하트비트, 오류 처리 | storage, config | collector, web, manage |
| 채널 | [backend/core/channels.py](../backend/core/channels.py) | SOC 외에 관리자에게 보내는 메시지: 설정(`fChannelSettings`), 15개 언어의 텍스트(`lLanguages`. 없으면 영어: `fBuildMessage`, `fTestMessage`), Telegram 클라이언트(`TelegramClient`), 전송 스레드(`ChannelSender`)와 그 상태 `channels.status` | config, masking, timeutil | collector, web |
| 상태 점검 | [backend/core/health.py](../backend/core/health.py) | 안티 포렌식 알림, 파싱되지 않은 줄, 조용한 소스, 디스크 | storage | collector |
| 마스킹 | [backend/core/masking.py](../backend/core/masking.py) | 민감한 매개변수, JSON 키, 헤더, ModSecurity 데이터 | — | modules |
| 로컬 소켓 | [backend/core/ipc.py](../backend/core/ipc.py) | Unix 소켓(개발용으로는 추상 소켓) 위의 JSON: 웹이 수집기에 보내는 명령 | — | collector, web |
| 모듈 카탈로그 | [backend/core/catalog.py](../backend/core/catalog.py) | `localSIEM-modules` 저장소의 아카이브(설정 `modules_repository`): 다운로드, 안전한 압축 해제, 설치된 것과 비교한 `mod-<id>` 폴더(`action`, `newer`), `<id>/`로의 원자적 설치 또는 업데이트(`previous`, `access_changed`)와 제거(한 번에 하나씩), root 명령(`manage.py setup-modules`) | config, registry | web(`api_modules`) |
| 설치된 모듈 | `/opt/localsiem/modules/<name>/`, 웹이 `localSIEM-modules` 저장소에서 설치(현재 `apache2`와 `privesc`, 저장소의 폴더는 `mod-apache2/`와 `mod-privesc/`) | Apache: 탐색, 파싱, 상관 분석, 수행된 조치, 심각도, 규칙, 보강, 진단, 요구 사항(Apache와 ModSecurity 2), 상태 점검, 요청 카드. privesc: 권한 상승. 그 프로젝트에 문서화됨 | core | collector, web, manage |
| 웹 애플리케이션 | [backend/web/app.py](../backend/web/app.py) | 두 대시보드의 페이지와 리디렉션(사용자와 모듈의 섹션, 모듈 페이지의 이전 URL), 인증, 계정, 보호(허용 IP, 보안 헤더) | context, api_* | server |
| 웹 컨텍스트 | [backend/web/context.py](../backend/web/context.py) | 설정, 계정, 이벤트 데이터베이스(읽기 전용), 핑거프린트가 붙은 `index.html`, 수집기 소켓, 모듈의 매니페스트, 웹 훅용 인스턴스와 웹이 확인한 요구 사항(`dRequirements`) | auth, webdb, registry | web |
| 계정과 세션 | [backend/web/auth.py](../backend/web/auth.py), [webdb.py](../backend/web/webdb.py), [totp.py](../backend/web/totp.py) | 사용자, 세션(방식 포함: 비밀번호 또는 토큰), 잠금, CSRF, TOTP, 허용 IP, 직접 로그인용 액세스 토큰, 로그인 기록, 검색 감사 | security | web, manage, configure |
| 검색 API | [backend/web/api_search.py](../backend/web/api_search.py) | 검색, 히스토그램, 요약, 내보내기, 요청 카드(각 모듈이 필드 추가), 알림, 실시간 WebSocket | storage, query | web |
| 모듈 및 개요 API | [backend/web/api_modules.py](../backend/web/api_modules.py) | 모든 모듈의 상태와 그 이유(충족되지 않은 요구 사항 포함), 모듈 하나의 세부 정보(설정, 요구 사항, 소스, 진단, 규칙)와 그 저장(요구 사항이 충족된 경우에만 켜짐), 재구성, 저장소에서의 설치 또는 업데이트(같은 호출. 요구 사항이 없으면 첫 설치에서만 꺼짐, `access_changed`)와 제거, 대시보드 개요 | registry, catalog, rules, storage, config | web |
| 관리 API | [backend/web/api_admin.py](../backend/web/api_admin.py) | 사용자, SOC, 채널, 설정, 감사 | storage, soc, channels, config | web |
| 프런트엔드 | [frontend/](../frontend/) | 하나의 HTML 셸, `common.js`, `app.js`(두 대시보드와 사용자, 채널, 모듈 섹션의 라우터, 로그인), `overview.js`, `search.js`(검색, 실시간 보기, 알림, 계정), `modules.js`(관리자의 설치됨과 설치 가능 섹션: 설치된 모듈마다 한 행, 저장소에 더 새로운 버전이 있으면 업데이트, 아직 설치되지 않은 저장소의 모듈과 10분 동안 보관되는 저장소 응답. 요구 사항과 재구성이 포함된 모듈 하나의 페이지), `admin.js`(계정과 액세스 토큰이 있는 사용자, SOC, 일반과 Telegram이 있는 채널, 설정, 감사, 로그인 기록), SOC의 스타일시트와 `localsiem.css`, 15개 언어(he-IL은 오른쪽에서 왼쪽) | — | 브라우저 |
| 배포 | [deploy/](../deploy/) | GitHub 또는 사본에서 실행하는 코어 전용 설치 프로그램(동작 하나: 설치, 업데이트, 처음부터 재설치 또는 제거. 없는 패키지, 다운로드, `manage.py setup-modules --no-restart`를 통한 이미 설치된 모듈의 `read_paths` 읽기 권한), `configure.py`(설정, 인증서, 자격 증명, `modules_repository`), systemd 유닛, OpenRC 스크립트, certbot 훅, logrotate | manage, registry | root |

<a id="symbols"></a>
## 3. 주요 심볼

| 심볼 | 파일:줄 | 하는 일 |
|---|---|---|
| `Collector` | [backend/collector.py:58](../backend/collector.py#L58) | 수집기: 초기 설정, 메인 루프, 모든 주기적 작업 |
| `Collector.mSetup` | [backend/collector.py:104](../backend/collector.py#L104) | 모듈을 불러오고(`fCreateModules`), 각 모듈의 `mStart`와 상관기, «Modules: ...» 로그 기록, 요구 사항, 규칙, 탐색, 대기 중인 레코드 |
| `Collector.mCheckRequirements` | [backend/collector.py:134](../backend/collector.py#L134) | 시작하고 다시 불러올 때 모든 모듈의 요구 사항(`fCheckRequirements`): 웹을 위한 상태 `<name>.requirements`. 충족되지 않은 것을 로그에 기록. 모듈을 켜거나 끄지 않음 |
| `Collector.mDiscover` | [backend/collector.py:163](../backend/collector.py#L163) | 활성화된 모듈의 소스. 새 소스를 열고(모듈을 이미 따라가고 있지 않으면 끝에서 시작: `sFollowedModules`) 사라진 소스를 닫음 |
| `Collector.mReloadSettings` | [backend/collector.py:211](../backend/collector.py#L211) | 새 설정: 모듈, 요구 사항, 그룹화, 규칙, 탐색, 진단과 상태를 즉시 게시 |
| `Collector.mDiscoveryInterval` | [backend/collector.py:316](../backend/collector.py#L316) | 활성화된 모듈 중 가장 짧은 탐색 간격(최소 60초) |
| `Collector.mReadSources` | [backend/collector.py:327](../backend/collector.py#L327) | 모든 소스를 폴링하고(따라잡는 동안 균형 조정), 프레이밍, 파싱, 레코드와 위치 저장 |
| `Collector.mWatermark` | [backend/collector.py:416](../backend/collector.py#L416) | 모듈의 뒤처진 소스가 읽은 가장 이른 로그 시각 |
| `Collector.mProcessDue` | [backend/collector.py:424](../backend/collector.py#L424) | 기한이 된 트랜잭션의 이벤트를 만들고, 규칙을 실행하고, 저장하고, 탐지 |
| `Collector.mProcessGroups` | [backend/collector.py:485](../backend/collector.py#L485) | 버퍼 시간이 지난 그룹: 보강, 알림, SOC 대기열 |
| `Collector.mRetention` | [backend/collector.py:534](../backend/collector.py#L534) | 일수와 크기 기준 삭제, 증분 vacuum |
| `Collector.mPublishState` | [backend/collector.py:569](../backend/collector.py#L569) | `collector.status`: 소스, 디스크, 데이터베이스, 규칙, 건너뛴 로그, 모듈별 상태(`enabled`, `version`, `sources`, `pending`)와 `module_errors` |
| `Collector.mPublishDoctor` | [backend/collector.py:612](../backend/collector.py#L612) | 각 모듈의 `<name>.doctor`(비활성화된 모듈은 비어 있음) |
| `Collector.mHandleIpc` | [backend/collector.py:624](../backend/collector.py#L624) | 웹의 명령: reload(재구성에서도), doctor, restart(웹에서 모듈을 설치, 업데이트, 제거했을 때), SOC 재시도와 거부된 알림의 재대기열 추가. heartbeat와 status도 처리 |
| `fListManifests` | [backend/core/registry.py:165](../backend/core/registry.py#L165) | `module.json`이 있는 설치된 모듈 폴더(`cModulesPath`에서, 이름순). 오류는 별도 |
| `fReadManifest` | [backend/core/registry.py:133](../backend/core/registry.py#L133) | `module.json`을 확인하고(id: 폴더 이름, 또는 `mod-<id>` 폴더에 대해 카탈로그가 주는 id. entry, settings, `core`), 기본값을 채우고 로캘을 읽음 |
| `fCheckInstallRequirements` | [backend/core/registry.py:97](../backend/core/registry.py#L97) | `module.json`의 `install_requirements`를 확인(`fReadManifest`가 호출): `lSystems`의 시스템(`debian`, `alpine`), 한 줄짜리 명령 1~20개, 셸 연산자 없음(`cShellOperatorRegex`). 웹이 각 명령 앞에 `sudo`를 붙이기 때문 |
| `fLoadClass` | [backend/core/registry.py:197](../backend/core/registry.py#L197) | `fRegisterPackage` 후 `localsiem_modules.<name>.<file>`을 가져오고 클래스를 확인 |
| `fCreateModules` | [backend/core/registry.py:229](../backend/core/registry.py#L229) | `({name: module}, manifests, errors)`. 실패한 모듈이 다른 모듈을 멈추게 하는 일은 없음 |
| `fCheckRequirements` | [backend/core/registry.py:214](../backend/core/registry.py#L214) | 모듈의 `mRequirements()`를 `{time, checks, met}`로 반환(met: 오류인 검사가 없음. 예외는 충족되지 않은 것으로 간주) |
| `fModuleSettings` | [backend/core/registry.py:250](../backend/core/registry.py#L250) | `settings.json` `modules.<name>` 아래에 깔리는 `module.json`의 기본값 |
| `fValidateSettings` | [backend/core/registry.py:317](../backend/core/registry.py#L317) | 관리자가 저장하는 값을 `module.json`에 대해 확인. `ValueError("invalid_setting:<key>")` |
| `Module` | [backend/core/module.py:59](../backend/core/module.py#L59) | 모듈의 인터페이스: `mModuleSettings`, `mEnabled`, `mStart`, `mDiscoveryInterval`, `mDiscover`, `mParse`, `mBuildEvent`, `mDoctor`, `mRequirements`, `mSkipped`, `mSetLowDisk`, `mDisplayRecord`... |
| `FileTailer` | [backend/core/tailer.py:37](../backend/core/tailer.py#L37) | 읽기 전용으로 연, 따라가는 파일 하나: 위치(첫 위치가 저장될 때까지 `vOpenedUnsaved`), 로테이션, 잘림, 삭제. `vWasReadable`(이번 실행에서 열었거나 이전 실행이 저장한 위치가 있음): `unreadable` 통지가 이를 `was_readable`로 전달 |
| `FileTailer.mPoll` | [backend/core/tailer.py:250](../backend/core/tailer.py#L250) | 새로운 완전한 줄을 오프셋과 함께 읽고, 통지도 읽음 |
| `SqliteStorage` | [backend/core/storage_sqlite.py:303](../backend/core/storage_sqlite.py#L303) | SQLite 스토리지 |
| `SqliteStorage.mSaveRecords` | [backend/core/storage_sqlite.py:392](../backend/core/storage_sqlite.py#L392) | 레코드, 전체 텍스트 인덱스, 위치를 하나의 트랜잭션에서 저장 |
| `fCompileQuery` | [backend/core/storage_sqlite.py:281](../backend/core/storage_sqlite.py#L281) | 검색 트리를 매개변수가 있는 SQL로 변환 |
| `SqliteStorage.mSearch` | [backend/core/storage_sqlite.py:878](../backend/core/storage_sqlite.py#L878) | 시간 기반 페이지 매김과 시간 제한이 있는 검색 |
| `SqliteStorage.mGetIpContext` | [backend/core/storage_sqlite.py:504](../backend/core/storage_sqlite.py#L504) | IP의 차단된 요청과 전체 요청, 처음 관측된 시각 |
| `SqliteStorage.mCountRecentEvents` | [backend/core/storage_sqlite.py:539](../backend/core/storage_sqlite.py#L539) | 특정 시각 이후 한 모듈의 이벤트와 가장 활발한 IP(모듈의 상태 점검) |
| `SqliteStorage.mModuleCounts` | [backend/core/storage_sqlite.py:708](../backend/core/storage_sqlite.py#L708) | 모듈별 이벤트, 차단, 알림 발생 수와 최종 시각 |
| `SqliteStorage.mAlertCounts` | [backend/core/storage_sqlite.py:720](../backend/core/storage_sqlite.py#L720) | 특정 시각 이후 생성된 알림(상태별, 심각도별) |
| `SqliteStorage.mGetEventDetail` | [backend/core/storage_sqlite.py:949](../backend/core/storage_sqlite.py#L949) | 레코드(각각 `module` 포함), 규칙 적중, 알림이 포함된 이벤트 하나 |
| `SqliteStorage.mGroupEvents` | [backend/core/storage_sqlite.py:1011](../backend/core/storage_sqlite.py#L1011) | 알림의 요청(`event_alerts`): 최대 50개(`api_search.py`의 `cAlertEvents`), 가장 오래된 것부터, 검색의 열과 함께, 그리고 전체 개수. `GET /api/alerts/{id}`가 이를 `events`와 `events_total`로 반환 |
| `fAlertRequests` / `fBindRows` | [frontend/assets/search.js:687](../frontend/assets/search.js#L687) / [:259](../frontend/assets/search.js#L259) | 열린 알림 행(알림 탭)에 표시되는 알림의 요청으로, 검색의 행(`fResultRow`)을 사용. 클릭하면 요청 카드가 열림(`fToggleRow` → `fRequestCard`). `fBindRows`는 자기 표의 카드 안에서 일어난 클릭만 무시하므로 알림의 열린 행 안에서도 작동함. 알림 하나가 열려 있는 동안에는 알림 목록이 새로 고쳐지지 않음 |
| `fParseQuery` | [backend/core/query.py:232](../backend/core/query.py#L232) | 쿼리 텍스트를 트리로 변환. 코드와 위치가 포함된 `QueryError` |
| `RulesEngine` / `Rule` | [backend/core/rules.py:319](../backend/core/rules.py#L319) / [:93](../backend/core/rules.py#L93) | YAML 규칙을 불러오고 평가 |
| `fDescribeFolder` | [backend/core/rules.py:54](../backend/core/rules.py#L54) | 모듈 폴더의 규칙을 파일이 정의한 그대로, 비활성화된 규칙 포함(모듈 페이지) |
| `Grouper` | [backend/core/grouping.py:38](../backend/core/grouping.py#L38) | 탐지를 그룹으로(기간, 버퍼) |
| `fExternalId` | [backend/core/grouping.py:31](../backend/core/grouping.py#L31) | 결정적 `external_id` |
| `fBuildAlert` | [backend/core/soc.py:67](../backend/core/soc.py#L67) | 그룹을 `GenericAlert`로(시각은 저장 형식) |
| `SocSender.mDeliver` | [backend/core/soc.py:256](../backend/core/soc.py#L256) | 배치를 보냄. 413/422에서는 분할. 401, 507, 네트워크 오류 처리 |
| `fSocConfigured` / `SqliteStorage.mSkipPending` | [backend/core/soc.py:43](../backend/core/soc.py#L43) / [backend/core/storage_sqlite.py:630](../backend/core/storage_sqlite.py#L630) | 보낼 SOC가 있는지(URL, 토큰, `soc_enabled`). 없으면 대기 중이던 것은 `local`(전송 안 됨)이 됨 |
| `ChannelSender.mNotify` / `ChannelSender.mDeliver` | [backend/core/channels.py:330](../backend/core/channels.py#L330) / [:414](../backend/core/channels.py#L414) | 수집기는 SOC용 대기열에 넣는 모든 알림을 여기에 넘김: `min_severity` 이상의 알림은 켜져 있고 설정된 각 채널의 목록으로 감(최대 200개, 가장 오래된 것은 버림). 1초에 메시지 하나. 오류 시 재시도(`retry_after`, 점점 늘어나는 대기) 또는 버림(400, 401, 403, 404 또는 5회 시도) |
| `TelegramClient.mCall` / `fBuildMessage` | [backend/core/channels.py:273](../backend/core/channels.py#L273) / [:226](../backend/core/channels.py#L226) | `https://api.telegram.org/bot<token>/<method>`로 POST. 실패는 토큰을 절대 담지 않는 `TelegramError`(상태, 설명, `retry_after`). 메시지: 심각도, 규칙, 설명, 모듈, 이벤트, 최초 및 최종 시각(표시 형식), 검색이며 채널의 언어로 작성 |
| `HealthMonitor` | [backend/core/health.py:110](../backend/core/health.py#L110) | 파싱되지 않은 줄, 조용한 소스, 디스크 수준 |
| `fNoticeDetection` | [backend/core/health.py:58](../backend/core/health.py#L58) | 소스 통지(truncated, missing, replaced, unreadable, rotated_lost)의 알림. `unreadable`은 `was_readable`일 때만: 한 번도 읽지 못한 로그(`setup-modules` 실행 전의 방금 설치한 모듈)는 소스 상태로만 표시되며, 수집기는 알림 없이 로그에 기록함(`Collector.mHandleNotice`) |
| `Masker` | [backend/core/masking.py:17](../backend/core/masking.py#L17) | 매개변수, JSON, 헤더, ModSecurity 데이터를 마스킹 |
| `fCreateApp` | [backend/web/app.py:114](../backend/web/app.py#L114) | FastAPI 애플리케이션과 그 페이지, 보호 장치를 구성 |
| `fUserTab` / `fAdminTab` | [backend/web/app.py:196](../backend/web/app.py#L196) / [:211](../backend/web/app.py#L211) | 각 대시보드의 탭과 역할에 맞는 대시보드로의 리디렉션. `users`와 `modules`는 첫 번째 섹션(`users/accounts/`, `modules/installed/`)으로 이동 |
| `fAdminUsersSection` | [backend/web/app.py:232](../backend/web/app.py#L232) | 사용자의 섹션: `accounts`(기본값)와 `tokens` |
| `fAdminModulesSection` | [backend/web/app.py:264](../backend/web/app.py#L264) | 모듈의 섹션(`lModuleSections`): `installed`(기본값)와 `installable`. 세션을 먼저 확인하며(없으면 로그인), 분석가는 `/user/dashboard/modules/`로 이동. 모듈의 이전 URL `/admin/dashboard/modules/<name>/`은 모듈이 설치되어 있으면 `installed/<name>/`으로 301, 아니면 404로 응답 |
| `fAdminChannelsSection` | [backend/web/app.py:246](../backend/web/app.py#L246) | `/admin/dashboard/channels/general/`과 `telegram/`(관리자 전용. 다른 섹션: 404) |
| `fLoginWithToken` | [backend/web/app.py:387](../backend/web/app.py#L387) | `/auth/login/auto?token=...`(또는 `?TOKEN`): 직접 로그인, 잠금, 기록, 이 사이트에 한정된 `next` |
| `fCreateToken` / `fLogins` | [backend/web/api_admin.py:421](../backend/web/api_admin.py#L421) / [:446](../backend/web/api_admin.py#L446) | 액세스 토큰 생성(응답에 한 번만 담김). 로그인 기록 목록(결과로 필터링, `alert_retention_days` 후 삭제) |
| `fAdminModule` | [backend/web/app.py:283](../backend/web/app.py#L283) | 모듈 하나의 페이지 `/admin/dashboard/modules/installed/<name>/`(관리자용. 분석가는 `/user/dashboard/modules/`로 이동. 설치되지 않은 모듈은 404) |
| `WebContext.mReloadModules` | [backend/web/context.py:51](../backend/web/context.py#L51) | 웹에서 설치, 업데이트, 제거한 후: `module.json` 파일을 다시 읽고, 그 모듈의 코드를 새로 가져오고, 웹이 확인한 그 모듈의 요구 사항을 잊음 |
| `WebContext.mModule` | [backend/web/context.py:91](../backend/web/context.py#L91) | 웹 훅(`mDisplayRecord`)용 모듈 인스턴스 |
| `WebContext.mCheckRequirements` | [backend/web/context.py:105](../backend/web/context.py#L105) | 새 인스턴스에서 확인한 설치된 모듈의 요구 사항(저장된 설정 또는 저장하려는 설정 사용). 저장된 설정으로 확인한 결과는 `dRequirements`에 보관 |
| `fSummary` | [backend/web/api_modules.py:104](../backend/web/api_modules.py#L104) | 모듈 하나의 상태(`ok`, `warning`, `error`, `pending`, `disabled`, `unknown`)와 그 이유(꺼져 있고 요구 사항이 충족되지 않은 동안에는 `requirements_missing`), `has_requirements`와 `requirements_missing` |
| `fRequirements` / `fMissing` | [backend/web/api_modules.py:88](../backend/web/api_modules.py#L88) / [:99](../backend/web/api_modules.py#L99) | 모듈의 가장 최근 요구 사항 검사(수집기 또는 웹의 것). 충족되지 않은 검사 |
| `fRules` / `fCleanRules` | [backend/web/api_modules.py:196](../backend/web/api_modules.py#L196) / [:208](../backend/web/api_modules.py#L208) | 재정의가 적용된 모듈의 규칙. 저장 전에 재정의를 확인 |
| `fRegisterModules` | [backend/web/api_modules.py:237](../backend/web/api_modules.py#L237) | `/api/modules`, `/api/admin/modules/{name}`(`/doctor`와 `/reconfigure` 포함. `DELETE`는 제거), `/api/admin/module-catalog`, `/api/overview` |
| `fReconfigure` / `fFirstInstallation` | [backend/web/api_modules.py:338](../backend/web/api_modules.py#L338) / [:369](../backend/web/api_modules.py#L369) | 재구성: 요구 사항 재확인, 수집기 `reload`, 충족되면 root 명령(모듈을 켜지는 않음). 첫 설치: 요구 사항이 충족되지 않고 `modules.<name>.enabled`가 저장된 적이 없으면 꺼짐 |
| `fOverview` | [backend/web/api_modules.py:439](../backend/web/api_modules.py#L439) | 개요 데이터: 24시간 카운트, 시간별 히스토그램, 모듈, SOC, 수집기, 디스크, 최근 알림 |
| `Accounts` | [backend/web/auth.py:128](../backend/web/auth.py#L128) | 사용자, 로그인, TOTP, 세션, 잠금, 액세스 토큰, 로그인 기록, 검색 감사 |
| `Accounts.mCreateSession` / `mLoadSession` | [backend/web/auth.py:323](../backend/web/auth.py#L323) / [:340](../backend/web/auth.py#L340) | 방식(`password` 또는 `token`)이 포함된 세션. 토큰 세션은 2차 인증도 비밀번호 변경도 요구하지 않으며 분석가만 유지할 수 있음. `mfa_enabled`가 켜져 있으면 2차 인증이 없는 계정의 비밀번호 세션은 유효하지 않음 |
| `fSaveSettingsRoute` | [backend/web/api_admin.py:358](../backend/web/api_admin.py#L358) | 관리자 패널의 설정, `mfa_enabled` 포함(켜면서 저장한 관리자의 세션이 종료되었으면 `session_closed`) |
| `fChannels` / `fSaveChannels` / `fSaveTelegram` / `fTestTelegram` | [backend/web/api_admin.py:230](../backend/web/api_admin.py#L230) / [:252](../backend/web/api_admin.py#L252) / [:275](../backend/web/api_admin.py#L275) / [:309](../backend/web/api_admin.py#L309) | 채널의 설정과 상태(마스킹된 토큰, `bot_id`). 일반 설정(`enabled`, `min_severity`, `language`). Telegram(토큰은 `config/telegram-bot-token`에, `chat_id`, `enabled`는 둘 다 있을 때만: `telegram_incomplete`. `remove_token`). 저장된 값으로 테스트 메시지 전송(`getMe` + `sendMessage`) |
| `Accounts.mCreateAccessToken` / `mCheckAccessToken` | [backend/web/auth.py:371](../backend/web/auth.py#L371) / [:412](../backend/web/auth.py#L412) | 활성 분석가용 토큰(1~365일, SHA-256만 보관, 한 번만 표시). 사용자, 또는 세션을 열지 않는 이유 |
| `Accounts.mRecordLogin` | [backend/web/auth.py:440](../backend/web/auth.py#L440) | `logins`의 한 행: 계정, 방식(`password`, `password_totp`, `token`), 결과, 사유, IP, 브라우저 |
| `fEvent` | [backend/web/api_search.py:173](../backend/web/api_search.py#L173) | 요청 카드: 이벤트와 그 레코드, 각 모듈이 추가하는 필드 포함 |
| `fLive` | [backend/web/api_search.py:225](../backend/web/api_search.py#L225) | 실시간 WebSocket: 로그인된 세션 쿠키로만 열림(그렇지 않으면 4401로 닫힘) |
| `fDownload` / `fCatalog` | [backend/core/catalog.py:121](../backend/core/catalog.py#L121) / [:171](../backend/core/catalog.py#L171) | 안전하게 압축을 푼 저장소 아카이브. 그 모듈들(`mod-<id>` 폴더: `fModuleFolders`)과 동작(install, update, reinstall, downgrade, incompatible, invalid), `newer`(설치되어 있고 저장소에 더 새로운 버전이 있음. 이 localSIEM이 설치할 수 없는 버전도 포함). 설치 가능은 설치되지 않은 것만 나열하며(`installed`가 null: install, incompatible 또는 invalid), 설치됨은 `newer`를 사용(동작이 update이면 업데이트, incompatible이면 필요한 localSIEM만 표시). 각 항목에는 `module.json`의 `install_requirements`도 있음(요구 사항 대화 상자) |
| `fInstall` / `InstallLock` | [backend/core/catalog.py:235](../backend/core/catalog.py#L235) / [:213](../backend/core/catalog.py#L213) | `mod-<name>` 폴더를 설치된 `<name>` 옆에 복사하고 이름 바꾸기로 교체(설치와 업데이트). `previous`(교체된 버전, 첫 설치에서는 `None`)와 `access_changed`(`read_paths`가 교체된 사본의 것과 다름. 첫 설치에서는 항상 true)가 포함된 매니페스트를 반환. 설치, 업데이트, 제거는 한 번에 하나씩 |
| `fRemove` / `fUninstallModule` | [backend/core/catalog.py:302](../backend/core/catalog.py#L302) / [backend/web/api_modules.py:422](../backend/web/api_modules.py#L422) | 설치된 모듈을 제거하며, 불러올 수 없는 모듈도 마찬가지: 폴더를 스테이징 폴더로 이름 바꾸기 후 삭제. `DELETE /api/admin/modules/{name}`(폴더가 없으면 404 `module_not_installed`. 그다음 `mReloadModules`, 수집기 재시작) |
| `fFetchCatalog` / `fFetchAndInstall` / `fRootCommand` | [backend/core/catalog.py:330](../backend/core/catalog.py#L330) / [:337](../backend/core/catalog.py#L337) / [:372](../backend/core/catalog.py#L372) | 웹이 실행하는 것(다운로드는 `/opt/localsiem/run/`에). 웹에서 설치한 후(또는 `access_changed`가 있는 업데이트 후) 또는 재구성 시의 root용 명령: `manage.py setup-modules` |
| `fServerSystem` | [backend/core/catalog.py:345](../backend/core/catalog.py#L345) | 모듈의 `install_requirements`를 위한 이 서버의 시스템: `family`(`/etc/alpine-release`가 있으면 `alpine`, `/etc/debian_version`이 있으면 `debian`, 또는 `/etc/os-release`의 `ID`/`ID_LIKE`. 다른 시스템이면 비어 있음)와 `name`(`PRETTY_NAME`) |
| `fResolveRef` | [backend/core/catalog.py:91](../backend/core/catalog.py#L91) | github.com 저장소이면 브랜치 또는 태그의 커밋(GitHub API, `Accept: application/vnd.github.sha`)을 구하므로, 내려받는 아카이브는 그 커밋의 것이며 GitHub가 캐시에 보관한 사본이 아님. 다른 저장소, 아카이브, 이미 커밋인 ref, API 응답 없음: ref를 그대로 사용. 모든 다운로드는 `Cache-Control: no-cache`를 보냄(`dNoCacheHeaders`) |
| `fGetCatalog` / `fInstallFromCatalog` | [backend/web/api_modules.py:384](../backend/web/api_modules.py#L384) / [:395](../backend/web/api_modules.py#L395) | `GET /api/admin/module-catalog`: `installed`, `newer`, `action`이 포함된 저장소의 모듈(설치 가능, 그리고 설치됨의 업데이트). `POST /api/admin/module-catalog/{name}`: 설치 또는 업데이트(같은 호출. `fFirstInstallation`은 이전 사본이 없었을 때만), 그다음 `mReloadModules`와 수집기 `restart`. 응답에는 `version`, `previous`, `enabled`, `turned_off`, `requirements_missing`, `read_paths`, `access_changed`, `root_command`, `collector_restarted`가 있음. `GET`의 응답에는 `system`(`fServerSystem`)도 있고, 각 모듈에는 `install_requirements`가 있음 |
| `fGrantReadAccess` | [backend/manage.py:116](../backend/manage.py#L116) | 설치된 모듈의 `read_paths`에 대한 읽기 권한(ACL, 기본 ACL, Debian의 `adm` 그룹). `setup-modules`가 실행 |
| `fConfigureCredentials` / `fEnsureAdmin` | [deploy/configure.py:247](../deploy/configure.py#L247) / [:340](../deploy/configure.py#L340) | `localsiem.env`: JWT 비밀 값, 새로 설치할 때나 `--rotate-credentials`(이제 새 JWT 비밀 값만 의미)를 지정할 때만 생성. 실행할 때마다 이전 버전이 원격 입력을 위해 보관한 변수(`lRemovedEnvironment`)를 제거하고 최대 하나의 블록(시스템 사용자와 JWT 서명 비밀 값)을 반환. 첫 번째 웹 계정 `admin`. `fMain`은 `/root/webapp-credentials.txt`에 `admin`의 블록을 먼저 쓰고, 그다음 `fConfigureCredentials`가 반환한 블록을 쓰며, 이후 단계가 실패해도 마찬가지 |
| `fConfigureSettings` / `fRemoveSettings` | [deploy/configure.py:220](../deploy/configure.py#L220) / [backend/core/config.py:194](../backend/core/config.py#L194) | 설치 프로그램에 지정된 설정을 `settings.json`에 저장. 더 이상 존재하지 않는 기능의 저장된 키(`lRemovedSettings`: `http_input`)를 제거하며, 그런 키가 있을 때만 파일을 씀 |
| `lLanguages` / `lRightToLeftLanguages` | [backend/core/config.py:46](../backend/core/config.py#L46) / [:50](../backend/core/config.py#L50) | 15개 언어(알파벳순. en-US가 원본이자 대체 언어)와 오른쪽에서 왼쪽으로 쓰는 언어(he-IL). `common.js`의 `cLanguages`와 `cRightToLeft`는 웹을 위한 같은 목록 |
| `fConfigureCertificates` | [deploy/configure.py:277](../deploy/configure.py#L277) | 지정된 인증서, Let's Encrypt(배포 훅 포함), 기존 인증서 또는 자체 서명 인증서 |
| `fGetSource` | [deploy/install-update-reinstall-debian.sh:525](../deploy/install-update-reinstall-debian.sh#L525) / [alpine.sh:524](../deploy/install-update-reinstall-alpine.sh#L524) | 설치 프로그램이 실행되는 완전한 사본, 또는 `/tmp/localsiem-install.*`에 압축을 푼 GitHub의 아카이브(`--ref`, `--source-url`) |
| `fResolveRef`(설치 프로그램) | [deploy/install-update-reinstall-debian.sh:504](../deploy/install-update-reinstall-debian.sh#L504) / [alpine.sh:503](../deploy/install-update-reinstall-alpine.sh#L503) | 캐시 없이 GitHub API에 물어본 `--ref`(기본값 `main`)의 커밋. `fGetSource`는 그 커밋의 아카이브를 내려받으며, API가 응답하지 않으면 경고를 표시하고 브랜치의 아카이브를 내려받음. 모든 `curl`은 `Cache-Control: no-cache`를 보냄(`aNoCache`) |
| `fEnsurePackages` | [deploy/install-update-reinstall-debian.sh:479](../deploy/install-update-reinstall-debian.sh#L479) / [alpine.sh:483](../deploy/install-update-reinstall-alpine.sh#L483) | 없는 패키지만 설치. `apt-get update` / `apk update`도 그때만 실행 |
| `fGrantLogAccess` | [deploy/install-update-reinstall-debian.sh:585](../deploy/install-update-reinstall-debian.sh#L585) / [alpine.sh:584](../deploy/install-update-reinstall-alpine.sh#L584) | 업데이트할 때마다 설치된 모듈의 폴더에 읽기 권한 부여: `manage.py setup-modules --no-restart` |
| `fIsInstalled` | [deploy/install-update-reinstall-debian.sh:462](../deploy/install-update-reinstall-debian.sh#L462) / [alpine.sh:466](../deploy/install-update-reinstall-alpine.sh#L466) | localSIEM의 흔적(`/opt/localsiem`, systemd 유닛이나 OpenRC 스크립트, 또는 그 홈을 가진 `localsiem` 사용자): 하나라도 있으면 `--install`이 중지하고, 하나도 없으면 `--update`와 `--reinstall`이 중지 |
| `fConfirmRemoval` / `fRemoveInstallation` / `fUninstall` | [deploy/install-update-reinstall-debian.sh:710](../deploy/install-update-reinstall-debian.sh#L710) / [:749](../deploy/install-update-reinstall-debian.sh#L749) / [:817](../deploy/install-update-reinstall-debian.sh#L817); [alpine.sh:694](../deploy/install-update-reinstall-alpine.sh#L694) / [:733](../deploy/install-update-reinstall-alpine.sh#L733) / [:808](../deploy/install-update-reinstall-alpine.sh#L808) | `--uninstall`과 `--reinstall`이 공유. `fConfirmRemoval`: 삭제되는 것을 보여 주고, `--yes`가 없으면 `/dev/tty`에서 `yes`를 받음(취소는 오류가 아님: `vConfirmed`가 비어 있음). `fRemoveInstallation`: 서비스, 프로세스, ACL(`fRemoveReadAccess`), apache2 모듈 1.2.0 이하 버전에서 `--configure-apache`가 추가한 Apache 파일(`fRemoveApacheSetup`. `localsiem_access.log*`는 남음), logrotate, Let's Encrypt 훅, 사용자와 그룹, `/opt/localsiem`, `/tmp/localsiem-install.*`에 있는 이전 실행의 사본(이번 실행의 사본은 제외), `/root/webapp-credentials.txt`의 localSIEM 블록(`fRemoveCredentials`). `fUninstall`: 자체 로그의 시작과 함께 실행되는 `--uninstall`. 아무것도 삭제하지 않으면(`vRemovedAny`가 비어 있음) `fUninstall`은 «Nothing of localSIEM was found on this server.»라고 표시 |
| `fInitStyle` / `fStartLog` / `fSplitOutput` / `fStopLog` | [deploy/install-update-reinstall-debian.sh:129](../deploy/install-update-reinstall-debian.sh#L129) / [:283](../deploy/install-update-reinstall-debian.sh#L283) / [:291](../deploy/install-update-reinstall-debian.sh#L291) / [:324](../deploy/install-update-reinstall-debian.sh#L324); [alpine.sh:128](../deploy/install-update-reinstall-alpine.sh#L128) / [:282](../deploy/install-update-reinstall-alpine.sh#L282) / [:290](../deploy/install-update-reinstall-alpine.sh#L290) / [:323](../deploy/install-update-reinstall-alpine.sh#L323) | 설치 프로그램의 출력: 터미널에서만 색 사용(한 번 결정되어, 설치 프로그램이 실행하는 Python 도구에 `LOCALSIEM_COLOR`로 전달됨). 로그가 열리면 stdout과 stderr는 순서가 유지되는 하나의 스트림이 되며, `fSplitOutput`(순수 bash로, Alpine의 BusyBox에서도 동일)이 이를 화면으로, 그리고 색 코드 없이 `/root/webapp-install.log`로 보냄. `cLogOnly` 또는 `cScreenOnly`로 표시된 줄은 한쪽으로만 감(`fToLog`, `fToScreen`: 시각은 화면에서는 표시 형식, 로그에서는 저장 형식). `fCleanup`에서 호출되는 `fStopLog`는 마지막 줄들을 기다림 |
| `fStep` / `fRun` / `fRunToLog` / `fShowOutputTail` | [deploy/install-update-reinstall-debian.sh:177](../deploy/install-update-reinstall-debian.sh#L177) / [:359](../deploy/install-update-reinstall-debian.sh#L359) / [:343](../deploy/install-update-reinstall-debian.sh#L343) / [:379](../deploy/install-update-reinstall-debian.sh#L379); [alpine.sh:176](../deploy/install-update-reinstall-alpine.sh#L176) / [:358](../deploy/install-update-reinstall-alpine.sh#L358) / [:342](../deploy/install-update-reinstall-alpine.sh#L342) / [:378](../deploy/install-update-reinstall-alpine.sh#L378) | 번호가 붙은 단계(`[3/12] Getting localSIEM`. `vStepTotal`: 설치 또는 업데이트는 12, 재설치는 13, 제거는 2)와 결과 줄(`fOk` ✓, `fWarn` !, `fFail` ✗, `fInfo` ·, `fDetail`). `fRun`은 출력이 로그에만 기록되는 명령을 실행하고(`fRunToLog`: `$ command`와 그 줄들, stdin은 `/dev/null`) 한 줄을, 실패하면 마지막 20줄을 보여 줌(`fShowOutputTail`): apt-get 또는 apk, curl, tar, pip, venv, 사용자, 서비스 |
| `fShowHeader` / `fShowNextSteps` / `fShowFailure` | [deploy/install-update-reinstall-debian.sh:264](../deploy/install-update-reinstall-debian.sh#L264) / [:848](../deploy/install-update-reinstall-debian.sh#L848) / [:392](../deploy/install-update-reinstall-debian.sh#L392); [alpine.sh:263](../deploy/install-update-reinstall-alpine.sh#L263) / [:839](../deploy/install-update-reinstall-alpine.sh#L839) / [:391](../deploy/install-update-reinstall-alpine.sh#L391) | 머리글(동작, 서버, 시스템, 시작 시각, 로그). 마지막에는 요약(웹과 SIEM의 주소, 자격 증명, 로그, SOC)과 다음 단계. 실패하면 멈춘 단계 |
| `fTokensSection` / `LocalsiemViews.logins` | [frontend/assets/admin.js:183](../frontend/assets/admin.js#L183) / [:828](../frontend/assets/admin.js#L828) | 사용자 › 액세스 토큰(생성, URL을 한 번만 표시, 폐기). 로그인 기록 |
| `LocalsiemViews.channels` / `fChannelsGeneralSection` / `fTelegramSection` | [frontend/assets/admin.js:420](../frontend/assets/admin.js#L420) / [:431](../frontend/assets/admin.js#L431) / [:516](../frontend/assets/admin.js#L516) | 하위 탭(`fChannelSections`)이 있는 채널 탭: 일반(모든 채널 켜기 또는 끄기, 최소 심각도, 언어, 채널마다 상태가 표시되는 한 행)과 Telegram(토큰, 채팅 ID, «저장하고 테스트 메시지 보내기», «토큰 삭제», 상태, 설정 단계). 상태는 15초마다 새로 고쳐짐 |
| `ldTabs` / `fRoute` | [frontend/assets/app.js:19](../frontend/assets/app.js#L19) / [:356](../frontend/assets/app.js#L356) | 두 대시보드의 탭. 다른 대시보드의 URL을 자신의 대시보드로 이동시키고, 사용자, 채널, 모듈의 첫 번째 섹션을 열고(`lUserSections`, `lChannelSections`, `lModuleSections`), 이전 `/admin/dashboard/modules/<name>/`을 `modules/installed/<name>/`으로 이동시키고, 그 밖의 곳에서는 두 번째 부분을 버리는 라우터. `fShowView`는 `modules/installed/<name>/`에 대해 `LocalsiemViews.module`을 그림 |
| `fLoginView` / `fDone` | [frontend/assets/app.js:97](../frontend/assets/app.js#L97) / [:153](../frontend/assets/app.js#L153) | 버튼 아래에 언어와 테마가 있는 로그인 양식(`fLanguageSelect` / `fThemeToggle`, [common.js:590](../frontend/assets/common.js#L590) / [:602](../frontend/assets/common.js#L602)). 로그인 후 버튼을 누를 때 표시된 언어가 계정의 언어가 됨(`PATCH /api/account`) |
| `LocalsiemViews.overview` | [frontend/assets/overview.js:26](../frontend/assets/overview.js#L26) | 개요 탭 |
| `LocalsiemViews.modules` / `.module` | [frontend/assets/modules.js:389](../frontend/assets/modules.js#L389) / [:683](../frontend/assets/modules.js#L683) | 모듈 탭: 관리자에게는 섹션(`fModuleSections`)이 있고, 설치됨에서는 설치된 모듈마다 전체 너비의 한 행이 모듈 페이지의 머리글처럼 한 부분 아래에 다른 부분이 오도록 배치됨(`fCard`: 이름, ID, 버전과, 관리자에게는 오른쪽에 켜기/끄기 스위치(요구 사항이 충족되지 않은 동안 잠김)가 있는 `.module-head`. 상태, 요약, 이유와, 관리자에게는 새 버전 안내 `fUpdateNotice`. 카운터. 그리고 관리자에게는 맨 아래의 `fCardActions`). 분석가는 행만 봄. 모듈 하나의 페이지 `installed/<name>/`(요구 사항과 재구성. «설치된 모듈로 돌아가기»와 제거는 `installed/`로 이동) |
| `fModuleSections` | [frontend/assets/modules.js:194](../frontend/assets/modules.js#L194) | 모듈의 하위 탭인 설치됨과 설치 가능. 각각 해당 URL로의 링크(`admin.js fUserSections`처럼) |
| `fCatalogPanel` | [frontend/assets/modules.js:218](../frontend/assets/modules.js#L218) | 설치 가능 섹션: 저장소 확인(`fCheck` → `fFetchCatalog(true)`: 항상 다시 내려받음). 아직 설치되지 않은 모듈만 설치 버튼(또는 설치할 수 없는 이유: incompatible, invalid)과 함께 표시. 없으면 `catalog.all_installed` 또는 `catalog.empty`. 모듈을 설치하면 보관된 응답을 잊고(`fForgetCatalog`), 목록에서 제거하고, root용 명령이나 서버에 없는 것과 «설치된 모듈 보기»가 담긴 대화 상자(`P.fModal`, `fResult`)를 엶. 설치되지 않은 각 모듈에는 **설치** 앞에 **요구 사항**이 있음: `fShowRequirements` → `fRequirementsBody`(모듈의 참고 사항과, `system.family`의 또는 모듈이 선언한 모든 시스템의 `install_requirements`를 `fRequirementCommands`를 통해 root로 실행하는 형태와 앞에 `sudo`를 붙인 형태로, 각각 «복사»가 있는 `fCommandBox`에 표시) |
| `cCatalogSeconds` / `fFetchCatalog` / `fForgetCatalog` | [frontend/assets/modules.js:174](../frontend/assets/modules.js#L174) / [:177](../frontend/assets/modules.js#L177) / [:186](../frontend/assets/modules.js#L186) | 브라우저에 600초 동안 보관되고(`dCatalogCache`) 설치됨과 설치 가능이 공유하는 `GET /api/admin/module-catalog`의 마지막 응답. 설치됨을 열 때마다 저장소를 내려받지 않기 위함. `fFetchCatalog(true)`(저장소 확인)는 항상 다시 내려받음. 모듈을 설치, 업데이트, 제거하면 응답을 잊음 |
| `fCheckRepository` / `fUpdateNotice` | [frontend/assets/modules.js:543](../frontend/assets/modules.js#L543) / [:417](../frontend/assets/modules.js#L417) | 설치됨, 관리자 전용: 섹션이 열릴 때 한 번 `fFetchCatalog(false)` → `dNewer`(`newer`가 있고 동작이 update 또는 incompatible인 항목). 그동안 `modules.checking_updates`, 실패하면 `modules.updates_failed`(목록은 평소처럼 작동). 10초마다 하는 새로 고침에서는 절대 실행하지 않음. 행의 안내(`.module-update`): 업데이트 버튼이 있는 `modules.update_notice`, 또는 버튼이 없는 `modules.update_incompatible`(`.module-update-blocked`). 설치된 버전이 저장소와 비교한 버전일 때만 표시 |
| `fUpdate` / `fUpdateResult` | [frontend/assets/modules.js:452](../frontend/assets/modules.js#L452) / [:436](../frontend/assets/modules.js#L436) | 업데이트: 확인(`modules.update_confirm`), `POST /api/admin/module-catalog/{name}`(그동안 버튼에 «업데이트 중…» 표시: `sUpdating`, 새로 고침 사이에도 유지), `fForgetCatalog`, 토스트 `modules.updated_toast`. 대화 상자(«<module> 업데이트 완료»)는 `access_changed`(root용 명령)가 있거나 `collector_restarted`가 없을 때만 표시. 그다음 `fLoad` |
| `fDraw` / `fLoad`(설치됨) | [frontend/assets/modules.js:517](../frontend/assets/modules.js#L517) / [:531](../frontend/assets/modules.js#L531) | `fLoad`(10초마다)는 `GET /api/modules`만 요청하고 응답을 보관(`dLast`). `fDraw`는 그 응답으로 행을 그리며, 저장소 확인이 끝날 때와 업데이트가 시작될 때도 그림 |
| `fCheckItem` / `fCommandBox` | [frontend/assets/modules.js:70](../frontend/assets/modules.js#L70) / [:61](../frontend/assets/modules.js#L61) | 해결 방법이 함께 있는 검사 하나(진단, 요구 사항). 복사할 텍스트(root용 명령) |
| `fUninstallButton` / `fCardActions` | [frontend/assets/modules.js:146](../frontend/assets/modules.js#L146) / [:508](../frontend/assets/modules.js#L508) | 확인 후 제거(설치됨의 행과 모듈 페이지. 보관된 저장소 응답을 잊음, `fForgetCatalog`). 관리자를 위한 행의 동작: 구성(→ `installed/<name>/`)과 제거 |
| `fInput` / `fRecordsEditor` | [frontend/assets/modules.js:586](../frontend/assets/modules.js#L586) / [:612](../frontend/assets/modules.js#L612) | `module.json`으로 만든 설정 양식, 레코드 편집기 포함 |

<a id="flows"></a>
## 4. 주요 호출 경로

**모듈 불러오기(수집기 시작)**

`Collector.mSetup` → `fCreateModules` → `fListManifests` (`cModulesPath/*/module.json`) → `fReadManifest` (id, entry, settings, `core` ≤ `cVersion`, 로캘) → `fLoadClass` (`fRegisterPackage` + `localsiem_modules.<name>.<file>`) → `Class(settings, masker, storage, manifest)` → `Module.mStart` → `mCreateCorrelator` → 로그 «Modules: apache2 1.1.0 (on)» → `mCheckRequirements` (`fCheckRequirements` → 각 모듈의 `Module.mRequirements` → 상태 `<name>.requirements`. 충족되지 않으면 로그 «Module apache2: requirements missing: ...») → `mLoadRules` → `mDiscover`(활성화된 모듈만) → `mPublishDoctor`. 오류는 `ldModuleErrors`로 가고 루프는 계속됩니다.

**로그 줄에서 SOC의 알림까지**

1. `Collector.mCycle` → `mReadSources` → `FileTailer.mPoll`(새로운 완전한 줄) → 소스의 프레이머(`Module.mCreateFramer`: `LineFramer` 또는 Apache 모듈의 감사 프레이머) → 소스 모듈의 `Module.mParse`(마스킹) → `mStoreRecords` → `SqliteStorage.mSaveRecords`(레코드 + FTS + 위치, 하나의 트랜잭션) → 상관기 `mAdd`.
2. `mProcessDue` → 상관기 `mDue`(기간이 지나고 워터마크에 도달) → `Module.mBuildEvent`(수행된 조치, 점수, 탐지) → `RulesEngine.mEvaluate`(모듈 규칙) → `SqliteStorage.mSaveEvents` → `mDetect` → `Grouper.mAdd`(새 그룹 또는 횟수 +1).
3. `mProcessGroups`(매초) → `SqliteStorage.mGetDueGroups` → `Module.mEnrich` (`mGetIpContext`) → `fSocConfigured` → `fBuildAlert` → `mQueueGroup`(SOC가 없으면: `mSkipGroup`, 상태 `local`).
4. `SocSender.run`(스레드) → `mCycle`(SOC가 없으면: `mSkipPending`만 실행) → `mSendHeartbeat`(5분마다)와 `mGetQueueBatch`(알림 ≤ 100개, ≤ 1 MiB) → `mDeliver` → `SocClient.mSendAlerts` → `mMarkQueueSent`(SOC 코드), 또는 분할, 보류, 백오프로 지연, 507이면 일시 중지.
5. 이와 별도로 `mProcessGroups` → `ChannelSender.mNotify`(`fChannelSettings`, `fSeverityReached`, `fBuildMessage`) → 켜져 있고 설정된 각 채널의 목록 → `ChannelSender.run`(스레드, 매초) → `mCycle` → `mDeliver` → `TelegramClient.mSendMessage` → 상태 `channels.status`(보낸 메시지, 실패, 버려짐, 마지막 오류).

**Telegram 설정**

`/admin/dashboard/channels/telegram/` → `admin.js fTelegramSection` → «저장하고 테스트 메시지 보내기» → `POST /api/admin/channels/telegram` (`fSaveTelegram`: `cTokenRegex`, `cChatIdRegex`, `fSaveTelegramToken`, `fSaveSettings`, 수집기 `reload`) → `POST /api/admin/channels/telegram/test` (`fTestTelegram` → `TelegramClient.mGetMe` → `fTestMessage`로 `mSendMessage`) → 봇의 @username 또는 Telegram의 설명이 담긴 안내.

**모듈 켜기/끄기, 또는 설정이나 규칙 저장**

`modules.js fSwitch`(모듈 › 설치됨의 행 또는 모듈 페이지의 머리글. 끌 때는 확인. `requirements_missing`이 비어 있지 않은 동안에는 요청 없이 잠김) 또는 `LocalsiemViews.module`의 양식 → `POST /api/admin/modules/{name}` (`fSaveModule`: `fValidateSettings`. 꺼져 있는 모듈을 켤 때: 요청의 설정으로 `WebContext.mCheckRequirements` → 충족되지 않은 검사와 함께 422 `requirements_missing`. `fRules` + `fCleanRules`) → `fSaveSettings`(`settings.json`의 `modules.<name>`과 `rules.<id>`) → `WebContext.mApplySettings` → `mCollector({"command": "reload"})` → `Collector.mHandleIpc` → `mCycle` → `mReloadSettings` (`Module.mReload`, `mCheckRequirements`, `mLoadRules`, `mDiscover`, `mPublishDoctor`, `mPublishState`). `collector.status.modules.<name>.enabled`가 저장된 값과 일치할 때까지 `fSummary`는 `pending`으로 응답합니다.

**요구 사항과 재구성**

모듈 페이지(`/admin/dashboard/modules/installed/<name>/`, `LocalsiemViews.module`) → «재구성»(`fReconfigure`, `has_requirements`일 때 표시) → `POST /api/admin/modules/{name}/reconfigure` (`fReconfigure` → `WebContext.mCheckRequirements`: 저장된 설정으로 설치된 사본에서 새 인스턴스 생성 → `fCheckRequirements` → `mRequirements`, `dRequirements`에 보관 → 수집기 IPC `reload` → `mReloadSettings` → `mCheckRequirements`(상태 `<name>.requirements`)와, 켜져 있는 모듈에 대해서는 `mDiscover`와 `mPublishDoctor`) → 응답: `requirements`와, 충족되면 `fRootCommand` → `fShowReconfigured` → `fLoad` (`GET /api/admin/modules/{name}` → `fRequirements`: 수집기와 웹의 검사 중 최신 것) → 스위치 잠금이 해제되지만, 관리자가 켤 때까지 모듈은 꺼진 상태로 유지됩니다.

**모듈 상태와 개요**

`modules.js`(모듈 › 설치됨과 분석가의 모듈 탭. 10초마다) → `GET /api/modules` → `fRead`(`collector.status`, `<name>.doctor`와 `<name>.requirements` 상태, 24시간의 `mModuleCounts`) → `fSummaries` → 매니페스트마다 `fSummary`(불러오기 오류 → `error`. 꺼짐 → `disabled`, 가장 최근 요구 사항 검사 `fRequirements`에 오류가 있으면 `requirements_missing`과 함께. 수집기가 2분 동안 응답 없음 → `unknown`. `collector.status.modules`에 없음 → `warning`/`not_loaded`. enabled가 다름 → `pending`. 진단 오류 또는 읽을 수 없는 소스 → `error`. 소스 없음 또는 존재하지 않는 소스 → `warning`. 진단 경고는 참고 사항이며 `ok`를 유지) + 불러올 수 없는 폴더에 대한 `fBrokenSummary`. `overview.js`(15초마다) → `GET /api/overview` → `fOverview` → `fRead`, `fSummaries`, `mAlertCounts`, `mQueueStatistics`, `soc.status`와 `soc.heartbeat` 상태, `mHistogram`(24시간의 시간별 버킷), `mListGroups`(최근 6개).

**모듈 탭, 그 섹션과 모듈 페이지**

`/admin/dashboard/modules/` → `fAdminTab` → `modules/installed/`로 302(`lModuleSections[0]`) → `fAdminModulesSection`(세션을 먼저 확인. 분석가 → `/user/dashboard/modules/`. `installed` 또는 `installable` → `index.html`. 설치된 모듈의 이름, 즉 이전 URL → `installed/<name>/`로 301. 그 밖의 것 → 404) → `app.js fRoute`(`cPathRegex`는 두 번째 부분을 허용. `/admin/dashboard/modules/`와 `/admin/dashboard/modules/<name>/` → `modules/installed/`와 `modules/installed/<name>/`. `installable/` 아래나 사용자 탭의 두 번째 부분은 버려지며, 다른 탭은 두 번째 부분을 받지 않음) → `fShowView("modules", section, item)` → `LocalsiemViews.modules`(`fModuleSections`. 설치됨: `fLoad` → `GET /api/modules` → `fDraw` → 모듈마다 `fCard`와, 관리자에게는 `fCheckRepository` 한 번(«모듈 업데이트» 참조). 설치 가능: `fCatalogPanel`) 또는 항목이 있으면 `LocalsiemViews.module`(이때 `vParameter`는 모듈 이름). 행의 «구성»(`fCardActions`) → `/admin/dashboard/modules/installed/<name>/` → `fAdminModule`(설치되지 않은 모듈은 404) → `LocalsiemViews.module` → `GET /api/admin/modules/{name}`. «설치된 모듈로 돌아가기», 제거, 사라진 모듈(`not_found`) → `/admin/dashboard/modules/installed/`. 분석가: `/user/dashboard/modules/` → `fUserTab` → 행만 있는 `LocalsiemViews.modules`(라우터가 두 번째 부분을 모두 버림).

**쿼리에서 결과까지**

`search.js fRun` → `GET /api/search`, `/api/search/histogram`, `/api/search/summaries` → `fParseQuery`(오류 시 코드와 위치와 함께 400) → `fRange` → `SqliteStorage.mSearch` / `mHistogram` / `mSummaries` → `fCompileQuery` → 진행 핸들러가 있는 SQLite(시간 제한, 422 `search_timeout`) → `Accounts.mAudit` → 기본 표시 시각이 담긴 JSON. 행 → `GET /api/events/{id}` → `fEvent` → `mGetEventDetail` → 각 레코드에 대해 `WebContext.mModule(record.module)` → `mDisplayRecord`(Apache 모듈은 감사 레코드의 헤더와 본문을 추가) → 피벗이 있는 요청 카드.

**액세스 토큰을 사용한 직접 로그인**

`admin.js fTokensSection` → `POST /api/admin/tokens` (`fCreateToken` → `Accounts.mCreateAccessToken`: 활성 분석가, 1–365일, `access_tokens`에 SHA-256) → URL `https://<server>:10443/auth/login/auto?token=...`을 한 번만 표시(`fShowSecret`). 분석가가 이를 엶 → `fLoginWithToken`(이름 `(access token)`으로 `mIsBlocked` → `mCheckAccessToken` → `mRecordAttempt`) → 실패: `mRecordLogin`과 `/auth/login/?error=<reason>`(`app.js fLoginView`가 표시) → 성공: `mCreateSession(..., "token")` → `mMarkAccessTokenUsed` → `mRecordLogin` → 쿠키 → `next`(이 사이트의 경로) 또는 `/user/dashboard/overview/`. 모든 요청 → `mLoadSession`(방식 `token`: 분석가 전용, 2차 인증 없음, 비밀번호 변경 없음).

**로그인과 대시보드**

`app.js fLoginView`(페이지는 양식뿐: `fAuthLogo`, 사용자 이름, 비밀번호, 버튼, 그리고 그 아래의 언어와 테마: `fLanguageSelect`, `fThemeToggle`) → `POST /api/auth/login` (`Accounts.mIsBlocked`, `mCheckPassword`, `mRecordAttempt`) → `mfa_enabled` 꺼짐: 즉시 세션(`step` done) → 켜짐: `step` totp 또는 enroll(`mStartEnrollment`, QR) → `POST /api/auth/totp` (`mReadChallenge`, `mVerifyTotp`) → `mCreateSession` → `mRecordLogin`(모든 실패도 기록: `invalid_credentials`, `invalid_code`, `login_blocked`, `challenge_expired`) → 쿠키 `localsiem_session` → `fDone`(계정에 다른 언어가 있으면 버튼을 누를 때 표시된 언어로 `PATCH /api/account`: 대시보드가 그 언어로 열림) → `next`(매개변수가 포함된 원래 URL) 또는 역할의 개요로 돌아감. 모든 대시보드 URL → `fUserTab` / `fAdminTab`(섹션과 모듈 페이지에는 `fAdminUsersSection`, `fAdminModulesSection`, `fAdminModule`. 세션 없음 → `/auth/login/?next=...`. 다른 역할 → 자신의 대시보드의 같은 탭) → `index.html` → `app.js fRoute` → `fShowView` → `window.LocalsiemViews[tab]`(`modules/installed/<name>/`에는 `LocalsiemViews.module`).

**코어 설치 또는 업데이트**

`curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- ACTION options` → `install-update-reinstall-*.sh fMain`(정확히 하나의 동작 `--install`, `--update`, `--reinstall` 또는 `--uninstall`이 필요하며, 없으면 중지. `fIsInstalled`: `--install`은 localSIEM이 없을 때만, `--update`와 `--reinstall`은 있을 때만. `--reinstall`: 먼저 `fConfirmRemoval`. `--configure-*`는 거부되며(모듈에는 셋업 옵션이 없음) `--modules-from`도 거부됨: 모듈은 웹에서 설치) → `fEnsurePackages` → `fGetSource`(완전한 사본, 또는 `fResolveRef`(GitHub API에 물어본 `<ref>`의 커밋)와 캐시 없는 `curl`로 받아 `/tmp/localsiem-install.*`에 압축을 푼 `https://github.com/PYMEHackers/localSIEM/archive/<commit>.tar.gz`) → `configure.py --check-arguments` → `--reinstall`일 때만: `fRemoveInstallation`(내려받은 사본을 제외한 모든 것을 삭제) → 코어를 `/opt/localsiem/webapp/`에 복사(`AGENTS.md`처럼 작업 사본에만 있는 파일은 있을 때만) → 가상 환경 → `configure.py`(설정, `modules_repository`, 인증서, 자격 증명: `/root/webapp-credentials.txt`에 `admin`을 먼저, 그다음 새로 만들었으면 시스템 사용자와 JWT 비밀 값. 이전 버전의 `http_input`과 원격 입력 변수 제거) → `fGrantLogAccess` (`manage.py setup-modules --no-restart` → `fGrantReadAccess`: 이미 설치된 모듈) → 서비스 재시작 → `localsiem`으로 `manage.py modules`와 `doctor` → 모듈을 설치할 곳(웹) 안내. 화면에는 번호가 붙은 단계(`fStep`)와 결과 표시로 나타나며, 로그에는 같은 줄이 색 없이, 그리고 `fRun`으로 실행한 모든 명령의 전체 출력이 기록됩니다(`fStartLog` → `fSplitOutput`). 실패하면 어느 단계에서 멈췄는지 알려 줍니다(`fShowFailure`).

**모듈 제거**

`modules.js fUninstallButton`(모듈 › 설치됨의 행, `fCardActions`, 또는 모듈 페이지. 확인) → `DELETE /api/admin/modules/{name}` (`fUninstallModule` → `fRemove` → `InstallLock` → `/opt/localsiem/modules/<name>`을 `.staging-*`로 이름 바꾸기 → 삭제) → `WebContext.mReloadModules`(모듈이 더 이상 나열되지 않음) → 수집기 IPC `restart`(systemd 또는 supervise-daemon이 다시 시작 → 모듈 없이 `fCreateModules`) → `fForgetCatalog` → 목록을 다시 그리거나, 모듈 페이지는 `/admin/dashboard/modules/installed/`로 이동. `settings.json`은 `modules.<name>`과 `rules.<id>`를 유지합니다.

**웹에서 모듈 설치**

`/admin/dashboard/modules/installable/` → `modules.js fCatalogPanel` → «저장소 확인»(`fCheck` → `fFetchCatalog(true)`) → `GET /api/admin/module-catalog` (`fGetCatalog` → `fFetchCatalog` → `fResolveRef` → `fArchiveUrl` → `/opt/localsiem/run/catalog.*`에 `fDownload` → `fCatalog` → `fModuleFolders`(`mod-<id>` 폴더)와 `fListManifests`) → `installed`가 null인 항목만 나열(`fDraw`. 저장소의 모든 모듈이 설치되어 있으면 `catalog.all_installed`, 모듈이 없으면 `catalog.empty`) → «요구 사항»(`fShowRequirements` → `fRequirementsBody` → `fRequirementCommands`: `system.family`의 `install_requirements`를 root로 실행하는 형태와 `sudo`를 붙인 형태로. 아무것도 실행하지 않음) 또는 «설치»(`fInstall`) → `POST /api/admin/module-catalog/{name}` (`fInstallFromCatalog` → `fFetchAndInstall` → `InstallLock` → `fResolveRef` → `fDownload` → `fInstall`: `mod-<name>` → `/opt/localsiem/modules/<name>`) → `WebContext.mReloadModules` → 첫 설치일 때만: `fFirstInstallation`(설치된 사본에서 `WebContext.mCheckRequirements` → 요구 사항이 충족되지 않고 `modules.<name>.enabled`가 저장된 적이 없으면 `enabled: false`로 `fSaveSettings`) → 수집기 IPC `restart`(`Collector.mHandleIpc` → `vStop`. systemd 또는 supervise-daemon이 다시 시작 → `fCreateModules`가 모듈을 불러옴 → `mCheckRequirements`) → `requirements_missing`과 `fRootCommand`가 담긴 응답 → `fForgetCatalog` → 모듈이 목록에서 사라지고(`fDraw`) 대화 상자가 열림(`P.fModal`, «<module> 설치 완료», `fResult`): 서버에 없는 것(과 재구성) 또는 root용 명령. 닫기, 또는 «설치된 모듈 보기» → `/admin/dashboard/modules/installed/` → 관리자가 root로 실행(`manage.py setup-modules` → `fGrantReadAccess`, `fRestartServices`, `fDoctorAsLocalsiem`).

**모듈 업데이트**

`/admin/dashboard/modules/installed/` → `LocalsiemViews.modules`(관리자) → `fLoad` (`GET /api/modules` → `dLast` → `fDraw`)와, 한 번 `fCheckRepository` (`modules.checking_updates`) → `fFetchCatalog(false)`(보관된 응답이 10분 미만이면 그것을 사용, `cCatalogSeconds`. 그렇지 않으면 `GET /api/admin/module-catalog` → `fGetCatalog` → `catalog.py fFetchCatalog` → `fCatalog`: 각 모듈의 `newer`와 `action`) → `dNewer`(`newer`가 있고 동작이 `update` 또는 `incompatible`인 항목) → `fDraw` → `fCard` → `fUpdateNotice`(항목의 `installed`가 행의 버전일 때만: `modules.update_notice`와 «업데이트», 또는 버튼이 없는 `modules.update_incompatible`) → «업데이트» → `fUpdate` (`P.fConfirm`, «모듈 업데이트». `sUpdating`: «업데이트 중…», 10초마다 하는 새로 고침 사이에도 유지) → `POST /api/admin/module-catalog/{name}` (`fInstallFromCatalog` → `fFetchAndInstall` → `InstallLock` → `fResolveRef` → `fDownload` → `fInstall`: 새 사본을 설치된 사본과 교체, `previous`와 `access_changed` 포함) → `WebContext.mReloadModules` → `fFirstInstallation` 없음(`previous`가 `None`이 아님: 설정과 켜짐/꺼짐 상태는 그대로 유지) → 수집기 IPC `restart` → 응답 → 모듈이 `dNewer`에서 빠짐 → `fForgetCatalog` → 토스트 `modules.updated_toast` → `access_changed`가 있거나 `collector_restarted`가 없을 때만: 대화 상자(`P.fModal`, «<module> 업데이트 완료», `fUpdateResult`: root용 명령 `fRootCommand`, 또는 `localsiem` 서비스 재시작) → `fLoad`. 확인에 실패하면 `vRepositoryNote`가 `modules.updates_failed`를 표시하고 목록은 평소처럼 작동합니다. 웹은 모듈을 재설치하거나 이전 버전을 설치하지 않습니다(동작 `reinstall`과 `downgrade`).

<a id="routes"></a>
## 5. 라우트와 진입점

| 라우트 / 명령 | 핸들러 | 파일 |
|---|---|---|
| `/` → 역할의 대시보드 개요(또는 `/auth/login/`) | `fRoot` | [backend/web/app.py](../backend/web/app.py) |
| `/auth/login/`, `/auth/register/`, `/auth/recover/` | `fPage`(하나의 HTML 셸) | [backend/web/app.py](../backend/web/app.py) |
| `/user/dashboard/` → `/user/dashboard/overview/`; `overview/`, `search/`, `live/`, `alerts/`, `modules/`, `account/`(관리자는 `/admin/dashboard/`의 같은 탭으로 이동) | `fUserDashboard`, `fUserTab` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/` → `/admin/dashboard/overview/`; `overview/`, `search/`, `live/`, `alerts/`, `soc/`, `settings/`, `audit/`, `logins/`, `account/`(분석가는 `/user/dashboard/`의 같은 탭으로, 관리 탭이면 그 `overview/`로 이동); `users/` → `users/accounts/`; `modules/` → `modules/installed/` | `fAdminDashboard`, `fAdminTab` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/users/accounts/`, `/admin/dashboard/users/tokens/`; `/admin/dashboards/...` → `/admin/dashboard/...` | `fAdminUsersSection`, `fAdminDashboards` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/channels/` → `/admin/dashboard/channels/general/`; `/admin/dashboard/channels/general/`, `/admin/dashboard/channels/telegram/`(분석가는 `/user/dashboard/overview/`로 이동) | `fAdminTab`, `fAdminChannelsSection` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/modules/installed/`, `/admin/dashboard/modules/installable/`(분석가는 `/user/dashboard/modules/`로 이동); 이전 `/admin/dashboard/modules/<name>/` → `/admin/dashboard/modules/installed/<name>/`로 301(모듈이 설치되어 있지 않으면 404) | `fAdminModulesSection` | [backend/web/app.py](../backend/web/app.py) |
| `/auth/login/auto?token=TOKEN`(또는 `?TOKEN`. 선택적 `next`) | `fLoginWithToken` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/modules/installed/<name>/`(설치되지 않은 모듈은 404. 분석가는 `/user/dashboard/modules/`로 이동) | `fAdminModule` | [backend/web/app.py](../backend/web/app.py) |
| `GET /api/auth/session`, `POST /api/auth/login`, `POST /api/auth/totp`, `POST /api/auth/logout` | `fGetSession`, `fLogin`, `fLoginTotp`, `fLogout` | [backend/web/app.py](../backend/web/app.py) |
| `GET/PATCH /api/account`, `POST /api/account/password`, `POST /api/account/totp/reset` | 계정 핸들러 | [backend/web/app.py](../backend/web/app.py) |
| `GET /api/search`, `/api/search/histogram`, `/api/search/summaries`, `/api/search/export` | `fSearch`, `fHistogram`, `fSummaries`, `fExport` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/events/{id}` | `fEvent` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/alerts`, `GET /api/alerts/{id}` | `fAlerts`, `fAlert` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/ws`(프로토콜), `WebSocket /api/ws`(로그인된 세션 쿠키만. 그렇지 않으면 4401로 닫힘) | `fWebSocketProtocol`, `fLive` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/modules`(로그인한 모든 사용자) | `fModules` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/admin/modules/{name}`, `POST /api/admin/modules/{name}`(`enabled`, `settings`, `rules`. 422 `requirements_missing`), `DELETE /api/admin/modules/{name}`(제거), `POST /api/admin/modules/{name}/doctor`, `POST /api/admin/modules/{name}/reconfigure` | `fModule`, `fSaveModule`, `fUninstallModule`, `fRunDoctor`, `fReconfigure` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/admin/module-catalog`(설치 가능, 그리고 설치됨의 새 버전 확인), `POST /api/admin/module-catalog/{name}`(설치 또는 업데이트: 같은 호출) | `fGetCatalog`, `fInstallFromCatalog` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/overview`(로그인한 모든 사용자) | `fGetOverview` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `/api/admin/users` (GET, POST), `/api/admin/users/{id}` (PATCH, DELETE), `.../password`, `.../totp-reset` | 사용자 핸들러 | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/soc`, `POST /api/admin/soc/test`, `/retry`, `/requeue` | SOC 핸들러 | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/channels`, `POST /api/admin/channels/telegram`, `POST /api/admin/channels/telegram/test` | `fChannels`, `fSaveChannels`, `fSaveTelegram`, `fTestTelegram` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/settings`, `GET /api/admin/audit` | 설정 및 감사 핸들러 | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET /api/admin/tokens`, `POST /api/admin/tokens` (`user_id`, `label`, `days`), `DELETE /api/admin/tokens/{id}` | `fTokens`, `fCreateToken`, `fRevokeToken` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET /api/admin/logins` (`before`, `limit`, `result`) | `fLogins` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `/api/doc/` | FastAPI의 Swagger | [backend/web/app.py](../backend/web/app.py) |
| `backend/collector.py [--from-start] [--once]` | `fMain` | [backend/collector.py](../backend/collector.py) |
| `backend/server.py`(`-h`/`--help` 외에는 옵션 없음) | `fMain` | [backend/server.py](../backend/server.py) |
| `backend/manage.py ensure-admin\|create-user\|reset-password\|reset-mfa\|list-users\|doctor [--json]\|modules\|read-paths\|soc-test\|setup-modules [--no-restart]` | `fMain` | [backend/manage.py](../backend/manage.py) |
| `deploy/install-update-reinstall-debian.sh`, `deploy/install-update-reinstall-alpine.sh`(동작 하나: `--install`, `--update`, `--reinstall [--yes]` 또는 `--uninstall [--yes]`. `--ref`, `--source-url`과 `configure.py`의 옵션), `https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/`에서 파이프로도 실행(헤더 `Accept: application/vnd.github.raw+json`) | `fMain` | [deploy/](../deploy/) |

<a id="impact"></a>
## 6. 영향 분석

| 구성 요소 | 변경 시 영향을 받는 것 |
|---|---|
| `storage_sqlite.lSchema`의 스키마 | 모든 검색, 웹, 보존, 개요의 카운트. 열은 `CREATE ... IF NOT EXISTS`로 추가되며, 기존 열을 변경하려면 마이그레이션(`meta.schema_version`)이 필요합니다. |
| `Module` 인터페이스([backend/core/module.py](../backend/core/module.py)) | 모든 모듈(모두 `localSIEM-modules`에서 오며, 코어에는 자체 모듈이 없음). 수집기. 웹 훅 `mDisplayRecord`. `mRequirements`(첫 설치, 켜기, 재구성, 수집기 시작과 다시 불러오기, `manage.py modules`와 `doctor`). `manage.py`(`mDoctor`, `mSkipped`). 설치된 모듈이 계속 작동하도록 기본 클래스에 기본 구현이 있는 훅을 추가하십시오. |
| `module.json` 형식(`fReadManifest`, `fCheckSetting`, `lSettingTypes`) | 모든 모듈. `modules.js`의 설정 양식(`fInput`, `fRecordsEditor`). `fValidateSettings`. `read_paths`: `manage.py read-paths`와 `setup-modules`(웹과 설치 프로그램의 root 명령이 설정하는 ACL). 검사를 더 엄격하게 하면 설치된 모듈을 불러올 수 없게 됩니다. `install_requirements`(`fCheckInstallRequirements`, `lSystems`): 설치 가능의 요구 사항 대화 상자(`fRequirementsBody`). 잘못된 값이 있는 모듈은 설치되지도 불러와지지도 않습니다 |
| `Module.mRequirements`와 `fCheckRequirements` | 첫 설치(꺼짐), 스위치(잠김. 422 `requirements_missing`), 재구성, 수집기의 상태 `<name>.requirements`, `manage.py modules`와 `doctor`. 검사가 실패한 모듈은 요구 사항을 충족하지 않으므로 켤 수 없습니다. 요청마다 또는 주기마다 호출하지 마십시오. |
| `cVersion` | 모든 `module.json`의 `core` 필드: 더 새로운 코어가 필요한 모듈은 불러와지지 않습니다. 웹에 표시되는 버전, 모든 알림의 `details`, SOC로 보내는 `User-Agent`에 들어가는 버전. |
| `cModulesPath`, `localsiem_modules` 패키지 | 모듈을 찾는 위치와 가져오는 방식. 카탈로그(`fInstall`, `InstallLock`), 모든 모듈 내부의 상대 가져오기, `WebContext.mReloadModules`. |
| `backend/core/catalog.py`, 그 API(`fGetCatalog`, `fInstallFromCatalog`)와 설정 `modules_repository` | 모듈의 설치 가능 섹션(`installed`가 null인 항목만 나열하는 `fCatalogPanel`), 설치됨의 업데이트(`fCheckRepository`, `fUpdateNotice`, `fUpdate`는 각 항목의 `newer`, `action`, `installed`, `version`, `core`와 설치 응답의 `previous`, `access_changed`, `root_command`, `collector_restarted`를 읽음)와 제거. 이것이 모듈을 설치, 업데이트, 제거하는 유일한 방법입니다. `localSIEM-modules` 저장소의 구조(`mod-<id>` 폴더: `cFolderPrefix`, `fModuleFolders`). 웹이 보여 주는 root 명령(`fRootCommand` → `manage.py setup-modules`). 웹 유닛은 `ReadWritePaths`에 `/opt/localsiem/modules`를 유지해야 합니다. 요구 사항 대화 상자는 각 항목의 `install_requirements`와 응답의 `system`을 읽습니다 |
| 브라우저에 보관되는 저장소 응답(`modules.js`의 `dCatalogCache`, `cCatalogSeconds`, `fFetchCatalog`, `fForgetCatalog`) | 설치됨과 설치 가능에 표시되는 것: 저장소에 게시된 새 버전이 설치됨에서 제공되기까지 최대 10분이 걸릴 수 있습니다(«저장소 확인»을 누르거나 페이지를 다시 불러오면 더 짧음). 설치된 모듈을 바꾸는 모든 동작은 `fForgetCatalog`를 호출해야 하며, 그렇지 않으면 설치됨이 이미 끝난 업데이트를 제공하게 됩니다. `fCheck`(저장소 확인)는 계속 `true`로 요청해야 합니다. |
| `manage.py setup-modules`(`fGrantReadAccess`, `fRestartServices`) | 웹의 root 명령(모듈 설치 후, `access_changed`가 있는 업데이트 후, 재구성 시)과 설치 프로그램(`fGrantLogAccess`, `--no-restart`): 모든 모듈의 로그 읽기 권한. 멱등성을 유지하고, 터미널 없이 root로 실행할 수 있게 하십시오. |
| `collector.status`(`mPublishState`), `<name>.doctor`(`mPublishDoctor`), `<name>.requirements`(`mCheckRequirements`) | `api_modules.fSummary`와 `fOverview`(상태, 이유, 카운트, 스위치 잠금), 모듈 페이지와 모듈 하나의 페이지(요구 사항), 개요, 설정 페이지(디스크와 데이터베이스). |
| `fSummary`의 상태와 이유 | 네 로캘 파일의 `module_state.*`와 `module_reason.*` 키, `modules.js`, `overview.js`, 매뉴얼. |
| `access_tokens`, `logins` 테이블과 `sessions.method`([backend/web/webdb.py](../backend/web/webdb.py), 이전 데이터베이스에는 `lColumns`로 추가) | 직접 로그인, `mLoadSession`(어떤 세션이 2차 인증을 건너뛰는지), 사용자 › 액세스 토큰, 로그인 기록. 토큰 세션은 관리자에게 절대 유효하면 안 됩니다. |
| `config.cWebPort`(10443) | `server.py`, `configure.py`(`fCheckPort`, `install.env`에 기억되는 SIEM 주소), 웹에 표시되는 설정, 분석가에게 주는 액세스 URL, SOC(클라이언트의 SIEM 주소). |
| `/root/webapp-credentials.txt`의 블록(`fEnsureAdmin`, `fConfigureCredentials`) | `--uninstall`(`fRemoveCredentials`는 `localSIEM `으로 시작하는 모든 블록을 제거하고 다른 애플리케이션의 블록은 유지): 새 블록은 모두 그렇게 시작해야 합니다. |
| `lUserTabs` / `lAdminTabs`, `lUserSections` / `lModuleSections`(`app.py`와 `app.js`에 있음)와 `ldTabs` | 두 대시보드, 그 리디렉션(서버와 `fRoute`: 사용자와 모듈의 첫 번째 섹션, 모듈 페이지의 이전 URL), 하위 탭(`admin.js fUserSections`, `modules.js fModuleSections`), 모듈 페이지로의 링크(`fCardActions`, «설치된 모듈로 돌아가기», 제거), SOC의 링크(`/user/dashboard/search/?q=...`). 서버와 라우터의 목록은 같게 유지해야 합니다. |
| 계정의 언어(`users.language`) | `app.js fStart`(대시보드가 브라우저의 언어가 아니라 이 언어로 열림), 로그인(`fDone`이 로그인 페이지의 언어를 계정에 설정), 제목 표시줄의 언어 선택기(`fSetLanguage` → `PATCH /api/account`). |
| 레코드 dict(`mParse`) | 상관 분석(`correlation`, `fields.client_ip`, `fields.path`), 요청 카드(`search.js fRecordBlock`과 모듈의 `mDisplayRecord`), FTS(`search`, `raw`). |
| 이벤트 dict(`mBuildEvent`) | `lEventColumns`, 규칙(YAML이 읽는 필드), 그룹화, 검색 필드(`dTextColumns`, `dNumberColumns`), CSV 내보내기, `mModuleCounts`. |
| 모듈이 만드는 범주와 규칙 이름 | 심각도, 알림 규칙 이름(SOC 통계가 이것으로 그룹화하므로 고정적으로 유지하십시오), 그룹화 키. |
| `fGroupKey` / `fExternalId` | SOC의 중복 제거: 이를 바꾸면 이미 보낸 것을 다시 보냅니다. |
| `fBuildAlert` | SOC 계약: `GenericAlert` 제한(규칙 300, 설명 10 000, details 200개 키 × 5000자). |
| `Masker` | 개인 정보: 무엇이 저장되고 무엇이 SOC에 도달하는지. |
| `FileTailer` | 손실 없음/반복 없음 보장. 처음 열 때 오래된 줄은 절대 읽지 않음. 안티 포렌식 통지. 로그를 쓰기 모드로 절대 열면 안 됩니다. `unreadable` 통지의 `was_readable`이 읽을 수 없는 소스가 알림인지를 결정합니다(`fNoticeDetection`). |
| `query.dFields` | 검색 언어, 15개 언어의 도움말, 매뉴얼. |
| 설정 기본값(`config.dDefaults`) | 두 프로세스. 관리자 패널(`api_admin`), `configure.py`. 모듈의 설정은 여기에 없으며, 각 `module.json`에서 옵니다. |
| 설정 `mfa_enabled`(기본값 꺼짐) | `Accounts.mLoadSession`(켜면 2차 인증이 없는 계정의 비밀번호 세션이 즉시 종료됨), `fLogin`(step done, totp 또는 enroll), `/api/auth/session`, 설정, 사용자, 계정 뷰, `manage.py list-users`와 `create-user`, `configure.py`(`--enable-mfa` / `--disable-mfa`로만). |
| `frontend/assets/app.css` | SOC와 공유하는 모양: SOC의 스타일시트입니다. localSIEM 전용 규칙은 `localsiem.css`에 넣으며, 이 파일은 `app.css`를 건드리지 않고 다음을 합니다. SOC의 녹색 강조색을 PYMEHackers의 빨간색 `#cc3333`(두 테마 모두에서 강조 텍스트의 색이기도 함)으로, 오류 빨간색을 오류가 강조색과 혼동되지 않도록 주황빛 빨간색으로 바꾸는 것으로 시작하고, 로그인 페이지를 가운데 정렬된 양식만으로 배치하며(측면 패널이나 도구 모음 없음. 로그인 양식은 다른 로그인 카드의 절반 너비(`.auth-card-narrow`, 코드만 요청할 때의 코드 단계에도 적용되며, QR 코드가 있는 설정은 전체 너비 유지)이고, 버튼 아래에 언어와 테마가 있음, `.auth-preferences`), 설치된 모듈을 각각 전체 너비의 한 행으로 배치합니다(`.module-list`와 `.module-card`: 모듈 페이지의 머리글처럼 한 부분 아래에 다른 부분. `.module-title`은 행 `.module-head` 안에서만 24rem 기준을 사용하며, 열 안에서는 그것이 높이가 되므로 절대 사용하지 않음). 새 버전 안내(`.module-update`, 업데이트가 있는 정보 안내. 더 새로운 localSIEM이 필요하면 흐리게 표시되는 `.module-update-blocked`)도 포함합니다. 로고는 자체 로고입니다(`frontend/assets/img/logo.svg`: 세 개의 로그 줄 위의 돋보기. 두 줄은 해결되어 체크 표시가 있고, 한 줄은 아직 아무도 해결하지 않아 !가 있음). SOC의 방패가 아닙니다. |
| 설치 프로그램과 유닛 | 모든 서버: 정확히 하나의 동작을 요구하고, `--update`와 `--uninstall`을 반복 실행할 수 있으며, GitHub에서 파이프로 실행할 수 있고(함수, 마지막에 `fMain`, stdin을 읽는 것 없음), 코어만 설치하도록 유지하십시오. |
| `backend/core/terminal.py`와 설치 프로그램의 출력 함수(`fSplitOutput`, `fRun`, `fStep`) | `manage.py`, `configure.py`, 설치 프로그램이 출력하는 것과 설치 로그(색 코드 없음). `manage.py read-paths`(`fRemoveReadAccess`가 읽음)와 `doctor --json`은 프로그램을 위해 출력하므로 절대 표시나 색을 넣지 마십시오. 설치 프로그램이 실행하는 Python 도구는 출력한 것을 즉시 플러시하고(`fWrite`가 그렇게 함) `LOCALSIEM_COLOR`를 따라야 합니다. |
| `backend/core/channels.py`(`fChannelSettings`, `fBuildMessage`, `ChannelSender`)와 설정 `channels` | 관리자가 받는 메시지(Telegram), 채널 탭(`fChannelsGeneralSection`과 `fTelegramSection`은 `channels.status`와 `settings`를 읽음), `api_admin`(`cTokenRegex`, `cChatIdRegex`, `lSeverities`, `lLanguages`로 검증). SOC 전송은 이것에 의존하지 않으며, 실패한 채널이 알림을 붙잡아 두는 일은 없습니다. |

<a id="extensions"></a>
## 7. 확장 지점

### 모듈을 추가하는 방법(SSH, Postfix, MariaDB...)

코어는 바뀌지 않습니다. 수집기에 등록할 것도 없고 `config.dDefaults`에 기본값을 넣을 것도 없습니다.

1. `localSIEM-modules/mod-<name>/` 폴더를 만드십시오(이름: `[a-z][a-z0-9_]{1,31}`. 접두사 `mod-`는 저장소의 폴더에만 붙으며, `id`, `vName`, 설정, URL, 옵션, 설치된 폴더 `/opt/localsiem/modules/<name>/`은 `<name>`을 사용). 폴더에는 `module.json`(`id`, `version`, `core`, `entry`, `default_enabled`, `read_paths`, `settings`. [코어와 모듈](#architecture)과 [backend/core/registry.py](../backend/core/registry.py)의 머리글 참조)이 있어야 합니다.
2. `entry`에 지정한 `Module`의 하위 클래스를 작성하십시오([backend/core/module.py](../backend/core/module.py)): id와 같은 `vName`(`<name>`), `mDiscover`(고정된 `key`를 가진 소스. 설정은 `mModuleSettings()`로 읽음), `mCreateFramer`(보통 `LineFramer`), `mParse`(시각, 상관관계, parse_status, 필드, 마스킹된 원본이 있는 레코드), `mCreateCorrelator`(`mAdd`, `mDue(pNow, pForce, pWatermark)`, `mPendingCount`가 있는 객체), `mBuildEvent`(`action`과 `detections`가 있는 이벤트 dict), 그리고 선택적으로 `mStart`, `mRulesPath`, `mRuleFunctions`, `mEnrich`, `mDoctor`, `mRequirements`, `mHealth`, `mSkipped`, `mSetLowDisk`, `mDisplayRecord`. 모듈 자체의 파일은 상대 경로로(`from .parsers import ...`), 코어는 `backend.core.*`로 가져오십시오. `__init__.py`는 추가하지 마십시오.
3. 15개 언어(`lLanguages`) 각각에 대해 `locales/<language>.json`을 추가하십시오: `name`, `summary`, `settings.<key>.label` / `help`(`records`에는 `fields`, `add`, `remove`, `empty`도), `choices`.
4. YAML 규칙을 `mod-<name>/rules/`에 넣고 `mRulesPath`에서 그 폴더를 반환하십시오.
5. 서비스에서 «수행된 조치»가 무엇을 뜻하는지 정하고(예: fail2ban이 차단한 IP) 그에 맞게 `action`을 설정하십시오. 조치가 취해지지 않은 이벤트만 탐지를 만듭니다.
6. 모듈에 서버의 소프트웨어(감시하는 서비스)가 필요하면, `mDoctor`의 검사와 같은 형태의 검사(`fix`에 설치 명령 포함)로 `mRequirements`에서 반환하십시오. 스토리지를 사용하지 않고, 아무것도 설치하지 않으며, `/opt/localsiem/` 밖의 어떤 것도 변경하지 않아야 합니다. 그 소프트웨어가 없으면 모듈은 꺼진 상태로 설치되며, 재구성이 그것을 찾을 때까지 켤 수 없습니다.
7. 로그 폴더를 `read_paths`에 선언하여 `manage.py setup-modules`(웹이 보여 주는 root용 명령이며, 설치 프로그램도 업데이트할 때마다 실행함)가 `localsiem`에게 읽기 권한을 부여하게 하십시오. 서비스의 로그나 그 기록 방식, 형식을 절대 변경하지 마십시오. 있는 그대로 읽고 파서를 맞추십시오. 진단은 로그를 설명하며, 로그가 아닌 것과 읽기 권한에 대해서만 `fix`를 제공합니다. 모듈에 필요한 소프트웨어를 Debian과 Alpine에 설치하는 명령은 `install_requirements`에 선언하고(한 줄에 명령 하나, 셸 연산자 없이), 그 참고 사항은 로캘에 넣으십시오(`install_requirements.note`와 `install_requirements.<system>`). 웹은 이를 모듈 › 설치 가능 › 요구 사항에 보여 주기만 하고 절대 실행하지 않습니다.
8. `localSIEM-modules` 저장소(`mod-<name>/` 폴더)에 게시하십시오. 설치되지 않은 동안 모듈 › 설치 가능에 나타나며, 이것이 설치하는 유일한 방법입니다(개발용 사본에서는 폴더를 `/opt/localsiem/modules/<name>/`에 복사하고 `localsiem`과 `localsiem-web`을 다시 시작할 수 있음). 새 버전을 게시하려면 `module.json`의 `version`을 올리십시오. 모듈 › 설치됨이 업데이트로 이를 제공합니다(`core`도 설치된 localSIEM보다 높게 올리면 필요한 localSIEM만 알려 줌). 새 버전이 `read_paths`를 바꾸면 웹은 업데이트 후 root용 명령을 다시 보여 줍니다.

### 모듈에 설정을 추가하는 방법

`module.json`의 `settings`에 추가하고(유형과 기본값) 레이블과 도움말을 로캘 파일에 추가하십시오. 값은 `mModuleSettings()`로 읽습니다. 웹이 필드를 만들고, `fValidateSettings`가 값을 확인하며, 수집기는 다음 다시 불러오기에서 즉시 적용합니다.

### 규칙을 추가하는 방법

모듈의 `rules/` 폴더에 YAML 파일을 만드십시오(모든 키와 연산자는 [backend/core/rules.py](../backend/core/rules.py)의 머리글 참조). 예:

```yaml
id: apache-xmlrpc-burst
name: "Apache: burst of XML-RPC calls"
category: bruteforce
type: authentication
severity: medium
kind: threshold
when:
  method: POST
  path: /xmlrpc.php
  action: none
by: [ip, vhost]
window: 60
threshold: 30
description: "{count} POST requests from {ip} to /xmlrpc.php of {vhost} in {window} seconds."
search: "ip:{ip:q} path:/xmlrpc.php"
```

수집기는 다음 시작이나 설정 다시 불러오기에서 이 파일을 불러옵니다. 그러면 모듈 페이지(관리 › 모듈 › 설치됨 › 구성)의 규칙 표에 나타나며, 거기에서 규칙을 끄거나 심각도, 임계값, 기간을 조정할 수 있습니다(재정의는 `settings.json`의 `rules.<id>` 아래에 저장). 파일의 `enabled: false`는 규칙을 기본적으로 끕니다. 코드가 필요한 조건은 모듈의 `mRuleFunctions`가 반환하는 함수와 함께 `{function: name}`을 사용합니다.

### 검색 필드를 추가하는 방법

[backend/core/query.py](../backend/core/query.py)의 `dFields`와 [backend/core/storage_sqlite.py](../backend/core/storage_sqlite.py)의 `fCompileField`에 있는 `dTextColumns` / `dNumberColumns`(또는 특수한 경우)에 추가하십시오. 새 열에는 스키마, `lEventColumns`, 인덱스도 필요합니다. 도움말(네 로캘 파일의 `help.fields`)과 매뉴얼에 문서화하십시오.

### API 엔드포인트나 대시보드 탭을 추가하는 방법

엔드포인트는 해당 영역의 `fRegister*` 함수에서 `/api/` 아래에 둡니다(Swagger가 문서화함). 탭에는 `lUserTabs` 및/또는 `lAdminTabs`의 라우트([backend/web/app.py](../backend/web/app.py)), `ldTabs`의 항목([frontend/assets/app.js](../frontend/assets/app.js). `group`, `adminGroup`, `adminOnly`), `window.LocalsiemViews`의 뷰(새 스크립트는 `frontend/index.html`에 추가해야 함), 네 로캘 파일의 텍스트(`nav.<tab>`과 뷰의 키)가 필요합니다. 사용자와 모듈처럼 섹션이 있는 탭에는 `app.py`와 `app.js`의 섹션 목록(`lUserSections`, `lChannelSections`, `lModuleSections`), `fAdminTab`에서 탭을 첫 번째 섹션으로 보내는 리디렉션, 섹션의 라우트(`fAdminUsersSection`, `fAdminChannelsSection`, `fAdminModulesSection`), `fRoute`의 해당 경우, 뷰의 하위 탭(`fUserSections`, `fChannelSections`, `fModuleSections`)도 필요합니다.

### 채널을 추가하는 방법(이메일, Slack...)

[backend/core/channels.py](../backend/core/channels.py)에서: `lChannels`에 이름을, `dDefaults["channels"]`에 블록을 추가하고([backend/core/config.py](../backend/core/config.py). 비밀 값은 `settings.json`이 아니라 `config/`의 자체 파일(모드 600)에 저장), `fChannelSettings`, `ChannelSender.mConfigured`, `ChannelSender.mDeliver`에 해당 경우를 추가하십시오(`TelegramClient` 같은 클라이언트이며, 오류에 비밀 값이 절대 담기지 않아야 함). 그다음 `api_admin.py`의 API(`fSaveTelegram`과 `fTestTelegram`처럼), `app.py`, `app.js`, `admin.js`의 `lChannelSections`에 있는 섹션과 그 뷰(`fTelegramSection`처럼), 네 로캘 파일의 텍스트 `channels.section_<name>`과 뷰의 텍스트, 매뉴얼의 해당 부분을 추가하십시오. 일반 섹션은 채널을 저절로 나열합니다(`GET /api/admin/channels`의 `channels`).

<a id="resources"></a>
## 8. 측정된 리소스 사용량

Apache 모듈을 사용하는 Debian 13 서버(mod_security2 2.9.11, CRS 3.3.7)에서 유닛의 systemd 제한(`MemoryMax` 300M / 200M, `CPUQuota` 50 %, `Nice` 10, 유휴 I/O)을 적용하여 측정했습니다:

| 상황 | 수집기(RSS) | 웹(RSS) | 합계 |
|---|---|---|---|
| 유휴, 시작 후 | ≈ 28 MB | ≈ 26–55 MB | ≈ 55–80 MB |
| 약 60초 동안 요청 30 000개가 한꺼번에 발생, **모든 요청**에 감사 레코드 있음(파트 K 때문에 감사 로그 ≈ 1.8 GB) | 최대 ≈ 160 MB | ≈ 40 MB | 최대 ≈ 200 MB |
| 한꺼번에 발생한 요청 이후 | ≈ 70 MB | ≈ 26–40 MB | ≈ 100 MB |

그 동안 수집기는 마지막 요청 후 약 40초 만에 따라잡았고, 요청마다 정확히 하나의 이벤트를 저장했으며(30 000개 중 30 000개, 모두 세 소스 포함), 알림 그룹을 수천 개가 아니라 세 개만 보냈습니다. 유휴 상태의 Alpine 3.24: 수집기 ≈ 26 MB, 웹 ≈ 54 MB.

디스크: 일치가 없는 요청은 약 0.8 KB(액세스 줄, 이벤트, 인덱스), 감사 레코드와 error.log의 ModSecurity 줄 여러 개가 있는 요청은 약 10–13 KB입니다. 하루에 수만 건의 요청을 받고 그중 몇 퍼센트가 감사되는 일반적인 PYME 사이트는 90일 보존 기간 동안 기본 최대 크기(디스크의 15 %와 10 GB 중 작은 값) 안에 넉넉히 머뭅니다. 최대 크기에 도달하면 가장 오래된 이벤트부터 삭제됩니다.
