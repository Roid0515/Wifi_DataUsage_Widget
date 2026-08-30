# macOS Wi‑Fi 연결 세션 데이터 사용량 위젯 개발 작업지시서

## 1. 프로젝트 개요

macOS에서 현재 연결된 Wi‑Fi의 **이번 연결 세션 동안 발생한 네트워크 데이터 사용량**을 측정하고, macOS 데스크탑에 **WidgetKit 위젯**으로 표시하는 개인용 유틸리티를 개발한다.

사용자가 확인하고 싶은 핵심 정보는 다음과 같다.

- 현재 Wi‑Fi 연결 상태
- 현재 Wi‑Fi 연결 세션에서 사용한 총 데이터 용량
- 다운로드(RX) 사용량
- 업로드(TX) 사용량
- 필요 시 현재 SSID 및 연결 지속시간

모든 측정 및 저장은 로컬 Mac에서 수행한다. 외부 서버, 클라우드, 텔레메트리, 광고 SDK는 사용하지 않는다.

---

## 2. 최우선 요구사항

1. macOS 네이티브 앱으로 개발한다.
2. 첨부 캡처의 날씨 위젯과 동일한 계열의 크기로 데스크탑 위젯을 제공한다.
   - WidgetKit 기준 `WidgetFamily.systemSmall`을 우선 구현한다.
   - Retina 캡처에서는 약 300px 이상으로 보일 수 있으나 실제 논리 크기는 macOS 시스템 Small Widget 규격을 따른다.
3. 위젯 중앙에 현재 연결 세션의 **총 데이터 사용량을 가장 큰 숫자**로 표시한다.
4. 데이터 사용량은 현재 연결된 Wi‑Fi 인터페이스의 RX/TX 누적 바이트 카운터를 기준으로 계산한다.
5. 새로운 Wi‑Fi 연결이 시작되면 사용량 기준값을 새로 잡아 `0 B`부터 계산한다.
6. Wi‑Fi가 끊기거나 다른 SSID로 변경되면 기존 세션을 종료하고 새 세션을 생성한다.
7. 관리자 권한, root 권한, 패킷 캡처, VPN 프로파일, Network Extension 설치를 요구하지 않는 방향으로 구현한다.
8. 앱이 실행 중이지 않더라도 가능한 한 지속적으로 사용량을 추적할 수 있도록 **경량 백그라운드 동작 구조**를 포함한다.
9. 위젯은 macOS WidgetKit의 갱신 정책 한계 때문에 초 단위 실시간 표시를 보장하지 않는다. 대신 마지막 측정값을 안정적으로 저장하고 WidgetKit에 갱신을 요청하는 방식으로 구현한다.

---

## 3. 권장 개발 환경

### 언어 및 프레임워크

- Swift 6 계열
- SwiftUI
- WidgetKit
- CoreWLAN
- Network.framework 또는 SystemConfiguration
- Darwin / `getifaddrs()` 기반 네트워크 인터페이스 통계 조회
- ServiceManagement (`SMAppService`) — 로그인 시 자동 실행이 필요한 경우 사용

### 지원 OS

- 최소 지원: macOS 14 Sonoma 이상
- 주 테스트 환경: 최신 macOS

> 데스크탑 WidgetKit 위젯 사용이 핵심이므로 macOS Sonoma 이상을 기준으로 한다.

### 빌드 방식

- 정식 Xcode Project 구조 사용
- Codex는 가능하면 CLI 기반으로 파일 생성/수정 및 `xcodebuild` 빌드/테스트를 수행한다.
- Widget Extension, App Group, Entitlement 설정 때문에 단일 Swift Package만으로 끝내지 말고 Xcode Project를 구성한다.

---

## 4. 프로그램 구조

프로젝트는 아래 3개 역할로 분리한다.

### A. WiFiUsageApp

메인 macOS 앱.

역할:

- 초기 권한 및 상태 안내
- 현재 Wi‑Fi 정보 표시
- 현재 세션 사용량 표시
- 자동 실행 설정
- 단위 표시 설정
- 수동 세션 초기화 기능
- 백그라운드 모니터 동작 유지

앱은 대형 일반 창보다는 **가벼운 메뉴바 유틸리티 형태**를 우선한다.

가능하면 SwiftUI `MenuBarExtra`를 사용한다.

메뉴바에 표시할 내용 예시:

- Wi‑Fi 연결됨 / 연결 안 됨
- 총 사용량
- 다운로드
- 업로드
- 연결 시간
- `Reset Session`
- `Launch at Login`
- `Quit`

### B. WiFiUsageCore

네트워크 통계 계산 로직을 담는 공용 모듈.

역할:

- 현재 활성 Wi‑Fi 인터페이스 탐색
- Wi‑Fi 연결 여부 확인
- 인터페이스 이름 확인
- 현재 RX/TX 누적 바이트 조회
- 연결 세션 시작/종료 판단
- 기준 카운터와 현재 카운터 차이 계산
- 세션 상태 저장
- 바이트 단위 포맷 변환
- sleep / wake / reconnect 상황 처리

Widget Extension과 메인 앱 양쪽에서 재사용할 수 있도록 UI 코드와 분리한다.

### C. WiFiUsageWidget

WidgetKit Extension.

역할:

- 공유 컨테이너에 저장된 최신 사용량을 읽어서 표시
- 직접 패킷을 감시하거나 지속 측정하지 않는다.
- 측정은 메인 앱/백그라운드 모니터가 담당하고 위젯은 표시 전용으로 설계한다.

---

## 5. Wi‑Fi 데이터 측정 방식

### 5.1 기본 원칙

패킷 하나하나를 캡처하지 말고 macOS가 관리하는 **네트워크 인터페이스 누적 바이트 카운터**를 사용한다.

현재 Wi‑Fi 인터페이스의 값:

- RX bytes: 수신한 누적 바이트
- TX bytes: 송신한 누적 바이트

연결 세션 시작 시 값을 저장한다.

예:

```text
sessionStartRX = 125,000,000
sessionStartTX =  45,000,000
```

현재 값이 아래와 같다면:

```text
currentRX = 425,000,000
currentTX =  95,000,000
```

계산 결과:

```text
sessionRX = 300,000,000 bytes
sessionTX =  50,000,000 bytes
sessionTotal = 350,000,000 bytes
```

### 5.2 인터페이스 탐색

`en0`을 하드코딩하지 않는다.

CoreWLAN 등을 통해 현재 Wi‑Fi 인터페이스 이름을 얻은 뒤, 해당 인터페이스의 통계를 조회한다.

예상 구현 후보:

- `CWWiFiClient.shared().interface()`
- `CWInterface.interfaceName`
- `getifaddrs()`
- `if_data.ifi_ibytes`
- `if_data.ifi_obytes`

구현 시 현재 macOS SDK에서 사용 가능한 가장 안정적인 public API를 선택한다.

### 5.3 세션 판정 기준

다음 상황에서 새 세션을 시작한다.

- Wi‑Fi가 미연결 → 연결 상태로 변경
- SSID가 변경됨
- Wi‑Fi 인터페이스 자체가 변경됨
- 시스템 재부팅 후 이전 카운터와 현재 카운터가 논리적으로 이어질 수 없음
- 현재 RX/TX 카운터가 저장된 시작값보다 작아짐

세션 종료 조건:

- Wi‑Fi 연결 해제
- 다른 Wi‑Fi로 연결
- 사용자가 `Reset Session` 실행

### 5.4 절전 / 화면 잠금 / Wake 처리

Mac이 sleep 상태에 들어갔다가 wake 했을 때:

1. 현재 Wi‑Fi 상태를 다시 확인한다.
2. 인터페이스 카운터 유효성을 검증한다.
3. 동일 세션으로 안전하게 이어갈 수 있으면 계속 누적한다.
4. 카운터 초기화나 Wi‑Fi 재연결이 확인되면 새 세션으로 처리한다.

카운터 차이가 음수가 되는 경우 절대 음수 사용량을 표시하지 않는다.

---

## 6. 데이터 저장 구조

메인 앱과 Widget Extension이 동일한 데이터를 읽을 수 있도록 **App Group**을 사용한다.

예시 App Group:

```text
group.local.wifiusage
```

실제 Bundle Identifier에 맞춰 변경 가능하게 구성한다.

### 저장 항목 예시

```swift
struct WiFiUsageSnapshot: Codable {
    let isConnected: Bool
    let interfaceName: String?
    let ssid: String?
    let sessionID: UUID
    let sessionStartedAt: Date?
    let lastUpdatedAt: Date
    let rxBytes: UInt64
    let txBytes: UInt64
    let totalBytes: UInt64
}
```

추가로 내부 상태에는 다음을 저장한다.

```text
baselineRxBytes
baselineTxBytes
lastRawRxBytes
lastRawTxBytes
lastKnownSSID
lastKnownInterface
```

### 저장 방식

MVP에서는 App Group 공유 컨테이너에 Codable JSON 파일 또는 App Group UserDefaults를 사용한다.

권장:

- 현재 Snapshot: App Group UserDefaults
- 향후 History 기능이 필요하면 SQLite로 확장

이번 버전에서 데이터베이스를 과도하게 도입하지 않는다.

---

## 7. 백그라운드 측정 정책

Wi‑Fi 데이터 사용량을 정상적으로 측정하려면 Widget Extension만으로는 부족하므로 메인 앱 또는 경량 에이전트가 백그라운드에서 동작하도록 한다.

### 권장 방식

- 메뉴바 앱을 실행 상태로 유지
- `Launch at Login` 기본 제공
- `SMAppService`를 활용해 사용자가 로그인 시 자동 실행 선택 가능

### 측정 주기

권장 초기값:

```text
5초
```

단, CPU 점유율과 배터리 소모를 확인한 뒤 5~10초 범위에서 조정 가능하다.

중요:

- 매번 파일을 과도하게 쓰지 않는다.
- raw 카운터는 5초마다 읽어도, 공유 Snapshot 저장은 값 변화 또는 적절한 간격에 맞춰 수행할 수 있다.
- WidgetKit reload 요청을 매 측정마다 호출하지 않는다.

### 목표 리소스 사용량

유휴 상태 기준:

- CPU: 사실상 0%에 가까운 수준
- 메모리: 수십 MB 이하 목표
- 네트워크 자체 발생량: 외부 통신 없음

---

## 8. WidgetKit 갱신 전략

WidgetKit은 일반 앱 UI처럼 초 단위 실시간 갱신을 보장하지 않는다.

따라서 다음 전략을 사용한다.

1. 백그라운드 앱이 최신 사용량 Snapshot을 App Group에 저장
2. 의미 있는 변경 시 `WidgetCenter.shared.reloadTimelines(ofKind:)` 요청
3. Timeline Provider에서도 주기적 갱신 Entry 제공
4. 위젯에는 `마지막 업데이트` 시간을 작게 표시할 수 있게 구현

WidgetKit 시스템 정책에 의해 갱신 요청이 지연 또는 제한될 수 있으므로 README에 이 내용을 명확히 적는다.

---

## 9. 위젯 UI 상세 요구사항

### 9.1 크기

첨부 캡처의 날씨 위젯과 같은 **Small Widget** 크기를 사용한다.

```swift
.supportedFamilies([.systemSmall])
```

초기 버전은 `systemSmall`에 집중한다.

향후 필요 시 `systemMedium`을 추가할 수 있도록 UI 컴포넌트는 재사용 가능하게 만든다.

### 9.2 디자인 방향

macOS 기본 위젯과 자연스럽게 어울리는 디자인으로 한다.

사용자 지정 테두리나 과한 그림자는 사용하지 않는다.

시스템 Widget Container 스타일을 따른다.

### 9.3 표시 순서

권장 레이아웃:

```text
┌────────────────────┐
│ Wi‑Fi 사용량       │
│ HOME_5G            │
│                    │
│      1.42 GB       │  ← 가장 크게 표시
│                    │
│ ↓ 1.18 GB ↑ 240 MB│
│ 연결 2시간 16분    │
└────────────────────┘
```

공간이 부족하면 SSID 또는 연결시간을 줄이고 **총 데이터 사용량 숫자를 최우선**으로 유지한다.

### 9.4 미연결 상태

Wi‑Fi가 연결되어 있지 않으면:

```text
Wi‑Fi 사용량

연결 안 됨

0 B
```

또는 Wi‑Fi 아이콘과 함께 간단히 표시한다.

### 9.5 숫자 표기

자동 단위 변환:

```text
0 ~ 999 B       → B
1 KB ~ 999 KB   → KB
1 MB ~ 999 MB   → MB
1 GB 이상       → GB
```

네트워크 사용량 표시는 decimal 기준을 우선한다.

```text
1 KB = 1,000 bytes
1 MB = 1,000,000 bytes
1 GB = 1,000,000,000 bytes
```

내부 저장값은 항상 `UInt64 bytes`로 유지한다.

예:

```text
824 MB
1.42 GB
12.8 GB
```

---

## 10. SSID 권한 및 개인정보 처리

macOS 버전/보안 정책에 따라 SSID 접근이 제한될 수 있다.

SSID 획득이 불가능하더라도 앱의 핵심 기능이 중단되면 안 된다.

SSID 접근 실패 시:

```text
Wi‑Fi 연결됨
```

정도로 표시하고 인터페이스 기준으로 세션을 관리한다.

불필요한 위치 정보 권한 요청은 하지 않는다.

단, 최신 macOS에서 SSID 조회를 위해 공식적으로 필요한 권한이 있다면:

- 필요 사유를 README에 설명
- 최소 권한만 요청
- 권한 거부 시에도 사용량 측정은 계속 가능하도록 fallback 구현

---

## 11. 앱 설정 화면

최소한 다음 옵션을 제공한다.

### General

- `Launch at Login`
- `Show SSID in Widget`
- `Show RX/TX in Widget`
- `Reset Current Session`

### Unit

기본값:

```text
Auto
```

선택 가능:

- Auto
- MB
- GB

단, 내부 값은 항상 bytes.

---

## 12. 세션 초기화 동작

사용자가 `Reset Current Session`을 실행하면 현재 시점의 raw RX/TX 카운터를 새로운 baseline으로 저장한다.

즉, Wi‑Fi 연결 자체를 끊지 않아도 사용량이 `0 B`부터 다시 시작한다.

확인창 문구 예시:

```text
현재 Wi‑Fi 세션의 사용량 기준값을 초기화할까요?
네트워크 연결은 끊어지지 않습니다.
```

---

## 13. 오류 및 예외 처리

아래 상황을 반드시 처리한다.

1. Wi‑Fi 미연결
2. Wi‑Fi가 꺼져 있음
3. 인터페이스 이름 변경
4. SSID를 읽을 수 없음
5. 시스템 sleep/wake
6. OS 재부팅
7. 인터페이스 카운터 리셋
8. 카운터 값 감소
9. 앱 강제 종료 후 재실행
10. Widget Extension만 실행된 상태
11. App Group 데이터 손상 또는 파일 없음
12. 최초 실행

오류가 발생해도 위젯이 crash하지 않도록 기본 Snapshot을 사용한다.

---

## 14. 코드 품질 요구사항

- 강제 unwrap 최소화
- 비즈니스 로직과 UI 로직 분리
- 네트워크 카운터 조회 코드를 Protocol 기반으로 분리해 테스트 가능하게 구성
- `UInt64` overflow 방어
- 음수 차이 계산 방지
- 파일/설정 저장은 atomic하게 처리
- 의미 없는 싱글톤 남발 금지
- 외부 패키지는 꼭 필요한 경우가 아니면 사용 금지

예시 Protocol:

```swift
protocol NetworkCounterProviding {
    func currentCounters(for interfaceName: String) throws -> InterfaceCounters
}
```

이를 실제 구현과 Mock 구현으로 분리한다.

---

## 15. 권장 디렉터리 구조

```text
WiFiUsage/
├── WiFiUsage.xcodeproj
├── WiFiUsageApp/
│   ├── App/
│   ├── MenuBar/
│   ├── Settings/
│   └── Resources/
├── WiFiUsageCore/
│   ├── Models/
│   ├── Networking/
│   │   ├── WiFiInterfaceProvider.swift
│   │   ├── InterfaceCounterProvider.swift
│   │   └── WiFiSessionMonitor.swift
│   ├── Storage/
│   │   └── SharedSnapshotStore.swift
│   └── Formatting/
│       └── ByteFormatter.swift
├── WiFiUsageWidget/
│   ├── WiFiUsageWidget.swift
│   ├── WiFiUsageProvider.swift
│   └── WiFiUsageWidgetView.swift
├── WiFiUsageTests/
│   ├── SessionMonitorTests.swift
│   ├── ByteFormatterTests.swift
│   └── CounterResetTests.swift
└── README.md
```

실제 Xcode Target 구성에 맞게 디렉터리는 조정 가능하다.

---

## 16. 테스트 요구사항

### Unit Test

반드시 아래 테스트를 작성한다.

#### 정상 누적

```text
baseline RX 100 / TX 50
current  RX 300 / TX 100
→ RX 200 / TX 50 / TOTAL 250
```

#### 카운터 감소

```text
baseline RX 1000
current  RX 100
```

→ 음수 사용량을 만들지 않고 새 baseline 처리.

#### SSID 변경

```text
WiFi_A → WiFi_B
```

→ 새로운 sessionID 생성 및 0부터 시작.

#### 연결 해제 후 재연결

→ 새 세션 시작.

#### 앱 재실행

→ 저장된 세션 정보를 안전하게 복구.

#### ByteFormatter

B / KB / MB / GB 경계값 테스트.

### Manual Test

1. Wi‑Fi 연결 직후 값이 거의 0부터 시작하는지 확인
2. 대용량 파일 다운로드
3. 위젯의 RX와 Total 증가 확인
4. 업로드 수행
5. TX 증가 확인
6. Wi‑Fi 연결 해제
7. 위젯 미연결 상태 확인
8. 다른 SSID 연결
9. 새 세션으로 초기화되는지 확인
10. Mac sleep → wake 테스트
11. 재부팅 후 정상 동작 확인
12. Login Item 활성화 상태 확인

---

## 17. 완료 기준 / Acceptance Criteria

다음 조건을 모두 만족해야 작업 완료로 판단한다.

- [ ] macOS 앱이 정상 빌드됨
- [ ] Widget Extension이 정상 빌드됨
- [ ] 위젯이 macOS 데스크탑 위젯 목록에 나타남
- [ ] `systemSmall` 위젯을 데스크탑에 추가할 수 있음
- [ ] 현재 Wi‑Fi 연결 상태를 식별함
- [ ] 현재 Wi‑Fi 인터페이스를 하드코딩하지 않고 탐색함
- [ ] 연결 세션 시작 시 RX/TX baseline을 생성함
- [ ] 사용량 = 현재 카운터 - baseline으로 정확히 계산됨
- [ ] RX / TX / Total을 bytes 기반으로 저장함
- [ ] KB / MB / GB 자동 단위 변환이 정상 동작함
- [ ] Wi‑Fi 변경 시 새 세션으로 초기화됨
- [ ] Wi‑Fi 해제 시 미연결 상태가 표시됨
- [ ] sleep/wake 후 음수 또는 비정상적으로 큰 값이 발생하지 않음
- [ ] 위젯에서 총 사용량 숫자가 가장 크게 표시됨
- [ ] Widget Extension과 앱이 App Group 데이터 공유에 성공함
- [ ] `Launch at Login` 설정이 정상 동작함
- [ ] 외부 서버로 데이터를 보내지 않음
- [ ] 관리자/root 권한이 필요 없음
- [ ] Packet Capture 또는 Network Extension을 사용하지 않음
- [ ] 핵심 계산 로직에 Unit Test가 존재함
- [ ] README에 설치/실행/권한/WidgetKit 갱신 한계가 설명됨

---

## 18. 구현 우선순위

### Phase 1 — Core Prototype

1. 현재 Wi‑Fi 인터페이스 탐색
2. RX/TX 누적 바이트 조회
3. 콘솔에 현재 raw bytes 출력
4. 세션 baseline 계산
5. 5초 주기 사용량 출력

이 단계에서 정확한 측정이 확인되기 전에는 Widget UI를 먼저 만들지 않는다.

### Phase 2 — Persistence

1. 현재 세션 모델 구현
2. App Group 설정
3. Snapshot 저장/복원
4. 재실행 테스트

### Phase 3 — Widget

1. Widget Extension 추가
2. `systemSmall` UI 구현
3. 총 사용량 대형 숫자 표시
4. RX/TX 표시
5. 미연결 상태 구현

### Phase 4 — Background / Login

1. 메뉴바 앱 구성
2. 백그라운드 모니터 안정화
3. Login Item 구현
4. sleep/wake 처리

### Phase 5 — Tests / Polish

1. Unit Test
2. 에러 처리
3. Widget 갱신 최적화
4. README
5. Release 빌드

---

## 19. Codex 작업 원칙

Codex는 아래 원칙을 지킨다.

1. 먼저 최신 macOS SDK 기준으로 사용 가능한 public API를 확인한다.
2. 비공개 API는 사용하지 않는다.
3. 관리자 권한이 필요한 구현은 피한다.
4. Wi‑Fi 인터페이스를 `en0`으로 하드코딩하지 않는다.
5. SSID 조회 실패가 전체 앱 실패로 이어지지 않게 한다.
6. WidgetKit을 초 단위 실시간 UI처럼 구현하려 하지 않는다.
7. 핵심 측정 로직을 Widget Extension 내부에 넣지 않는다.
8. 기능이 작으므로 불필요한 DB, 서버, REST API, 로그인 기능을 추가하지 않는다.
9. 외부 라이브러리 의존성을 최소화한다.
10. 각 Phase 완료 시 빌드와 테스트를 수행하고 오류를 해결한 뒤 다음 Phase로 넘어간다.
11. 최종적으로 `xcodebuild` 기반 Debug/Release 빌드가 성공해야 한다.
12. TODO나 임시 mock 값이 남은 상태로 완료 처리하지 않는다.

---

## 20. 최종 산출물

Codex는 최종적으로 아래 항목을 제공한다.

```text
1. 전체 Xcode 프로젝트 소스
2. WiFiUsageApp Target
3. WiFiUsageWidget Extension Target
4. App Group / Entitlement 설정
5. Unit Test
6. README.md
7. 빌드 방법
8. 실행 및 위젯 추가 방법
9. Launch at Login 설정 방법
10. 알려진 WidgetKit 갱신 제한 설명
```

README에는 최소한 다음 내용을 포함한다.

```text
- 개발 환경
- 최소 macOS 버전
- 빌드 방법
- 실행 방법
- 위젯 추가 방법
- 데이터 측정 방식
- 앱을 종료하면 측정 정확도가 떨어질 수 있는 이유
- WidgetKit이 실시간 갱신을 보장하지 않는 이유
- 개인정보 및 외부 전송 없음
```

---

## 21. 구현 시 가장 중요한 판단 기준

이 프로그램의 핵심은 화려한 UI가 아니라 아래 3가지다.

1. **현재 Wi‑Fi 연결 세션의 실제 RX/TX 사용량을 안정적으로 계산하는 것**
2. **Mac을 재우거나 깨우고, Wi‑Fi를 바꾸더라도 비정상적인 값이 나오지 않는 것**
3. **macOS 기본 날씨 위젯과 유사한 크기의 Small Widget에서 사용량 숫자를 한눈에 볼 수 있는 것**

따라서 개발 우선순위는 다음과 같이 유지한다.

```text
측정 정확도 > 세션 안정성 > 백그라운드 동작 > 위젯 가독성 > 부가 기능
```

