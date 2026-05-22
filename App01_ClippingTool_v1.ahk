#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Gdip_All.ahk
#Include OCR.ahk

if !pToken := Gdip_Startup() {
    MsgBox "GDI+ failed to start."
    ExitApp
}

OnExit AppCleanup

AppCleanup(*) {
    global pToken
    Gdip_Shutdown(pToken)
    try FileDelete(A_Temp "\temp_clip.png")
}

; ── OCR 언어팩 설치 여부 검사 ──
global hasOCR_koKR := false
global hasOCR_plPL := false
global hasOCR_enUS := false
try {
    availLangs := OCR.GetAvailableLanguages()
    hasOCR_koKR := InStr(availLangs, "ko") ? true : false
    hasOCR_plPL := InStr(availLangs, "pl") ? true : false
    hasOCR_enUS := InStr(availLangs, "en") ? true : false
}

; ── 상수 정의 (config.ini에서 로딩, 안전한 정수 변환 및 미존재 시 기본값 사용) ──
global CONFIG_FILE := A_ScriptDir "\config.ini"

/**
 * config.ini 파일에서 안전하게 정수 설정을 불러오는 헬퍼 함수
 * Safely loads integer settings from config.ini, defaulting if invalid.
 * @param {String} section - INI 섹션 이름 / Section name
 * @param {String} key - INI 키 이름 / Key name
 * @param {Integer} defaultVal - 기본값 / Default value fallback
 * @returns {Integer} 로드된 설정값 혹은 기본값 / Loaded value or fallback
 */
LoadIntSetting(section, key, defaultVal) {
    try {
        val := IniRead(CONFIG_FILE, section, key, String(defaultVal))
        return IsInteger(val) ? Integer(val) : defaultVal
    } catch {
        return defaultVal
    }
}

global MINI_SIZE := LoadIntSetting("UI", "MINI_SIZE", 80)
global MINI_OPACITY := LoadIntSetting("UI", "MINI_OPACITY", 128)
global BORDER_WIDTH := LoadIntSetting("UI", "BORDER_WIDTH", 3)
global UNDO_MAX := LoadIntSetting("Behavior", "UNDO_MAX", 5)

; ── 시스템 트레이 아이콘 및 메뉴 커스텀 ──
try {
    TraySetIcon("shell32.dll", 260) ; 가위 아이콘 (Snipping tool style)
} catch {
    ; 실패 시 무시 (기본 아이콘 사용)
}
A_IconTip := "Screen Clip Tool"
Tray := A_TrayMenu
Tray.Delete()
Tray.Add("📸 Capture (Win+Drag)", (*) => ScreenClip2Win(1))
Tray.Add("🔍 OCR: KR/EN (Win+Ctrl+Drag)", (*) => ScreenClip2OCR("ko-KR"))
Tray.Add("🔍 OCR: PL (Win+Alt+Drag)", (*) => ScreenClip2OCR("pl-PL"))
Tray.Add()
Tray.Add("📐 Sort All Clips (Ctrl+Left)", (*) => SCW_SortCascade())
Tray.Add("🔽 Minimize All (Ctrl+Up)", (*) => SCW_MinimizeAll())
Tray.Add("🔼 Restore All (Ctrl+Down)", (*) => SCW_RestoreAll())
Tray.Add("❌ Close All Clips (Ctrl+Esc)", (*) => SCW_CloseAll())
Tray.Add()
Tray.Add("🔄 Reload Script", (*) => Reload())
Tray.Add("🚪 Exit App", (*) => ExitApp())

; Globals
global ClipWins := Map()
global RightClickedHwnd := 0
global ClipMenu := Menu()

global REG_PATH := "HKCU\Software\ScreenClipTool"
global CLIP_SCALE := 1.0
try {
    CLIP_SCALE := Float(RegRead(REG_PATH, "Scale"))
} catch {
    CLIP_SCALE := 1.0
}

; Google Image 번역 서브메뉴 (타겟 언어 선택)
ImgTransMenu := Menu()
ImgTransMenu.Add("🇰🇷 Translate to Korean", (*) => GoogleImageTranslate("ko"))
ImgTransMenu.Add("🇬🇧 Translate to English", (*) => GoogleImageTranslate("en"))
ImgTransMenu.Add("🇵🇱 Translate to Polish", (*) => GoogleImageTranslate("pl"))

; 1. 텍스트 번역(OCR) 서브메뉴
TextTransMenu := Menu()
TextTransMenu.Add("🇵🇱→🇰🇷 Translate: PL to KR", MenuHandler)
TextTransMenu.Add("🇬🇧→🇰🇷 Translate: EN to KR", MenuHandler)
TextTransMenu.Add("🇵🇱→🇬🇧 Translate: PL to EN", MenuHandler)
TextTransMenu.Add() ; Separator
TextTransMenu.Add("🇰🇷→🇵🇱 Translate: KR to PL", MenuHandler)
TextTransMenu.Add("🇬🇧→🇵🇱 Translate: EN to PL", MenuHandler)
TextTransMenu.Add("🇰🇷→🇬🇧 Translate: KR to EN", MenuHandler)

ClipMenu.Add("🌐 1. Google Translate (Image)", ImgTransMenu)
ClipMenu.Add("🔤 2. Text Translate (OCR)", TextTransMenu)
ClipMenu.Add() ; Separator

; 3. 클립보드 스케일 서브메뉴
ScaleMenu := Menu()
ScaleMenu.Add("50%", (*) => SetClipScale(0.5))
ScaleMenu.Add("60%", (*) => SetClipScale(0.6))
ScaleMenu.Add("70%", (*) => SetClipScale(0.7))
ScaleMenu.Add("80%", (*) => SetClipScale(0.8))
ScaleMenu.Add("90%", (*) => SetClipScale(0.9))
ScaleMenu.Add("100%", (*) => SetClipScale(1.0))
ScaleMenu.Add("150%", (*) => SetClipScale(1.5))
UpdateScaleMenu()

ClipMenu.Add("⚙️ 3. Clipboard Scale", ScaleMenu)
ClipMenu.Add() ; Separator

ClipMenu.Add("📝 Draw: Shift=Red, Ctrl=Yellow, Alt=Green", (*) => 0)
ClipMenu.Disable("📝 Draw: Shift=Red, Ctrl=Yellow, Alt=Green")
ClipMenu.Add() ; Separator

ClipMenu.Add("🎨 4. Copy To Paint", MenuHandler)
ClipMenu.Add("💾 5. Save to Desktop (Ctrl+S)", MenuHandler)
ClipMenu.Add("📋 6. Copy to Clipboard (Ctrl+C)", MenuHandler)
ClipMenu.Add("↩️ 7. Undo Draw (Ctrl+Z)", MenuHandler)

WinMenu := Menu()
WinMenu.Add("📐 Sort All Clips (Ctrl+Left)", (*) => SCW_SortCascade())
WinMenu.Add("🔽 Minimize All (Ctrl+Up)", (*) => SCW_MinimizeAll())
WinMenu.Add("🔼 Restore All (Ctrl+Down)", (*) => SCW_RestoreAll())
WinMenu.Add("❌ Close All Clips (Ctrl+Esc)", (*) => SCW_CloseAll())

ClipMenu.Add() ; Separator
ClipMenu.Add("🪟 8. Window Management", WinMenu)

; ── OCR 미설치 언어 메뉴 비활성화 ──
if !hasOCR_plPL {
    TextTransMenu.Disable("🇵🇱→🇰🇷 Translate: PL to KR")
    TextTransMenu.Disable("🇵🇱→🇬🇧 Translate: PL to EN")
}
if !hasOCR_enUS {
    TextTransMenu.Disable("🇬🇧→🇰🇷 Translate: EN to KR")
    TextTransMenu.Disable("🇬🇧→🇵🇱 Translate: EN to PL")
}
if !hasOCR_koKR {
    TextTransMenu.Disable("🇰🇷→🇵🇱 Translate: KR to PL")
    TextTransMenu.Disable("🇰🇷→🇬🇧 Translate: KR to EN")
}

; ── 시작 시 환영 툴팁 ──
ToolTip("📸 Screen Clip Tool Ready!`r`nWin+드래그: 캡처 / Win+Ctrl+드래그: OCR`r`nWin+Drag: Capture / Win+Ctrl+Drag: OCR")
SetTimer(() => ToolTip(), -4000)

; Hotkeys
#^LButton:: ScreenClip2OCR("ko-KR") ; Win+Ctrl+LButton -> OCR (한국어/영어)
#!LButton:: ScreenClip2OCR("pl-PL") ; Win+Alt+LButton -> OCR (폴란드어)
#LButton:: ScreenClip2Win(1)  ; Win+LButton -> floating clip + auto copy to clipboard

#HotIf WinActive("ScreenClippingWindow ahk_class AutoHotkeyGUI")
^c:: SCW_Win2Clipboard()
^s:: SCW_Win2File()
^z:: SCW_Undo()
^Left:: SCW_SortCascade()
^Up:: SCW_MinimizeAll()
^Down:: SCW_RestoreAll()
Esc:: SCW_CloseWin()
^Esc:: SCW_CloseAll() ; Ctrl+Esc -> 전체 닫기
#HotIf

/**
 * 지정한 화면 영역을 캡처하여 항상-위 플로팅 이미지 창을 생성하는 핵심 함수
 * Captures a selected screen area and displays it in a floating always-on-top window.
 * @param {Integer} clipToClipboard - 1인 경우 클립보드로 자동 복사 수행 / Auto-copy to clipboard if 1
 * @returns {None}
 */
ScreenClip2Win(clipToClipboard := 0) {
    Area := SelectArea()
    if (Area.W < 10 || Area.H < 10)
        return

    pBitmap := Gdip_BitmapFromScreen(Area.X "|" Area.Y "|" Area.W "|" Area.H)

    hwnd := CreateClipWin(pBitmap, Area.X, Area.Y)

    if clipToClipboard {
        WinActivate("ahk_id " hwnd)
        SCW_Win2Clipboard()
    }
}

/**
 * 지정한 화면 영역을 네이티브 Windows OCR 엔진으로 판독하고 클립보드에 복사하는 함수
 * Performs native Windows OCR on a selected screen region and copies the text to the clipboard.
 * @param {String} lang - 판독 언어 (ko-KR, pl-PL, en-US 등) / Target language pack
 * @returns {None}
 */
ScreenClip2OCR(lang := "FirstFromAvailableLanguages") {
    actualLang := lang
    isFallback := false

    ; 요청한 언어팩이 있는지 확인
    langAvailable := (lang == "ko-KR" && hasOCR_koKR) || (lang == "pl-PL" && hasOCR_plPL) || (lang == "en-US" &&
        hasOCR_enUS)

    if !langAvailable {
        ; 없으면 영어(en-US)가 있는지 확인해서 대체 (클라우드 PC 등)
        if hasOCR_enUS {
            actualLang := "en-US"
            isFallback := true
        } else {
            ; 영어조차 없으면 구글 이미지 번역으로 폴백
            ScreenClip2GoogleImage()
            return
        }
    }

    Area := SelectArea()
    if (Area.W < 10 || Area.H < 10)
        return

    try {
        result := OCR.FromRect(Area.X, Area.Y, Area.W, Area.H, { lang: actualLang })

        if isFallback {
            langNameKR := "[영어(대체)]"
            langNameEN := "[EN(Fallback)]"
        } else {
            langNameKR := (actualLang == "pl-PL") ? "[폴란드어]" : "[한국어/영어]"
            langNameEN := (actualLang == "pl-PL") ? "[Polish]" : "[KR/EN]"
        }

        if (result.Text != "") {
            A_Clipboard := result.Text
            ToolTip("✅ 텍스트 복사 완료 " langNameKR "`r`n✅ Text copied to clipboard! " langNameEN)
            SetTimer(() => ToolTip(), -3000)
        } else {
            ToolTip("⚠️ 인식된 텍스트 없음 " langNameKR "`r`n⚠️ No text recognized. " langNameEN)
            SetTimer(() => ToolTip(), -3000)
        }
    } catch as e {
        ; OCR 실패 시에도 구글 이미지 번역으로 폴백
        ScreenClip2GoogleImage()
    }
}

/**
 * 로컬 OCR 실패 또는 언어팩 누락 시 구글 번역(이미지) 페이지로 화면을 캡처하여 전송하는 폴백 함수
 * Fallback subroutine that uploads the captured screen snippet to Google Translate Web (Image).
 * @returns {None}
 */
ScreenClip2GoogleImage() {
    Area := SelectArea()
    if (Area.W < 10 || Area.H < 10)
        return
    pBitmap := Gdip_BitmapFromScreen(Area.X "|" Area.Y "|" Area.W "|" Area.H)
    Gdip_SetBitmapToClipboard(pBitmap)
    Gdip_DisposeImage(pBitmap)
    Run("https://translate.google.com/?sl=auto&tl=ko&op=images")
    ToolTip("🌐 구글 번역(이미지) 열기 중...`r`n🌐 Opening Google Image Translation...")
    AutoPasteToGoogleTranslate()
}

/**
 * 플로팅 창의 우클릭 메뉴에서 특정 타겟 언어를 선택하여 구글 이미지 번역을 실행하는 함수
 * Triggers Google Image Translation with a user-selected target language from the context menu.
 * @param {String} targetLang - 타겟 언어 코드 (ko, en, pl 등) / Target language code
 * @returns {None}
 */
GoogleImageTranslate(targetLang) {
    global RightClickedHwnd
    if !ClipWins.Has(RightClickedHwnd)
        return
    pBitmap := ClipWins[RightClickedHwnd].pBitmap
    Gdip_SetBitmapToClipboard(pBitmap)
    Run("https://translate.google.com/?sl=auto&tl=" targetLang "&op=images")
    ToolTip("🌐 구글 번역(이미지) 열기 중...`r`n🌐 Opening Google Image Translation...")
    AutoPasteToGoogleTranslate()
}

/**
 * 구글 번역 브라우저 창을 감지하고 활성화한 후 클립보드의 이미지를 자동으로 붙여넣는(Ctrl+V) RPA 루틴
 * Detects the active browser translation tab and automates clipboard paste (Ctrl+V) inputs.
 * @returns {None}
 */
AutoPasteToGoogleTranslate() {
    SetTimer(_DoPaste, -1000)

    _DoPaste() {
        ; 다국어 브라우저 타이틀 패턴
        patterns := ["Google Translate", "Google 번역", "Tłumacz Google", "translate.google"]
        hwndTarget := 0

        ; 브라우저 창이 뜰 때까지 최대 5초 대기
        loop 10 {
            for _, pattern in patterns {
                if hwnd := WinExist(pattern) {
                    hwndTarget := hwnd
                    break
                }
            }
            if hwndTarget
                break
            Sleep(500)
        }

        if !hwndTarget {
            ToolTip(
                "⚠️ 브라우저를 찾을 수 없습니다. Ctrl+V로 직접 붙여넣으세요.`r`n⚠️ Browser not found. Please paste manually with Ctrl+V.")
            SetTimer(() => ToolTip(), -4000)
            return
        }

        ; 모든 캡처 창의 AlwaysOnTop 해제 + z-order 맨 아래로 이동
        for clipHwnd, _ in ClipWins {
            WinSetAlwaysOnTop(false, "ahk_id " clipHwnd)
            ; HWND_BOTTOM=1, SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE=0x0013
            DllCall("SetWindowPos", "ptr", clipHwnd, "ptr", 1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
        }

        WinActivate("ahk_id " hwndTarget)
        WinWaitActive("ahk_id " hwndTarget, , 3)
        Sleep(1000) ; 페이지 로딩 대기

        ; 브라우저 중앙 클릭으로 페이지 포커스 확보 후 붙여넣기
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwndTarget)
        CoordMode("Mouse", "Screen")
        Click(winX + winW // 2, winY + winH // 2)
        Send("^v")

        ; 모든 캡처 창의 AlwaysOnTop 복원
        for clipHwnd, _ in ClipWins
            WinSetAlwaysOnTop(true, "ahk_id " clipHwnd)

        ToolTip("✅ 이미지 붙여넣기 완료!`r`n✅ Image pasted to Google Translate!")
        SetTimer(() => ToolTip(), -3000)
    }
}

SelectArea() {
    CoordMode "Mouse", "Screen"
    MouseGetPos &MX, &MY

    SelGui := Gui("+AlwaysOnTop -Caption +Border +ToolWindow -DPIScale")
    WinSetTransparent 80, SelGui.Hwnd
    SelGui.BackColor := "Yellow"

    loop {
        if !GetKeyState("LButton", "P")
            break
        if GetKeyState("Esc", "P") {
            SelGui.Destroy()
            return { X: 0, Y: 0, W: 0, H: 0 }
        }
        Sleep 10
        MouseGetPos &MXend, &MYend
        w := Abs(MX - MXend)
        h := Abs(MY - MYend)
        X := (MX < MXend) ? MX : MXend
        Y := (MY < MYend) ? MY : MYend
        SelGui.Show("x" X " y" Y " w" w " h" h " NA")
    }
    SelGui.Destroy()

    MouseGetPos &MXend, &MYend
    X := (MX < MXend) ? MX : MXend
    Y := (MY < MYend) ? MY : MYend
    W := Abs(MX - MXend)
    H := Abs(MY - MYend)

    return { X: X, Y: Y, W: W, H: H }
}

DrawRectPreview(bgColor, hasBorder := true) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&screenStartX, &screenStartY)
    options := "+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale" . (hasBorder ? " +Border" : "")
    PreviewGui := Gui(options)
    WinSetTransparent(100, PreviewGui.Hwnd)
    PreviewGui.BackColor := bgColor

    x := 0, y := 0, w := 0, h := 0
    loop {
        if !GetKeyState("LButton", "P")
            break
        Sleep(10)
        MouseGetPos(&sMXend, &sMYend)

        w := Abs(screenStartX - sMXend)
        h := Abs(screenStartY - sMYend)
        x := (screenStartX < sMXend) ? screenStartX : sMXend
        y := (screenStartY < sMYend) ? screenStartY : sMYend
        if (w > 0 && h > 0)
            PreviewGui.Show("x" x " y" y " w" w " h" h " NA")
    }
    PreviewGui.Destroy()
    return { x: x, y: y, w: w, h: h }
}

/**
 * 플로팅 캡처 창 GUI를 생성하고 화면에 표시하는 함수
 * Creates and displays the borderless floating clipping window GUI.
 * @param {Integer} pBitmap - GDI+ 비트맵 포인터 / GDI+ bitmap pointer
 * @param {Integer} x - 시작 X 좌표 / Start X screen coordinate
 * @param {Integer} y - 시작 Y 좌표 / Start Y screen coordinate
 * @returns {Integer} 생성된 GUI 윈도우의 HWND / The created window's HWND handle
 */
CreateClipWin(pBitmap, x, y) {
    ClipGui := Gui("-Caption +ToolWindow +AlwaysOnTop +OwnDialogs -DPIScale", "ScreenClippingWindow")
    ClipGui.MarginX := 0
    ClipGui.MarginY := 0
    ClipGui.BackColor := "ff6666" ; Border color

    W := Gdip_GetImageWidth(pBitmap)
    H := Gdip_GetImageHeight(pBitmap)

    hBitmap := Gdip_CreateHBITMAPFromBitmap(pBitmap)
    Pic := ClipGui.Add("Picture", "x" BORDER_WIDTH " y" BORDER_WIDTH " w" W " h" H, "HBITMAP:*" hBitmap)
    DllCall("DeleteObject", "ptr", hBitmap)

    ; Add a tiny close button in the top right
    CloseBtnSize := 16
    CloseBtnX := W + (BORDER_WIDTH * 2) - CloseBtnSize - 1
    CloseBtnY := 1
    CloseBtn := ClipGui.Add("Text", "x" CloseBtnX " y" CloseBtnY " w" CloseBtnSize " h" CloseBtnSize " Center +BackgroundTrans cWhite +0x200",
        "×")
    CloseBtn.SetFont("s14 Bold")
    CloseBtn.OnEvent("Click", (*) => CloseClipWin(ClipGui))

    ; 가장 빠른 빈 번호 찾기 (Lowest Available Number)
    assignedId := 1
    loop {
        inUse := false
        for h, info in ClipWins {
            if (info.HasProp("id") && info.id == assignedId) {
                inUse := true
                break
            }
        }
        if (!inUse)
            break
        assignedId++
    }

    ; 숫자가 더 잘 보이도록 배경 역할을 할 검정색 레이어 (약간 작게)
    NumBg := ClipGui.Add("Text", "x15 y15 w50 h50 Background222222 Hidden", "")

    ; 축소 시 표시될 번호
    ; AHK 기본 Text 컨트롤은 완전 투명(+BackgroundTrans)으로 하고, GUI 자체의 투명도로 조절
    NumText := ClipGui.Add("Text", "x0 y0 w80 h80 Center 0x200 +BackgroundTrans cYellow Hidden", assignedId)
    NumText.SetFont("s24 Bold", "Verdana")

    ClipGui.Show("x" (x - BORDER_WIDTH) " y" (y - BORDER_WIDTH) " w" (W + BORDER_WIDTH * 2) " h" (H + BORDER_WIDTH * 2) " NA"
    )

    hwnd := ClipGui.Hwnd
    ClipWins[hwnd] := { pBitmap: pBitmap, w: W, h: H, gui: ClipGui, IsMinimized: false, id: assignedId, NumText: NumText,
        NumBg: NumBg,
        picCtrl: Pic, UndoStack: [], orgX: x - BORDER_WIDTH, orgY: y - BORDER_WIDTH }

    ; Setup dragging
    OnMessage(0x0201, WM_LBUTTONDOWN)
    OnMessage(0x0203, WM_LBUTTONDOWN) ; Handle double click message
    OnMessage(0x0204, WM_RBUTTONDOWN) ; Handle right click message

    ClipGui.OnEvent("Close", (*) => CloseClipWin(ClipGui))

    UpdateTrayTip()
    return hwnd
}

CloseClipWin(guiObj) {
    hwnd := guiObj.Hwnd
    if ClipWins.Has(hwnd) {
        winInfo := ClipWins[hwnd]
        for _, bmp in winInfo.UndoStack {
            Gdip_DisposeImage(bmp)
        }
        Gdip_DisposeImage(winInfo.pBitmap)
        ClipWins.Delete(hwnd)
    }
    guiObj.Destroy()
    UpdateTrayTip()
}

UpdateTrayTip() {
    cnt := ClipWins.Count
    A_IconTip := "Screen Clip Tool" . (cnt > 0 ? " (" cnt " clip" (cnt > 1 ? "s" : "") ")" : "")
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    if !ClipWins.Has(hwnd)
        return

    static LastClickTime := 0
    static LastClickHwnd := 0

    winInfo := ClipWins[hwnd]

    ; --- 그리기 모드 (Shift: 빨간 네모, Ctrl: 노랑 형광펜, Alt: 초록 형광펜) ---
    if GetKeyState("Shift", "P") || GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") {
        ; 백업 (Undo를 위해 최대 5개 저장)
        clone := Gdip_CloneBitmapArea(winInfo.pBitmap, 0, 0, winInfo.w, winInfo.h)
        winInfo.UndoStack.Push(clone)
        if (winInfo.UndoStack.Length > UNDO_MAX) {
            oldest := winInfo.UndoStack.RemoveAt(1)
            Gdip_DisposeImage(oldest)
        }

        WinGetPos(&winX, &winY, , , "ahk_id " hwnd)

        if GetKeyState("Shift", "P") {
            rect := DrawRectPreview("Red")
            if (rect.w > 0 && rect.h > 0) {
                rectX := rect.x - (winX + BORDER_WIDTH)
                rectY := rect.y - (winY + BORDER_WIDTH)
                pGraphics := Gdip_GraphicsFromImage(winInfo.pBitmap)
                pPen := Gdip_CreatePen("0xFFFF0000", BORDER_WIDTH)
                Gdip_DrawRectangle(pGraphics, pPen, rectX, rectY, rect.w, rect.h)
                Gdip_DeletePen(pPen)
                Gdip_DeleteGraphics(pGraphics)
            }
        }
        else if GetKeyState("Ctrl", "P") {
            rect := DrawRectPreview("Yellow", false)
            if (rect.w > 0 && rect.h > 0) {
                rectX := rect.x - (winX + BORDER_WIDTH)
                rectY := rect.y - (winY + BORDER_WIDTH)
                pGraphics := Gdip_GraphicsFromImage(winInfo.pBitmap)
                pBrush := Gdip_BrushCreateSolid("0x77FFFF00")
                Gdip_FillRectangle(pGraphics, pBrush, rectX, rectY, rect.w, rect.h)
                Gdip_DeleteBrush(pBrush)
                Gdip_DeleteGraphics(pGraphics)
            }
        }
        else if GetKeyState("Alt", "P") {
            rect := DrawRectPreview("Lime", false) ; 초록색 프리뷰
            if (rect.w > 0 && rect.h > 0) {
                rectX := rect.x - (winX + BORDER_WIDTH)
                rectY := rect.y - (winY + BORDER_WIDTH)
                pGraphics := Gdip_GraphicsFromImage(winInfo.pBitmap)
                pBrush := Gdip_BrushCreateSolid("0x7700FF00") ; 초록색 형광펜 (투명도 포함)
                Gdip_FillRectangle(pGraphics, pBrush, rectX, rectY, rect.w, rect.h)
                Gdip_DeleteBrush(pBrush)
                Gdip_DeleteGraphics(pGraphics)
            }
        }

        ; 화면 갱신
        hBitmap := Gdip_CreateHBITMAPFromBitmap(winInfo.pBitmap)
        winInfo.picCtrl.Value := "HBITMAP:*" hBitmap
        DllCall("DeleteObject", "ptr", hBitmap)
        return
    }
    isDoubleClick := (msg == 0x0203) || (hwnd == LastClickHwnd && A_TickCount - LastClickTime < DllCall(
        "GetDoubleClickTime"))

    ; 더블 클릭 감지
    if isDoubleClick {
        LastClickTime := 0 ; 초기화

        if winInfo.IsMinimized {
            ; 원래 크기로 복구
            WinMove(winInfo.orgX, winInfo.orgY, winInfo.w + BORDER_WIDTH * 2, winInfo.h + BORDER_WIDTH * 2, hwnd)
            WinSetTransparent("Off", hwnd)
            winInfo.NumText.Visible := false
            winInfo.NumBg.Visible := false
            winInfo.IsMinimized := false
        } else {
            WinGetPos(&oX, &oY, , , "ahk_id " hwnd)
            winInfo.orgX := oX
            winInfo.orgY := oY
            WinMove(, , MINI_SIZE, MINI_SIZE, hwnd)
            WinSetTransparent(MINI_OPACITY, hwnd) ; 50% 투명도로 설정
            winInfo.NumBg.Visible := true ; 검정 배경 살짝 노출
            winInfo.NumText.Visible := true
            winInfo.NumText.Redraw()
            winInfo.IsMinimized := true
        }
        return
    }

    LastClickTime := A_TickCount
    LastClickHwnd := hwnd

    ; Move window when clicking anywhere
    PostMessage 0xA1, 2, , , "ahk_id " hwnd
}

SCW_Win2Clipboard() {
    hwnd := WinExist("A")
    if !ClipWins.Has(hwnd)
        return

    pBitmap := ClipWins[hwnd].pBitmap
    w := Gdip_GetImageWidth(pBitmap)
    h := Gdip_GetImageHeight(pBitmap)

    if (CLIP_SCALE != 1.0) {
        pScaled := ResizeBitmap(pBitmap, CLIP_SCALE)
        pBordered := AddBorderToBitmap(pScaled)
        Gdip_DisposeImage(pScaled)
    } else {
        pBordered := AddBorderToBitmap(pBitmap)
    }

    Gdip_SetBitmapToClipboard(pBordered)

    finalW := Gdip_GetImageWidth(pBordered)
    finalH := Gdip_GetImageHeight(pBordered)
    Gdip_DisposeImage(pBordered)

    ToolTip("✅ 캡처 완료 (" finalW "×" finalH ") + 클립보드 복사`r`n✅ Copied to clipboard (" finalW "x" finalH ")")
    SetTimer(() => ToolTip(), -2000)
}

SCW_Win2File() {
    hwnd := WinExist("A")
    if !ClipWins.Has(hwnd)
        return

    pBitmap := ClipWins[hwnd].pBitmap
    pBordered := AddBorderToBitmap(pBitmap)
    TodayDate := FormatTime(, "yyyy-MM-dd_HHmmss")
    FileOut := A_Desktop "\" TodayDate ".PNG"
    Gdip_SaveBitmapToFile(pBordered, FileOut)
    Gdip_DisposeImage(pBordered)
    ToolTip("✅ 바탕화면에 저장 완료`r`n✅ Saved to Desktop:`r`n" FileOut)
    SetTimer(() => ToolTip(), -3000)
}

SCW_Undo(targetHwnd := 0) {
    hwnd := targetHwnd ? targetHwnd : WinExist("A")
    if !ClipWins.Has(hwnd)
        return
    winInfo := ClipWins[hwnd]
    if (winInfo.UndoStack.Length > 0) {
        popped := winInfo.UndoStack.Pop()
        Gdip_DisposeImage(winInfo.pBitmap)
        winInfo.pBitmap := popped

        hBitmap := Gdip_CreateHBITMAPFromBitmap(winInfo.pBitmap)
        winInfo.picCtrl.Value := "HBITMAP:*" hBitmap
        DllCall("DeleteObject", "ptr", hBitmap)
    } else {
        ToolTip("⚠️ 되돌릴 작업이 없습니다.`r`n⚠️ Nothing to undo.")
        SetTimer(() => ToolTip(), -2000)
    }
}

SCW_CloseWin() {
    hwnd := WinExist("A")
    if ClipWins.Has(hwnd) {
        CloseClipWin(ClipWins[hwnd].gui)
    }
}

WM_RBUTTONDOWN(wParam, lParam, msg, hwnd) {
    if !ClipWins.Has(hwnd)
        return
    global RightClickedHwnd := hwnd

    if (ClipWins[hwnd].UndoStack.Length > 0)
        ClipMenu.Enable("↩️ 7. Undo Draw (Ctrl+Z)")
    else
        ClipMenu.Disable("↩️ 7. Undo Draw (Ctrl+Z)")

    ClipMenu.Show()
}

MenuHandler(ItemName, ItemPos, MyMenu) {
    global RightClickedHwnd
    if !ClipWins.Has(RightClickedHwnd)
        return

    pBitmap := ClipWins[RightClickedHwnd].pBitmap

    if InStr(ItemName, "Translate:") {
        sl := "en"
        tl := "ko"
        ocrLang := "en-US"

        if InStr(ItemName, "PL to KR") {
            sl := "pl", tl := "ko", ocrLang := "pl-PL"
        } else if InStr(ItemName, "EN to KR") {
            sl := "en", tl := "ko", ocrLang := "en-US"
        } else if InStr(ItemName, "PL to EN") {
            sl := "pl", tl := "en", ocrLang := "pl-PL"
        } else if InStr(ItemName, "KR to PL") {
            sl := "ko", tl := "pl", ocrLang := "ko-KR"
        } else if InStr(ItemName, "EN to PL") {
            sl := "en", tl := "pl", ocrLang := "en-US"
        } else if InStr(ItemName, "KR to EN") {
            sl := "ko", tl := "en", ocrLang := "ko-KR"
        }

        try {
            result := OCR.FromBitmap(pBitmap, { lang: ocrLang })
            text := result.Text
            if (text == "") {
                ToolTip("⚠️ 인식된 텍스트가 없습니다.`r`n⚠️ No text recognized.")
                SetTimer(() => ToolTip(), -3000)
                return
            }
            url := "https://translate.google.com/?sl=" sl "&tl=" tl "&text=" UriEncode(text) "&op=translate"
            Run(url)
        } catch {
            ToolTip("❌ OCR 오류: 언어팩(" ocrLang ")을 확인하세요.`r`n❌ OCR Error: Check language pack (" ocrLang ")")
            SetTimer(() => ToolTip(), -3000)
        }
    }
    else if InStr(ItemName, "Copy To Paint") {
        tempFile := A_Temp "\temp_clip.png"
        Gdip_SaveBitmapToFile(pBitmap, tempFile)
        Run("mspaint.exe `"" tempFile "`"")
    }
    else if InStr(ItemName, "Save to Desktop") {
        pBordered := AddBorderToBitmap(pBitmap)
        TodayDate := FormatTime(, "yyyy-MM-dd_HHmmss")
        FileOut := A_Desktop "\" TodayDate ".PNG"
        Gdip_SaveBitmapToFile(pBordered, FileOut)
        Gdip_DisposeImage(pBordered)
        ToolTip("✅ 바탕화면에 저장 완료`r`n✅ Saved to Desktop:`r`n" FileOut)
        SetTimer(() => ToolTip(), -3000)
    }
    else if InStr(ItemName, "Copy to Clipboard") {
        if (CLIP_SCALE != 1.0) {
            pScaled := ResizeBitmap(pBitmap, CLIP_SCALE)
            pBordered := AddBorderToBitmap(pScaled)
            Gdip_DisposeImage(pScaled)
        } else {
            pBordered := AddBorderToBitmap(pBitmap)
        }
        Gdip_SetBitmapToClipboard(pBordered)
        finalW := Gdip_GetImageWidth(pBordered)
        finalH := Gdip_GetImageHeight(pBordered)
        Gdip_DisposeImage(pBordered)
        ToolTip("✅ 캡처 완료 (" finalW "×" finalH ") + 클립보드 복사`r`n✅ Copied to clipboard (" finalW "x" finalH ")")
        SetTimer(() => ToolTip(), -2000)
    }
    else if InStr(ItemName, "Undo Draw") {
        SCW_Undo(RightClickedHwnd)
    }
}

; ── 이미지 테두리 추가 헬퍼 (클립보드/저장 시 1px 검정 실선) ──
AddBorderToBitmap(pBitmap) {
    w := Gdip_GetImageWidth(pBitmap)
    h := Gdip_GetImageHeight(pBitmap)
    pNew := Gdip_CreateBitmap(w, h)
    pGraphics := Gdip_GraphicsFromImage(pNew)
    Gdip_DrawImage(pGraphics, pBitmap, 0, 0, w, h)
    pPen := Gdip_CreatePen("0xFF000000", 1)
    Gdip_DrawRectangle(pGraphics, pPen, 0, 0, w - 1, h - 1)
    Gdip_DeletePen(pPen)
    Gdip_DeleteGraphics(pGraphics)
    return pNew
}

UriEncode(Uri) {
    buf := Buffer(StrPut(Uri, "UTF-8"), 0)
    StrPut(Uri, buf, "UTF-8")
    Res := ""
    loop buf.Size - 1 {
        Code := NumGet(buf, A_Index - 1, "UChar")
        if (Code >= 0x30 && Code <= 0x39 || Code >= 0x41 && Code <= 0x5A || Code >= 0x61 && Code <= 0x7A || InStr(
            "-._~", Chr(Code)))
            Res .= Chr(Code)
        else
            Res .= Format("%{:02X}", Code)
    }
    return Res
}

; ── 클립보드 이미지 리사이징 헬퍼 ──
ResizeBitmap(pBitmap, scale) {
    w := Gdip_GetImageWidth(pBitmap)
    h := Gdip_GetImageHeight(pBitmap)
    newW := Round(w * scale)
    newH := Round(h * scale)

    pNew := Gdip_CreateBitmap(newW, newH)
    pGraphics := Gdip_GraphicsFromImage(pNew)
    Gdip_SetInterpolationMode(pGraphics, 7) ; 7 = HighQualityBicubic
    Gdip_DrawImage(pGraphics, pBitmap, 0, 0, newW, newH, 0, 0, w, h)
    Gdip_DeleteGraphics(pGraphics)
    return pNew
}

; ── 스케일 메뉴 업데이트 및 저장 ──
SetClipScale(scale) {
    global CLIP_SCALE, REG_PATH
    CLIP_SCALE := scale
    RegWrite(String(scale), "REG_SZ", REG_PATH, "Scale")
    UpdateScaleMenu()
}

UpdateScaleMenu() {
    global CLIP_SCALE
    ScaleMenu.Uncheck("50%")
    ScaleMenu.Uncheck("60%")
    ScaleMenu.Uncheck("70%")
    ScaleMenu.Uncheck("80%")
    ScaleMenu.Uncheck("90%")
    ScaleMenu.Uncheck("100%")
    ScaleMenu.Uncheck("150%")

    if (CLIP_SCALE == 0.5)
        ScaleMenu.Check("50%")
    else if (CLIP_SCALE == 0.6)
        ScaleMenu.Check("60%")
    else if (CLIP_SCALE == 0.7)
        ScaleMenu.Check("70%")
    else if (CLIP_SCALE == 0.8)
        ScaleMenu.Check("80%")
    else if (CLIP_SCALE == 0.9)
        ScaleMenu.Check("90%")
    else if (CLIP_SCALE == 1.5)
        ScaleMenu.Check("150%")
    else
        ScaleMenu.Check("100%")
}

SCW_MinimizeAll() {
    for hwnd, winInfo in ClipWins {
        if !winInfo.IsMinimized {
            WinGetPos(&oX, &oY, , , "ahk_id " hwnd)
            winInfo.orgX := oX
            winInfo.orgY := oY
            WinMove(, , MINI_SIZE, MINI_SIZE, hwnd)
            WinSetTransparent(MINI_OPACITY, hwnd)
            winInfo.NumBg.Visible := true
            winInfo.NumText.Visible := true
            winInfo.NumText.Redraw()
            winInfo.IsMinimized := true
        }
    }
}

SCW_RestoreAll() {
    for hwnd, winInfo in ClipWins {
        if winInfo.IsMinimized {
            WinMove(winInfo.orgX, winInfo.orgY, winInfo.w + BORDER_WIDTH * 2, winInfo.h + BORDER_WIDTH * 2, hwnd)
            WinSetTransparent("Off", hwnd)
            winInfo.NumText.Visible := false
            winInfo.NumBg.Visible := false
            winInfo.IsMinimized := false
        }
    }
}

SCW_CloseAll() {
    ; Map을 순회하며 모든 윈도우 닫기
    targetHwnds := []
    for hwnd, info in ClipWins
        targetHwnds.Push(info.gui)

    for guiObj in targetHwnds
        CloseClipWin(guiObj)

    ToolTip("✅ 모든 캡처 창 닫기 완료`r`n✅ All clips closed.")
    SetTimer(() => ToolTip(), -2000)
}

/**
 * 활성화된 모든 플로팅 캡처 창을 모니터상에 순차 정렬(계단식 캐스케이드) 배치하는 알고리즘 함수
 * Cascade-sorts all active floating capture windows neatly across connected monitors.
 * @returns {None}
 */
SCW_SortCascade() {
    static currentMonitor := 0  ; 모니터 토글 상태

    arr := []
    for hwnd, winInfo in ClipWins {
        arr.Push(winInfo)
    }

    n := arr.Length
    if (n == 0)
        return

    ; 모니터 개수 확인 및 순환
    monCount := MonitorGetCount()
    currentMonitor := Mod(currentMonitor, monCount) + 1  ; 1 → 2 → ... → 1

    ; 선택된 모니터의 왼쪽 상단 좌표 가져오기
    MonitorGet(currentMonitor, &monLeft, &monTop)

    ; ID 순으로 정렬 (버블 정렬)
    loop n {
        i := 1
        while (i < n) {
            if (arr[i].id > arr[i + 1].id) {
                temp := arr[i]
                arr[i] := arr[i + 1]
                arr[i + 1] := temp
            }
            i++
        }
    }

    ; 선택된 모니터의 왼쪽 상단 기준으로 캐스케이드 배치
    for index, winInfo in arr {
        x := monLeft + (n - index) * MINI_SIZE
        y := monTop + (index - 1) * MINI_SIZE
        WinMove(x, y, , , winInfo.gui.Hwnd)
        WinMoveTop("ahk_id " winInfo.gui.Hwnd)
    }

    ToolTip("📐 모니터 " currentMonitor "/" monCount " 정렬`r`n📐 Sorted to Monitor " currentMonitor "/" monCount)
    SetTimer(() => ToolTip(), -1500)
}
