# 📸 ScreenClip Tool v1  
### Dynamic Screenshot & OCR Automation Suite built for real-world office workflows

<p align="center">
  <img src="./demo.gif" width="900">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/OS-Windows%2010%2B-blue">
  <img src="https://img.shields.io/badge/AutoHotkey-v2-green">
  <img src="https://img.shields.io/badge/OCR-Windows%20Native-red">
  <img src="https://img.shields.io/badge/License-MIT-yellow">
</p>

<p align="center">
<a href="https://buymeacoffee.com/KBPark_Bob">
<img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&emoji=☕&slug=KBPark_Bob&button_colour=FFDD00&font_colour=000000&outline_colour=000000&coffee_colour=ffffff">
</a>
</p>

---

## 👋 Why I built this

I'm **not a professional software engineer**.

I work in a **finance department**, where repetitive tasks such as screenshot capturing, OCR extraction, documentation, and information sharing are part of everyday workflows.

Over time, I realized that many of these repetitive actions affected not only my own productivity but also the efficiency of my teammates.

This project began as an attempt to reduce those inefficiencies and support both **my own workflow and the repetitive operational tasks shared within the team**.

What started as a small automation script gradually evolved into a more sophisticated system featuring:

- Dynamic floating screenshot windows
- Native Windows OCR integration
- Real-time annotation tools
- Multi-monitor layout management
- Browser automation fallbacks
- Registry-backed persistent settings
- GDI+ bitmap optimization & resource management

This repository reflects my growing interest in:

> **Automation Engineering · Productivity Tools · Workflow Optimization · Practical Software Development**

I believe useful software doesn't always originate from professional developers — sometimes it comes directly from people trying to improve the way their teams work every day.

---

저는 **전문 개발자가 아니라 재무부서에서 근무하는 실무자**입니다.

업무 과정에서 반복적으로 수행되는 **화면 캡처, OCR 판독, 문서 정리, 정보 공유 및 반복 입력 작업**은 많은 시간을 소모했습니다.

이러한 반복 업무는 단순히 제 개인의 비효율 문제만이 아니라, **팀원들이 함께 겪는 공통적인 업무 부담**이라는 점을 느끼게 되었고 이를 줄이고자 자동화 도구 개발을 시작했습니다.

이 프로젝트는 **제 업무 효율 향상뿐 아니라 팀원들의 반복 업무를 지원하고 개선하기 위한 목적**에서 출발했습니다.

작은 자동화 스크립트로 시작했지만 지속적으로 기능을 확장하며 현재는:

- 플로팅 캡처 창
- 실시간 OCR
- 주석 및 형광펜 기능
- 다중 모니터 관리
- 브라우저 자동화
- 레지스트리 기반 설정 저장
- GDI+ 메모리 최적화

등을 포함한 통합 업무 자동화 도구로 발전했습니다.

본 저장소는 단순한 AHK 스크립트 모음이 아니라,

> **반복 업무 제거 · 팀 생산성 향상 · 실무 자동화 · 문제 해결 중심 개발**

에 대한 지속적인 탐구 기록이기도 합니다.

전문 개발자가 아니더라도, **실제 업무를 경험하는 사람들이 현장의 문제를 해결하기 위해 만든 도구가 가장 실용적일 수 있다**고 믿습니다.

---

# 📖 Visual User Guide (사용자 메뉴얼)

> Quick overview of workflows and shortcuts

<p align="center">
<img src="./App01Manual.png" width="1000">
</p>

---

## 🚀 Quick Start

### Installation

1. Install **AutoHotkey v2+**

https://www.autohotkey.com/

2. Clone repository

```bash
git clone https://github.com/KwangBeomPark/AHK-ScreenClip-OCR-Automation.git
```

3. Run:

```txt
App01_ClippingTool_v1.ahk
```

4. (Optional) Install Windows OCR language packs

Settings → Time & Language → Language → Add language → Enable OCR package

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

1. **Primary Language**
2. **Secondary Fallback**
3. **Browser Fallback**

...

(여기부터 기존 README 내용 그대로 유지)

---

## ⌨️ Shortcut Reference Guide (단축키 안내)

(기존 내용 유지)

---

## 🛠️ System Requirements & Installation (요구 사양 및 설치법)

(기존 내용 유지)

---

## 📂 Repository Structure (저장소 구조)

* `App01_ClippingTool_v1.ahk`
* `config.ini`
* `Gdip_All.ahk`
* `OCR.ahk`
* `LICENSE`
* `App01Manual.png`

---

## 💡 Engineering Highlights (기술적 강점)

(기존 내용 유지)

---

## ☕ Support This Project

If this tool saves your time or improves your workflow, consider supporting future development.

<p align="center">
<a href="https://buymeacoffee.com/KBPark_Bob">
<img src="https://img.buymeacoffee.com/button-api/?text=Support future automation projects&emoji=☕&slug=KBPark_Bob">
</a>
</p>

Your support helps me continue exploring:

- Productivity engineering
- Workflow automation
- OCR tools
- Office automation
- Practical software projects outside traditional development roles

감사합니다 🙏

---

## 📄 License (라이선스)

Licensed under the MIT License.

GDI+ wrapper by Tariq Porter (tic)  
OCR wrapper by Descolada
