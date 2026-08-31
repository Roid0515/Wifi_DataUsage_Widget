# Wi-Fi Data Usage Widget for macOS

현재 Wi-Fi 연결 세션에서 사용한 RX(다운로드), TX(업로드), 총 바이트를 표시하는 macOS 메뉴바 앱과 Small Widget입니다. 패킷을 캡처하지 않고 macOS 네트워크 인터페이스 누적 카운터만 사용하며, 측정값은 Mac의 App Group 컨테이너에만 저장됩니다.

## 구성

- `WiFiUsageApp`: 5초 간격으로 측정하는 메뉴바 앱, 설정, 세션 초기화, 로그인 시 실행
- `WiFiUsageCore`: CoreWLAN 인터페이스 탐색, `getifaddrs()` 카운터 조회, 세션 계산, 공유 저장, 단위 포맷
- `WiFiUsageWidget`: 공유 Snapshot을 읽는 `systemSmall` 표시 전용 Widget Extension
- `WiFiUsageTests`: 세션 전환/복원 및 ByteFormatter 단위 테스트

최소 지원 버전은 macOS 14 Sonoma입니다. 외부 패키지, 서버 통신, 텔레메트리, 관리자 권한, 패킷 캡처 또는 Network Extension을 사용하지 않습니다. 샌드박스 환경에서 CoreWLAN 인터페이스 정보를 읽기 위해 메인 앱에 Outgoing Connections entitlement가 포함되지만, 앱 자체는 외부 연결을 생성하지 않습니다.

## Xcode에서 실행

1. `WiFiUsage.xcodeproj`를 Xcode로 엽니다.
2. 프로젝트의 `WiFiUsageApp`과 `WiFiUsageWidget` 타깃에서 같은 Development Team을 선택합니다.
3. 두 타깃의 App Groups capability에 같은 그룹을 지정합니다.
4. `WiFiUsage` 스킴으로 앱을 빌드하고 실행합니다.
5. macOS 위젯 갤러리에서 **Wi-Fi Usage** Small Widget을 추가합니다.

기본 식별자는 다음과 같습니다.

```text
App:       local.wifiusage.app
Widget:    local.wifiusage.app.widget
App Group: ZA5PPDLD8T.local.wifiusage
```

현재 App Group은 Personal Team ID를 접두사로 사용해 macOS가 앱과 위젯을 같은 그룹 구성원으로 판별하도록 설정했습니다. 다른 팀으로 서명한다면 `<Team ID>.local.wifiusage` 형식으로 바꾸고 아래 세 곳을 동일하게 수정해야 합니다.

- `WiFiUsageCore/Models/WiFiUsageModels.swift`
- `Resources/WiFiUsageApp.entitlements`
- `Resources/WiFiUsageWidget.entitlements`

Bundle Identifier도 개발자 계정에서 고유한 값으로 변경할 수 있습니다. 앱을 `/Applications`에 복사해 실행한 뒤 **Launch at Login**을 켜는 것이 가장 안정적입니다.

## CLI 빌드 및 테스트

서명 없이 컴파일을 확인하려면:

```sh
xcodebuild \
  -project WiFiUsage.xcodeproj \
  -scheme WiFiUsage \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

테스트 실행:

```sh
xcodebuild \
  -project WiFiUsage.xcodeproj \
  -scheme WiFiUsage \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 동작 방식

앱은 CoreWLAN이 알려주는 현재 Wi-Fi 인터페이스 이름을 사용하므로 `en0`을 하드코딩하지 않습니다. 연결 시작 시 인터페이스의 `ifi_ibytes`와 `ifi_obytes`를 baseline으로 저장하고 이후 값과의 안전한 차이를 현재 세션 사용량으로 계산합니다.

다음 경우 새 세션을 0 B부터 시작합니다.

- 연결 해제 후 재연결
- SSID 또는 Wi-Fi 인터페이스 변경
- 시스템 재부팅
- raw 카운터 감소/초기화
- 사용자가 **Reset Current Session** 실행

SSID는 macOS 개인정보 정책에 따라 `nil`일 수 있습니다. 앱은 위치 권한을 요구하지 않으며 SSID를 읽을 수 없어도 인터페이스와 무선 링크 상태를 이용해 측정을 계속합니다.

## 백그라운드 및 위젯 갱신

메뉴바 앱이 실행 중일 때 5초마다 카운터를 읽습니다. 공유 Snapshot은 값이 변하거나 30초가 지났을 때만 저장합니다. 연결/해제 및 새 세션 전환은 위젯을 즉시 갱신하고, 일반적인 사용량 변화에 대한 WidgetKit reload 요청만 최소 60초 간격으로 제한합니다. Sleep에서 깨어날 때 즉시 상태를 다시 확인합니다.

WidgetKit의 시스템 정책 때문에 위젯 화면은 초 단위 실시간 갱신을 보장하지 않습니다. 위젯은 마지막 저장값을 안정적으로 표시하고 자체 Timeline은 1분 후 갱신을 요청합니다. 정확한 최신값은 메뉴바 패널에서 확인할 수 있습니다.

개발 중에는 서로 다른 Derived Data 경로에서 서명된 앱을 동시에 실행하지 마세요. 동일한 앱/위젯 Bundle Identifier가 여러 경로에 등록되면 macOS가 갤러리 프리뷰와 바탕화면 위젯에 서로 다른 확장 복제본을 선택할 수 있습니다. Xcode에서 실행하는 동안에는 다른 빌드 결과의 `WiFi Usage.app`을 종료해 두는 것이 안전합니다.

## 수동 확인 목록

- Wi-Fi 연결 직후 0 B 근처에서 시작하는지 확인
- 다운로드 시 RX/Total, 업로드 시 TX/Total이 증가하는지 확인
- Wi-Fi 해제 시 Disconnected 표시 확인
- 다른 SSID 연결 시 새 세션 확인
- Sleep/Wake 및 재부팅 뒤 값이 음수나 비정상적으로 커지지 않는지 확인
- 세션 초기화가 네트워크를 끊지 않고 0 B로 재설정하는지 확인
- Launch at Login과 위젯 추가/표시 확인
