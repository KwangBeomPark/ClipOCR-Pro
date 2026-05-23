# 📸 ScreenClip Tool v1 (Dynamic Screenshot & OCR Automation Suite)

<p align="center">
  <img src="demo.gif" width="900">
</p>
An advanced, production-ready productivity tool built with **AutoHotkey v2** and **GDI+ (Graphics Device Interface)**. Unlike standard snipping utilities, ScreenClip Tool creates interactive, floating, always-on-top screenshot windows that support real-time annotation (drawing/highlighting with undo support), dynamic image scaling, layout cascade sorting across multi-monitor setups, and advanced multilingual OCR (Optical Character Recognition) with automated browser translation fallbacks.

AutoHotkey v2와 GDI+를 기반으로 구현된 고성능 화면 캡처 및 OCR 업무 자동화 툴입니다. 일반적인 캡처 도구와 달리 캡처한 이미지를 독립된 플로팅 항상-위 창으로 띄우며, 실시간 주석 그리기(Undo 지원), 이미지 스케일링, 다중 모니터 정렬, 다국어 OCR 판독 및 브라우저 연동 자동 번역 등 강력한 실무 편의 기능을 제공합니다.

---

## 🌟 Key Features (핵심 기능)

### 1. 🖼️ Floating screenshot windows (플로팅 캡처 창)
* **Always-on-Top & Borderless:** Captured images are rendered instantly in borderless GUI windows set to float on top.
* **Double-Click Minimization:** Double-clicking a clip reduces it to a compact 80x80px card with 50% opacity, displaying its auto-assigned unique ID.
* **Always-on-Top & 무테두리:** 캡처한 이미지를 즉시 독립적인 항상-위 플로팅 창으로 띄웁니다.
* **더블클릭 최소화:** 더블클릭 시 80x80px 크기 및 50% 투명도로 소형화되며, 자동으로 할당된 고유 번호(ID)를 표시합니다.

### 2. 🔍 Multilingual OCR & Smart Fallbacks (다국어 OCR 및 스마트 폴백)
* **Native Windows OCR:** Directly parses Korean/English (`ko-KR`) and Polish (`pl-PL`) text using the native `Windows.Media.Ocr` engine.
* **Three-Tier Fallback Strategy (3단계 폴백 전략):**
  1. **Primary Language:** Checks for and runs the requested OCR language pack.
  2. **Secondary Fallback:** If the primary pack is missing, automatically defaults to the English (`en-US`) OCR engine.
  3. **Browser Fallback:** If no native OCR engines are installed, it automatically uploads the image to Google Translate (Image Translation) and sends a paste command (`Ctrl+V`) programmatically.
* **윈도우 네이티브 OCR:** `Windows.Media.Ocr` API를 호출하여 한국어/영어 및 폴란드어 텍스트를 실시간 추출 및 클립보드로 즉시 복사합니다.
* **스마트 대체 작동:** 언어팩 미설치 또는 판독 실패 시, 1차로 영어(en-US) 판독을 시도하고, 2차로 브라우저를 열어 구글 이미지 번역 서비스에 자동으로 이미지를 업로드(Ctrl+V 자동 제어)하는 고도화된 폴백 알고리즘을 갖추고 있습니다.

### 3. 🎨 On-Clip Annotation Canvas (실시간 주석 그리기)
* **Real-time Drawing Preview:** Annotate directly onto the floating screenshot.
* **Multi-Color Triggers:**
  * `Shift + Drag`: Red Rectangle Outline (빨간 테두리 사각형)
  * `Ctrl + Drag`: Yellow Highlighter (노란색 형광펜)
  * `Alt + Drag`: Green Highlighter (초록색 형광펜)
* **Multi-Step Undo:** Supports undoing up to 5 strokes (`Ctrl + Z` or context menu) using in-memory cloning of GDI+ bitmap graphics.
* **실시간 드로잉 프리뷰:** 플로팅 창 위에서 마우스 드래그를 통해 실시간으로 영역 미리보기를 제공하며 낙서 및 형광펜 표시가 가능합니다.
* **최대 5단계 실행 취소:** GDI+ 비트맵 클로닝 기법을 활용하여 그린 획을 최대 5번까지 되돌릴 수 있습니다 (`Ctrl + Z` 혹은 우클릭 메뉴).

### 4. 📐 Multi-Monitor Cascade Layout Sort (다중 모니터 캐스케이드 정렬)
* **Cascade Sorting:** Auto-aligns all scattered floating clips diagonally across the screen.
* **Multi-Monitor Aware:** Cycles through active monitors sequentially on successive keypresses, moving the cascade layout to the next monitor.
* **다중 모니터 지원 캐스케이드 정렬:** 흐트러진 모든 캡처 창을 화면 왼쪽 상단부터 대각선 방향으로 순차 정렬합니다. 단환 키 입력 시 활성화된 여러 모니터를 순환하며 창 그룹을 정렬시킵니다.

### 5. ⚙️ Image Scaling & Post-Processing (이미지 리사이징 및 사후 처리)
* **Registry-backed Scale Settings:** Supports shrinking or expanding clipboard output size (50% to 150%) saved in the Windows Registry (`HKCU\Software\ScreenClipTool`).
* **High-Quality Scaling:** Employs GDI+ `HighQualityBicubic` interpolation for scaling.
* **1px Aesthetic Border:** Automatically attaches a clean 1px black outline before clipboard copy or desktop saving for professional look.
* **레지스트리 기반 설정 관리:** 50% ~ 150% 범위의 이미지 비율 조정 설정을 윈도우 레지스트리에 영구 저장하고 불러옵니다.
* **고화질 보간법:** GDI+ `HighQualityBicubic` 알고리즘을 사용해 리사이징 시에도 텍스트 및 선의 왜곡을 최소화합니다.
* **테두리 자동 보정:** 파일 저장 또는 클립보드 복사 시 가장자리에 깔끔한 1px 검정 테두리를 씌워 가독성을 높입니다.
* **External config.ini File & Safe Loading:** Core constants such as minimization size, window opacity, border width, and maximum undo capacity are loaded from an external `config.ini` file. Incorporates safe validation algorithms to fallback to system defaults and prevent application crashes if parameters are corrupted or invalid.
* **외부 config.ini 설정 및 예외 안전 장치:** 창 축소 크기, 불투명도, 외곽선 두께, 최대 Undo 횟수 등의 핵심 상수를 외부 `config.ini` 파일에서 로딩합니다. 파일이 없거나 잘못된 문자열이 기록되어 있는 경우, 자체 방어 분석 로직을 거쳐 안전한 기본값으로 복구하여 실행 크래시를 원천 차단합니다.

---

## ⌨️ Shortcut Reference Guide (단축키 안내)

### Global Hotkeys (전역 단축키)
| Shortcut | Action (English) | 동작 (한국어) |
| :--- | :--- | :--- |
| `Win + Drag` | Capture area and create floating clip | 화면 캡처 후 플로팅 창 생성 (클립보드 자동 복사) |
| `Win + Ctrl + Drag` | Run Korean/English OCR | 한국어/영어 OCR 판독 (텍스트 복사) |
| `Win + Alt + Drag` | Run Polish OCR | 폴란드어 OCR 판독 (텍스트 복사) |

### On-Clip Hotkeys (플로팅 캡처 창 활성화 시 단축키)
| Shortcut | Action (English) | 동작 (한국어) |
| :--- | :--- | :--- |
| `Double-Click` | Toggle minimize (80x80 opacity) / restore | 최소화(80x80 크기 및 ID 표시) / 원래 크기 복원 토글 |
| `Right-Click` | Open feature context menu | 마우스 우클릭 콘텍스트 메뉴 열기 |
| `Shift + Drag` | Draw Red Outline Rectangle | 빨간 테두리 사각형 그리기 |
| `Ctrl + Drag` | Draw Yellow Highlighter | 노란색 형광펜 칠하기 |
| `Alt + Drag` | Draw Green Highlighter | 초록색 형광펜 칠하기 |
| `Ctrl + C` | Copy image to clipboard with border & scale | 테두리 및 스케일이 적용된 비트맵 클립보드 복사 |
| `Ctrl + S` | Save image to Desktop as PNG | 바탕화면에 PNG 파일로 즉시 저장 |
| `Ctrl + Z` | Undo last drawing stroke | 마지막으로 그린 주석 획 실행 취소 (최대 5회) |
| `Esc` | Close active clip window | 현재 선택된 캡처 창 닫기 |
| `Ctrl + Left` | Cascade sort all active clips (Monitor toggle) | 모든 캡처 창 캐스케이드 정렬 (입력 시 모니터 순환) |
| `Ctrl + Up` | Minimize all active clips | 모든 캡처 창 일괄 최소화 |
| `Ctrl + Down` | Restore all active clips | 모든 캡처 창 일괄 복원 |
| `Ctrl + Esc` | Close all active clips | 모든 캡처 창 일괄 닫기 |

---

## 🛠️ System Requirements & Installation (요구 사양 및 설치법)

1. **Operating System:** Windows 10 / Windows 11 (Windows OCR requires OS-level language packs).
2. **Runtime Engine:** [AutoHotkey v2.0+](https://www.autohotkey.com/) must be installed.
3. **OCR Languages (Optional but Recommended):** 
   To fully utilize native OCR, ensure that the language packs for English, Korean, and/or Polish are installed in your Windows settings:
   * *Settings > Time & Language > Language > Add a language* (Check "Speech recognition & OCR" package).

1. **운영체제:** Windows 10 이상 (윈도우 내장 OCR 엔진 필수 활용).
2. **구동 엔진:** [AutoHotkey v2.0+](https://www.autohotkey.com/) 정식 버전이 설치되어 있어야 합니다.
3. **OCR 언어팩 설치 (선택 사항):**
   네이티브 OCR 기능을 활용하기 위해서는 Windows 언어 설정에서 한국어, 영어, 폴란드어 등의 언어팩(필수: OCR 팩 포함)이 설치되어 있어야 정상 판독이 가능합니다.
   * *설정 > 시간 및 언어 > 언어 > 기본 설정 언어 추가* (OCR 옵션 체크 필수).

---

## 📂 Repository Structure (저장소 구조)

* `App01_ClippingTool_v1.ahk` - Main Application Script (핵심 애플리케이션 스크립트)
* `config.ini` - External Configuration File for Customizing Constants (외부 설정 파일 - 크기, 투명도 등 관리)
* `Gdip_All.ahk` - GDI+ Integration Library (GDI+ 이미지 처리 라이브러리)
* `OCR.ahk` - Windows Native OCR Wrapper Library (윈도우 내장 OCR 래퍼 라이브러리)
* `LICENSE` - Open source MIT License (오픈소스 MIT 라이선스)
* `Manual1.png` - Visual User Guide Image (사용자 가이드 매뉴얼 이미지)

---

## 💡 Engineering Highlights (기술적 강점)

* **Robust GDI+ Resource Management:** Standard AHK scripts often leak memory when repeatedly instantiating GDI+ bitmaps. This application implements strict tracking, disposing of internal GDI+ bitmaps (`Gdip_DisposeImage`) and deleting device-dependent objects (`DeleteObject`, `DeletePen`, `DeleteGraphics`) immediately when no longer needed or when windows are closed.
* **Deterministic Layout Sorting:** Arranges user coordinate grids by implementing a custom low-overhead bubble sort algorithm on window object arrays based on their unique numeric IDs.
* **Process Automation (RPA-grade):** Employs custom win32 window searching API techniques and UI synchronization strategies to capture coordinates, restore scale settings dynamically, shift z-orders gracefully, and automate web application inputs reliably without flickering.

* **철저한 GDI+ 메모리 누수 방지:** 비트맵 연산이 빈번한 도구 특성상 메모리 누수(Memory Leak)가 발생하기 쉽습니다. 본 앱은 비트맵 복사 및 드로잉 해제 시 `Gdip_DisposeImage` 및 `DeleteObject` API를 철저하게 명시적으로 호출하여 메모리를 완전히 최적화합니다.
* **객체 지향형 레이아웃 정렬 알고리즘:** 정적 배열 내 캡처 윈도우 객체들의 고유 식별 번호(ID)를 기준으로 버블 정렬 알고리즘을 작동시켜 흐트러짐 없는 캐스케이드(Diagonal) 배치를 신속히 구현합니다.
* **업무 자동화(RPA)급 연동:** 백그라운드 브라우저의 HWND를 직접 매칭하고 포커스를 조율하는 세련된 윈도우 제어 테크닉을 활용하여, 이미지 복사에서 브라우저 전송까지 끊김 없고 플리커 현상 없는 자동 프로세스를 구축했습니다.

---

## 📄 License (라이선스)

Licensed under the [MIT License](LICENSE). GDI+ library wrapper by Tariq Porter (tic), and OCR wrapper by Descolada.
