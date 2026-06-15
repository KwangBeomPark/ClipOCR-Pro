#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Gdip_All.ahk

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

; ── config.ini 기본 설정 ──
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

; ── Windows 설정 저장소(Registry)에 보관하는 사용자 설정 ──
global REG_PATH := "HKCU\Software\ScreenClipTool"
global CLIP_SCALE := 1.0
global TEXT_TRANSLATE_LANG := "ko"
global TEXT_TRANSLATE_HOTKEY := "#CapsLock"

; ── 실행 중 상태값: 메뉴 이름, 열린 창 ID, Annotation 모드, 마지막 텍스트 선택 창 ──
global TRAY_TEXT_TRANSLATE_ITEM := ""
global TextTranslatePopupHwnd := 0
global SettingsHwnd := 0
global ANNOTATION_MODE := ""
global ANNOTATION_TARGET_HWND := 0
global TEXT_SOURCE_LAST_HWND := 0

try {
    CLIP_SCALE := Float(RegRead(REG_PATH, "Scale"))
} catch {
    CLIP_SCALE := 1.0
}

try {
    savedLang := RegRead(REG_PATH, "TranslateLang")
    if IsTextTranslateLangSupported(savedLang)
        TEXT_TRANSLATE_LANG := savedLang
} catch {
    TEXT_TRANSLATE_LANG := "ko"
}

try {
    savedHotkey := RegRead(REG_PATH, "TranslateHotkey")
    if IsTextTranslateHotkeySupported(savedHotkey)
        TEXT_TRANSLATE_HOTKEY := savedHotkey
} catch {
    TEXT_TRANSLATE_HOTKEY := "#CapsLock"
}

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
TRAY_TEXT_TRANSLATE_ITEM := "🌐 Translate Selected Text (" GetTextTranslateHotkeyLabel(TEXT_TRANSLATE_HOTKEY) ")"
Tray.Add(TRAY_TEXT_TRANSLATE_ITEM, (*) => TranslateSelectedText(true))
Tray.Add("⚙️ Settings", (*) => ShowSettingsDialog())
Tray.Add()
Tray.Add("📐 Sort All Clips (Ctrl+Left)", (*) => SCW_SortCascade())
Tray.Add("🔽 Minimize All (Ctrl+Up)", (*) => SCW_MinimizeAll())
Tray.Add("🔼 Restore All (Ctrl+Down)", (*) => SCW_RestoreAll())
Tray.Add("❌ Close All Clips (Ctrl+Esc)", (*) => SCW_CloseAll())
Tray.Add()
Tray.Add("ℹ️ About App", (*) => ShowAboutDialog())
Tray.Add("🔄 Reload Script", (*) => Reload())
Tray.Add("🚪 Exit App", (*) => ExitApp())

; ── 캡처 창과 우클릭 메뉴 상태 ──
global ClipWins := Map()
global RightClickedHwnd := 0
global ClipMenu := Menu()

global bmcBtnPath := A_Temp "\bmc_btn.png"
global AboutHwnd := 0

; Background download of Buy Me a Coffee button image
SetTimer(DownloadBmcButton, -100)

DownloadBmcButton() {
    global bmcBtnPath
    if !FileExist(bmcBtnPath) {
        try {
            Download("https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png", bmcBtnPath)
        }
    }
}

; Google Image 번역 서브메뉴 (타겟 언어 선택)
ImgTransMenu := Menu()
ImgTransMenu.Add("🇰🇷 Translate to Korean", (*) => GoogleImageTranslate("ko"))
ImgTransMenu.Add("🇬🇧 Translate to English", (*) => GoogleImageTranslate("en"))
ImgTransMenu.Add("🇵🇱 Translate to Polish", (*) => GoogleImageTranslate("pl"))

ClipMenu.Add("🌐 1. Google Translate (Image)", ImgTransMenu)
ClipMenu.Add() ; Separator

ClipMenu.Add("🟥 2. Red Box (Shift+Drag)", MenuHandler)
ClipMenu.Add("🟨 3. Yellow Highlight (Ctrl+Drag)", MenuHandler)
ClipMenu.Add("🟩 4. Green Highlight (Alt+Drag)", MenuHandler)
ClipMenu.Add("↩️ 5. Undo Draw (Ctrl+Z)", MenuHandler)
ClipMenu.Add() ; Separator

ClipMenu.Add("📋 6. Copy to Clipboard (Ctrl+C)", MenuHandler)
ClipMenu.Add("💾 7. Save to Desktop (Ctrl+S)", MenuHandler)
ClipMenu.Add("🎨 8. Copy To Paint", MenuHandler)
ClipMenu.Add() ; Separator

; 9. 클립보드 스케일 서브메뉴
ScaleMenu := Menu()
ScaleMenu.Add("50%", (*) => SetClipScale(0.5))
ScaleMenu.Add("60%", (*) => SetClipScale(0.6))
ScaleMenu.Add("70%", (*) => SetClipScale(0.7))
ScaleMenu.Add("80%", (*) => SetClipScale(0.8))
ScaleMenu.Add("90%", (*) => SetClipScale(0.9))
ScaleMenu.Add("100%", (*) => SetClipScale(1.0))
ScaleMenu.Add("150%", (*) => SetClipScale(1.5))
UpdateScaleMenu()

ClipMenu.Add("⚙️ 9. Clipboard Scale", ScaleMenu)
ClipMenu.Add() ; Separator
ClipMenu.Add("📐 10. Sort All Clips (Ctrl+Left)", (*) => SCW_SortCascade())
ClipMenu.Add("🔽 11. Minimize All (Ctrl+Up)", (*) => SCW_MinimizeAll())
ClipMenu.Add("🔼 12. Restore All (Ctrl+Down)", (*) => SCW_RestoreAll())
ClipMenu.Add("❌ 13. Close All Clips (Ctrl+Esc)", (*) => SCW_CloseAll())
ClipMenu.Add("ℹ️ 14. App Info", (*) => ShowAboutDialog())

; ── 시작 시 환영 툴팁 ──
ToolTip("📸 Screen Clip Tool Ready!`r`nWin+드래그: 캡처`r`n" GetTextTranslateHotkeyLabel(TEXT_TRANSLATE_HOTKEY) ": 선택 텍스트 번역")
SetTimer(() => ToolTip(), -4000)

SetTimer(TrackLastTextSourceWindow, 250)
ApplyTextTranslateHotkey()

; Hotkeys
#LButton:: ScreenClip2Win(1)  ; Win+LButton -> floating clip + auto copy to clipboard
#CapsLock:: TranslateSelectedText(false) ; 기본 선택 텍스트 번역 단축키

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
 * 선택한 화면 영역을 Google 이미지 번역 페이지로 보냅니다.
 * Sends a selected screen area to Google Translate Image.
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

TrackLastTextSourceWindow() {
    global TEXT_SOURCE_LAST_HWND
    hwnd := WinExist("A")
    if !IsTextSourceWindow(hwnd)
        return
    TEXT_SOURCE_LAST_HWND := hwnd
}

IsTextSourceWindow(hwnd) {
    if !hwnd
        return false

    try className := WinGetClass("ahk_id " hwnd)
    catch
        return false

    if (className == "AutoHotkeyGUI" || className == "#32768" || className == "Shell_TrayWnd"
        || className == "NotifyIconOverflowWindow" || className == "WorkerW" || className == "Progman")
        return false

    return true
}

GetCopySourceHwnd(fromTray := false) {
    global TEXT_SOURCE_LAST_HWND
    activeHwnd := WinExist("A")
    if (!fromTray && IsTextSourceWindow(activeHwnd))
        return activeHwnd
    if (IsTextSourceWindow(TEXT_SOURCE_LAST_HWND) && WinExist("ahk_id " TEXT_SOURCE_LAST_HWND))
        return TEXT_SOURCE_LAST_HWND
    return IsTextSourceWindow(activeHwnd) ? activeHwnd : 0
}

TranslateSelectedText(fromTray := false) {
    global TEXT_TRANSLATE_LANG
    sourceHwnd := GetCopySourceHwnd(fromTray)
    clipSaved := ClipboardAll()
    try {
        if sourceHwnd {
            WinActivate("ahk_id " sourceHwnd)
            WinWaitActive("ahk_id " sourceHwnd, , 0.6)
            Sleep(80)
        }

        A_Clipboard := ""
        Send("^c")

        if !ClipWait(0.7) {
            Sleep(80)
            SendInput("^c")
        }

        if !ClipWait(0.8) {
            ToolTip("⚠️ 선택 텍스트를 복사하지 못했습니다.`r`n텍스트를 선택한 앱이 활성화되어 있는지 확인하세요.")
            SetTimer(() => ToolTip(), -2500)
            return
        }

        sourceText := Trim(A_Clipboard, "`r`n `t")
        if (sourceText == "") {
            ToolTip("⚠️ 선택된 텍스트가 없습니다.`r`n⚠️ No selected text.")
            SetTimer(() => ToolTip(), -2500)
            return
        }

        ToolTip("🌐 번역 중...`r`n🌐 Translating...")
        translatedText := TranslateTextViaGoogle(sourceText, TEXT_TRANSLATE_LANG)
        ToolTip()
        ShowTextTranslationPopup(sourceText, translatedText)
    } catch as e {
        ToolTip("❌ 번역 실패: " e.Message "`r`n❌ Translation failed.")
        SetTimer(() => ToolTip(), -3500)
    } finally {
        A_Clipboard := clipSaved
    }
}

TranslateTextViaGoogle(text, targetLang) {
    url := "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl="
        . targetLang . "&dt=t&q=" . UriEncode(text)

    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.Open("GET", url, false)
    http.SetTimeouts(1200, 1200, 1200, 3000)
    http.SetRequestHeader("User-Agent", "Mozilla/5.0")
    http.Send()

    if (http.Status != 200)
        throw Error("HTTP " http.Status)

    result := ParseGoogleTranslateResponse(http.ResponseText)
    if (result == "")
        throw Error("Empty result")

    return result
}

ParseGoogleTranslateResponse(json) {
    if (SubStr(json, 1, 3) != "[[[")
        return ""

    pos := 4
    len := StrLen(json)
    text := ""

    while (pos <= len) {
        ; 번역 결과 배열의 첫 번째 문자열만 순서대로 이어 붙인다.
        char := SubStr(json, pos, 1)
        if (char == "`"") {
            pos++
            str := ""
            while (pos <= len) {
                c := SubStr(json, pos, 1)
                if (c == "\") {
                    str .= "\" . SubStr(json, pos + 1, 1)
                    pos += 2
                } else if (c == "`"") {
                    pos++
                    break
                } else {
                    str .= c
                    pos++
                }
            }
            text .= JsonUnescape(str)

            ; 같은 문장 조각 안의 원문/발음 정보는 건너뛴다.
            bracketCount := 1
            inString := false
            while (pos <= len && bracketCount > 0) {
                c := SubStr(json, pos, 1)
                if (inString) {
                    if (c == "\")
                        pos += 2
                    else if (c == "`"") {
                        inString := false
                        pos++
                    } else {
                        pos++
                    }
                } else {
                    if (c == "`"") {
                        inString := true
                        pos++
                    } else if (c == "[") {
                        bracketCount++
                        pos++
                    } else if (c == "]") {
                        bracketCount--
                        pos++
                    } else {
                        pos++
                    }
                }
            }
        } else {
            if (char == "]") {
                break
            }
            pos++
        }

        ; 다음 번역 조각으로 이동한다.
        nextSegFound := false
        while (pos <= len) {
            c := SubStr(json, pos, 1)
            if (c == "[") {
                pos++
                nextSegFound := true
                break
            } else if (c == "]") {
                break 2
            }
            pos++
        }
        if (!nextSegFound)
            break
    }
    return text
}

JsonUnescape(text) {
    out := "", i := 1
    while (i <= StrLen(text)) {
        ch := SubStr(text, i, 1)
        if (ch != "\") {
            out .= ch, i++
            continue
        }

        i++, esc := SubStr(text, i, 1)
        if (esc == "n")
            out .= "`n"
        else if (esc == "r")
            out .= "`r"
        else if (esc == "t")
            out .= A_Tab
        else if (esc == "b")
            out .= Chr(8)
        else if (esc == "f")
            out .= Chr(12)
        else if (esc == "u") {
            hex := SubStr(text, i + 1, 4)
            if RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                out .= Chr(Integer("0x" hex)), i += 4
        } else {
            out .= esc
        }
        i++
    }
    return out
}

ShowTextTranslationPopup(sourceText, translatedText) {
    global TextTranslatePopupHwnd, TEXT_TRANSLATE_LANG

    if (TextTranslatePopupHwnd && WinExist("ahk_id " TextTranslatePopupHwnd))
        WinClose("ahk_id " TextTranslatePopupHwnd)

    PopGui := Gui("+AlwaysOnTop +ToolWindow +Border +Resize -DPIScale +MinSize320x200", "Translation by Google")
    PopGui.BackColor := "1E1E24"
    PopGui.SetFont("s9", "Segoe UI")

    ; ── 상단: 제목 + 임시 번역 언어 선택 ──
    TitleLabel := PopGui.Add("Text", "x14 y12 w220 h22 +BackgroundTrans cFFFFFF", "🌐 Translation by Google")
    TitleLabel.SetFont("s10 Bold", "Segoe UI")

    langItems := ["ORIGINAL"]
    for _, label in GetTextTranslateLangLabels()
        langItems.Push(label)
    initialIdx := GetTextTranslateLangIndex(TEXT_TRANSLATE_LANG) + 1
    LangCombo := PopGui.Add("DropDownList", "x250 y9 w156 Choose" initialIdx, langItems)

    ; ── 구분선 ──
    SepLine := PopGui.Add("Text", "x14 y38 w392 h1 Background3F3F46", "")

    ; ── 번역 결과 텍스트 박스 (단일, 읽기전용, 멀티라인, 스크롤) ──
    ResultEdit := PopGui.Add("Edit", "x14 y46 w392 h164 ReadOnly +Multi +VScroll", translatedText)

    ; ── 하단 버튼 ──
    CopyBtn := PopGui.Add("Button", "x218 y220 w90 h30", "Copy")
    CloseBtn := PopGui.Add("Button", "x316 y220 w90 h30", "Close")

    ; 현재 표시 중인 텍스트 (Copy용, 클로저 간 공유)
    currentText := translatedText

    ; ── 콤보박스 변경 → 자동 재번역 ──
    OnLangChange(*) {
        selected := LangCombo.Text
        if (selected == "ORIGINAL") {
            currentText := sourceText
            ResultEdit.Value := sourceText
        } else {
            targetLang := GetTextTranslateLangCodeByLabel(selected)
            ResultEdit.Value := "🌐 Translating..."
            try {
                translated := TranslateTextViaGoogle(sourceText, targetLang)
                currentText := translated
                ResultEdit.Value := translated
            } catch as e {
                currentText := ""
                ResultEdit.Value := "❌ Translation failed: " e.Message
            }
        }
    }
    LangCombo.OnEvent("Change", OnLangChange)

    ; ── Copy 버튼 ──
    CopyTranslated(*) {
        A_Clipboard := currentText
        ToolTip("✅ 번역 결과 복사 완료`r`n✅ Translation copied.")
        SetTimer(() => ToolTip(), -1500)
    }

    ; ── 닫기 처리 ──
    DestroyPopup(*) {
        global TextTranslatePopupHwnd := 0
        PopGui.Destroy()
    }

    CopyBtn.OnEvent("Click", CopyTranslated)
    CloseBtn.OnEvent("Click", DestroyPopup)
    PopGui.OnEvent("Close", DestroyPopup)
    PopGui.OnEvent("Escape", DestroyPopup)

    ; ── Resize 핸들러: 컨트롤 위치·크기 동적 조절 ──
    OnPopupResize(thisGui, MinMax, Width, Height) {
        if (MinMax == -1)  ; 최소화 상태면 크기 조정 생략
            return
        m := 14
        LangCombo.Move(Width - 170, 9, 156)
        SepLine.Move(m, 38, Width - m * 2)
        ResultEdit.Move(m, 46, Width - m * 2, Height - 46 - 50)
        CopyBtn.Move(Width - 202, Height - 40, 90, 30)
        CloseBtn.Move(Width - 104, Height - 40, 90, 30)
    }
    PopGui.OnEvent("Size", OnPopupResize)

    ; ── 마우스 커서 근처에 표시 ──
    MouseGetPos(&mx, &my)
    popupW := 420
    popupH := 360
    workLeft := 0, workTop := 0, workRight := A_ScreenWidth, workBottom := A_ScreenHeight
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
        if (mx >= mLeft && mx <= mRight && my >= mTop && my <= mBottom) {
            workLeft := mLeft, workTop := mTop, workRight := mRight, workBottom := mBottom
            break
        }
    }
    xMax := Max(workLeft, workRight - popupW)
    yMax := Max(workTop, workBottom - popupH)
    x := Min(Max(mx + 16, workLeft), xMax)
    y := Min(Max(my + 16, workTop), yMax)
    PopGui.Show("x" x " y" y " w" popupW " h" popupH)
    OnPopupResize(PopGui, 0, popupW, popupH)
    TextTranslatePopupHwnd := PopGui.Hwnd
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
    global AboutHwnd, ANNOTATION_MODE, ANNOTATION_TARGET_HWND
    if (AboutHwnd && hwnd == AboutHwnd) {
        PostMessage 0xA1, 2, , , "ahk_id " hwnd
        return
    }
    if !ClipWins.Has(hwnd)
        return

    static LastClickTime := 0
    static LastClickHwnd := 0

    winInfo := ClipWins[hwnd]

    if (ANNOTATION_MODE != "" && hwnd == ANNOTATION_TARGET_HWND) {
        mode := ANNOTATION_MODE
        ANNOTATION_MODE := ""
        ANNOTATION_TARGET_HWND := 0
        SetTimer(ClearAnnotationMode, 0)
        ToolTip()
        SCW_ApplyAnnotation(hwnd, mode)
        return
    }

    ; --- 그리기 모드 (Shift: 빨간 네모, Ctrl: 노랑 형광펜, Alt: 초록 형광펜) ---
    if GetKeyState("Shift", "P") || GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") {
        if GetKeyState("Shift", "P")
            SCW_ApplyAnnotation(hwnd, "Red")
        else if GetKeyState("Ctrl", "P") {
            SCW_ApplyAnnotation(hwnd, "Yellow")
        } else if GetKeyState("Alt", "P")
            SCW_ApplyAnnotation(hwnd, "Green")
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

SCW_ApplyAnnotation(hwnd, mode) {
    if !ClipWins.Has(hwnd)
        return

    winInfo := ClipWins[hwnd]
    WinGetPos(&winX, &winY, , , "ahk_id " hwnd)

    if (mode == "Red")
        rect := DrawRectPreview("Red")
    else if (mode == "Yellow")
        rect := DrawRectPreview("Yellow", false)
    else if (mode == "Green")
        rect := DrawRectPreview("Lime", false)
    else
        return

    if (rect.w <= 0 || rect.h <= 0)
        return

    clone := Gdip_CloneBitmapArea(winInfo.pBitmap, 0, 0, winInfo.w, winInfo.h)
    winInfo.UndoStack.Push(clone)
    if (winInfo.UndoStack.Length > UNDO_MAX) {
        oldest := winInfo.UndoStack.RemoveAt(1)
        Gdip_DisposeImage(oldest)
    }

    rectX := rect.x - (winX + BORDER_WIDTH)
    rectY := rect.y - (winY + BORDER_WIDTH)
    pGraphics := Gdip_GraphicsFromImage(winInfo.pBitmap)

    if (mode == "Red") {
        pPen := Gdip_CreatePen("0xFFFF0000", BORDER_WIDTH)
        Gdip_DrawRectangle(pGraphics, pPen, rectX, rectY, rect.w, rect.h)
        Gdip_DeletePen(pPen)
    } else if (mode == "Yellow") {
        pBrush := Gdip_BrushCreateSolid("0x77FFFF00")
        Gdip_FillRectangle(pGraphics, pBrush, rectX, rectY, rect.w, rect.h)
        Gdip_DeleteBrush(pBrush)
    } else if (mode == "Green") {
        pBrush := Gdip_BrushCreateSolid("0x7700FF00")
        Gdip_FillRectangle(pGraphics, pBrush, rectX, rectY, rect.w, rect.h)
        Gdip_DeleteBrush(pBrush)
    }
    Gdip_DeleteGraphics(pGraphics)

    hBitmap := Gdip_CreateHBITMAPFromBitmap(winInfo.pBitmap)
    winInfo.picCtrl.Value := "HBITMAP:*" hBitmap
    DllCall("DeleteObject", "ptr", hBitmap)
}

StartAnnotationMode(mode) {
    global ANNOTATION_MODE, ANNOTATION_TARGET_HWND, RightClickedHwnd
    if !ClipWins.Has(RightClickedHwnd)
        return

    ANNOTATION_MODE := mode
    ANNOTATION_TARGET_HWND := RightClickedHwnd
    WinActivate("ahk_id " ANNOTATION_TARGET_HWND)
    ToolTip("📝 마우스로 영역을 드래그하세요.`r`n📝 Drag an area on the clip.")
    SetTimer(ClearAnnotationMode, 0)
    SetTimer(ClearAnnotationMode, -10000)
}

ClearAnnotationMode() {
    global ANNOTATION_MODE, ANNOTATION_TARGET_HWND
    ANNOTATION_MODE := ""
    ANNOTATION_TARGET_HWND := 0
    ToolTip()
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
        ClipMenu.Enable("↩️ 5. Undo Draw (Ctrl+Z)")
    else
        ClipMenu.Disable("↩️ 5. Undo Draw (Ctrl+Z)")

    ClipMenu.Show()
}

MenuHandler(ItemName, ItemPos, MyMenu) {
    global RightClickedHwnd
    if !ClipWins.Has(RightClickedHwnd)
        return

    pBitmap := ClipWins[RightClickedHwnd].pBitmap

    if InStr(ItemName, "Red Box") {
        StartAnnotationMode("Red")
    }
    else if InStr(ItemName, "Yellow Highlight") {
        StartAnnotationMode("Yellow")
    }
    else if InStr(ItemName, "Green Highlight") {
        StartAnnotationMode("Green")
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

GetScaleLabels() {
    return ["50%", "60%", "70%", "80%", "90%", "100%", "150%"]
}

GetScaleIndex(scale) {
    scales := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.5]
    for index, value in scales {
        if (Abs(scale - value) < 0.001)
            return index
    }
    return 6
}

GetScaleFromLabel(label) {
    return Float(StrReplace(label, "%")) / 100
}

GetTextTranslateLangOptions() {
    return [
        { label: "한국어 (ko)", code: "ko" },
        { label: "영어 (en)", code: "en" },
        { label: "폴란드어 (pl)", code: "pl" },
        { label: "알바니아어 (sq)", code: "sq" },
        { label: "아르메니아어 (hy)", code: "hy" },
        { label: "아제르바이잔어 (az)", code: "az" },
        { label: "바스크어 (eu)", code: "eu" },
        { label: "벨라루스어 (be)", code: "be" },
        { label: "보스니아어 (bs)", code: "bs" },
        { label: "불가리아어 (bg)", code: "bg" },
        { label: "카탈루냐어 (ca)", code: "ca" },
        { label: "코르시카어 (co)", code: "co" },
        { label: "크로아티아어 (hr)", code: "hr" },
        { label: "체코어 (cs)", code: "cs" },
        { label: "덴마크어 (da)", code: "da" },
        { label: "네덜란드어 (nl)", code: "nl" },
        { label: "에스페란토 (eo)", code: "eo" },
        { label: "에스토니아어 (et)", code: "et" },
        { label: "핀란드어 (fi)", code: "fi" },
        { label: "프랑스어 (fr)", code: "fr" },
        { label: "프리지아어 (fy)", code: "fy" },
        { label: "갈리시아어 (gl)", code: "gl" },
        { label: "조지아어 (ka)", code: "ka" },
        { label: "독일어 (de)", code: "de" },
        { label: "그리스어 (el)", code: "el" },
        { label: "헝가리어 (hu)", code: "hu" },
        { label: "아이슬란드어 (is)", code: "is" },
        { label: "아일랜드어 (ga)", code: "ga" },
        { label: "이탈리아어 (it)", code: "it" },
        { label: "라틴어 (la)", code: "la" },
        { label: "라트비아어 (lv)", code: "lv" },
        { label: "리투아니아어 (lt)", code: "lt" },
        { label: "룩셈부르크어 (lb)", code: "lb" },
        { label: "마케도니아어 (mk)", code: "mk" },
        { label: "몰타어 (mt)", code: "mt" },
        { label: "노르웨이어 (no)", code: "no" },
        { label: "포르투갈어 (pt)", code: "pt" },
        { label: "루마니아어 (ro)", code: "ro" },
        { label: "러시아어 (ru)", code: "ru" },
        { label: "스코틀랜드 게일어 (gd)", code: "gd" },
        { label: "세르비아어 (sr)", code: "sr" },
        { label: "슬로바키아어 (sk)", code: "sk" },
        { label: "슬로베니아어 (sl)", code: "sl" },
        { label: "스페인어 (es)", code: "es" },
        { label: "스웨덴어 (sv)", code: "sv" },
        { label: "튀르키예어 (tr)", code: "tr" },
        { label: "우크라이나어 (uk)", code: "uk" },
        { label: "웨일스어 (cy)", code: "cy" },
        { label: "이디시어 (yi)", code: "yi" }
    ]
}

GetTextTranslateLangLabels() {
    labels := []
    for _, option in GetTextTranslateLangOptions()
        labels.Push(option.label)
    return labels
}

IsTextTranslateLangSupported(lang) {
    for _, option in GetTextTranslateLangOptions() {
        if (option.code == lang)
            return true
    }
    return false
}

GetTextTranslateLangIndex(lang) {
    for index, option in GetTextTranslateLangOptions() {
        if (option.code == lang)
            return index
    }
    return 1
}

GetTextTranslateLangCodeByLabel(label) {
    for _, option in GetTextTranslateLangOptions() {
        if (option.label == label)
            return option.code
    }
    return "ko"
}

SetTextTranslateLang(lang) {
    global TEXT_TRANSLATE_LANG, REG_PATH
    if !IsTextTranslateLangSupported(lang)
        lang := "ko"
    TEXT_TRANSLATE_LANG := lang
    RegWrite(lang, "REG_SZ", REG_PATH, "TranslateLang")
}

GetTextTranslateHotkeyOptions() {
    return [
        { label: "Win + CapsLock", hotkey: "#CapsLock" },
        { label: "Win + Shift + CapsLock", hotkey: "#+CapsLock" },
        { label: "Win + Alt + CapsLock", hotkey: "#!CapsLock" },
        { label: "Ctrl + Alt + CapsLock", hotkey: "^!CapsLock" },
        { label: "Ctrl + Shift + CapsLock", hotkey: "^+CapsLock" }
    ]
}

GetTextTranslateHotkeyLabels() {
    labels := []
    for _, option in GetTextTranslateHotkeyOptions()
        labels.Push(option.label)
    return labels
}

IsTextTranslateHotkeySupported(hotkey) {
    for _, option in GetTextTranslateHotkeyOptions() {
        if (option.hotkey == hotkey)
            return true
    }
    return false
}

GetTextTranslateHotkeyIndex(hotkey) {
    for index, option in GetTextTranslateHotkeyOptions() {
        if (option.hotkey == hotkey)
            return index
    }
    return 1
}

GetTextTranslateHotkeyLabel(hotkey) {
    for _, option in GetTextTranslateHotkeyOptions() {
        if (option.hotkey == hotkey)
            return option.label
    }
    return "Win + CapsLock"
}

GetTextTranslateHotkeyByLabel(label) {
    for _, option in GetTextTranslateHotkeyOptions() {
        if (option.label == label)
            return option.hotkey
    }
    return "#CapsLock"
}

ApplyTextTranslateHotkey() {
    global TEXT_TRANSLATE_HOTKEY
    ; Win+CapsLock은 정적 단축키로 항상 등록되어 있으므로, 사용자가 다른 단축키를 고른 경우만 추가 등록한다.
    if (TEXT_TRANSLATE_HOTKEY == "#CapsLock")
        return
    try {
        Hotkey(TEXT_TRANSLATE_HOTKEY, (*) => TranslateSelectedText(false), "On")
    } catch as e {
        ToolTip("⚠️ 번역 단축키 설정 실패: " e.Message)
        SetTimer(() => ToolTip(), -3000)
    }
}

SetTextTranslateHotkey(hotkey) {
    global TEXT_TRANSLATE_HOTKEY, REG_PATH
    if !IsTextTranslateHotkeySupported(hotkey)
        hotkey := "#CapsLock"

    oldHotkey := TEXT_TRANSLATE_HOTKEY
    if (oldHotkey != hotkey) {
        if (oldHotkey != "#CapsLock")
            try Hotkey(oldHotkey, "Off")
        TEXT_TRANSLATE_HOTKEY := hotkey
        ApplyTextTranslateHotkey()
    }

    RegWrite(hotkey, "REG_SZ", REG_PATH, "TranslateHotkey")
    UpdateTrayTextTranslateMenuLabel()
}

UpdateTrayTextTranslateMenuLabel() {
    global Tray, TRAY_TEXT_TRANSLATE_ITEM, TEXT_TRANSLATE_HOTKEY
    newItem := "🌐 Translate Selected Text (" GetTextTranslateHotkeyLabel(TEXT_TRANSLATE_HOTKEY) ")"
    try Tray.Rename(TRAY_TEXT_TRANSLATE_ITEM, newItem)
    TRAY_TEXT_TRANSLATE_ITEM := newItem
}

ShowSettingsDialog() {
    global SettingsHwnd, CLIP_SCALE, TEXT_TRANSLATE_LANG, TEXT_TRANSLATE_HOTKEY

    if (SettingsHwnd && WinExist("ahk_id " SettingsHwnd)) {
        WinActivate("ahk_id " SettingsHwnd)
        return
    }

    SettingsGui := Gui("+AlwaysOnTop +ToolWindow +Border -DPIScale", "Settings")
    SettingsGui.BackColor := "1E1E24"
    SettingsGui.SetFont("s9", "Segoe UI")

    Tab := SettingsGui.Add("Tab3", "x12 y12 w496 h300", ["기본값"])
    Tab.UseTab(1)

    SettingsGui.Add("Text", "x32 y55 w420 h22 +BackgroundTrans cFFFFFF", "이미지 붙여넣기 기본값")
    SettingsGui.Add("Text", "x32 y84 w180 h22 +BackgroundTrans cCCCCCC", "클립보드 이미지 크기")
    ScaleCombo := SettingsGui.Add("DropDownList", "x220 y80 w150 Choose" GetScaleIndex(CLIP_SCALE), GetScaleLabels())

    SettingsGui.Add("Text", "x32 y130 w420 h22 +BackgroundTrans cFFFFFF", "선택 텍스트 번역 기본값")
    SettingsGui.Add("Text", "x32 y160 w180 h22 +BackgroundTrans cCCCCCC", "번역 단축키")
    HotkeyCombo := SettingsGui.Add("DropDownList", "x220 y156 w220 Choose" GetTextTranslateHotkeyIndex(TEXT_TRANSLATE_HOTKEY),
        GetTextTranslateHotkeyLabels())

    SettingsGui.Add("Text", "x32 y202 w180 h22 +BackgroundTrans cCCCCCC", "번역 결과 언어")
    LangCombo := SettingsGui.Add("DropDownList", "x220 y198 w220 Choose" GetTextTranslateLangIndex(TEXT_TRANSLATE_LANG),
        GetTextTranslateLangLabels())

    SaveBtn := SettingsGui.Add("Button", "x304 y326 w90 h30", "저장")
    CloseBtn := SettingsGui.Add("Button", "x404 y326 w90 h30", "닫기")

    SaveSettings(*) {
        SetClipScale(GetScaleFromLabel(ScaleCombo.Text))
        SetTextTranslateHotkey(GetTextTranslateHotkeyByLabel(HotkeyCombo.Text))
        SetTextTranslateLang(GetTextTranslateLangCodeByLabel(LangCombo.Text))
        ToolTip("✅ 설정 저장 완료`r`n✅ Settings saved.")
        SetTimer(() => ToolTip(), -1500)
    }

    DestroySettings(*) {
        global SettingsHwnd := 0
        SettingsGui.Destroy()
    }

    SaveBtn.OnEvent("Click", SaveSettings)
    CloseBtn.OnEvent("Click", DestroySettings)
    SettingsGui.OnEvent("Close", DestroySettings)
    SettingsGui.OnEvent("Escape", DestroySettings)

    SettingsGui.Show("w520 h370")
    SettingsHwnd := SettingsGui.Hwnd
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

/**
 * 앱 정보 및 커피 후원 안내 다이얼로그를 표시하는 함수
 * Displays the About App dialog with version, author, and coffee support details.
 * @returns {None}
 */
ShowAboutDialog() {
    global AboutHwnd, bmcBtnPath

    ; 이미 열려있으면 활성화하고 끝냄
    if AboutHwnd && WinExist("ahk_id " AboutHwnd) {
        WinActivate("ahk_id " AboutHwnd)
        return
    }

    AboutGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border -DPIScale", "About ScreenClip Tool")
    AboutGui.BackColor := "1E1E24"

    ; 타이틀바 배경 (너비 560으로 증가)
    AboutGui.Add("Text", "x0 y0 w560 h45 Background141416", "")

    ; 타이틀 텍스트
    TitleTxt := AboutGui.Add("Text", "x15 y12 w350 h25 +BackgroundTrans cWhite", "📸 About ScreenClip Tool")
    TitleTxt.SetFont("s11 Bold", "Segoe UI")

    ; 우측 상단 닫기 버튼 "×" (x525로 조정)
    CloseBtn := AboutGui.Add("Text", "x525 y10 w25 h25 Center +0x200 +BackgroundTrans cGray", "×")
    CloseBtn.SetFont("s16 Bold")

    DestroyAbout(*) {
        global AboutHwnd := 0
        AboutGui.Destroy()
    }

    CloseBtn.OnEvent("Click", DestroyAbout)

    ; 앱 제목 및 로고 (왼쪽 정렬)
    AppTitle := AboutGui.Add("Text", "x20 y65 w300 h35 +BackgroundTrans cWhite", "ScreenClip Tool")
    AppTitle.SetFont("s18 Bold", "Segoe UI")

    ; ── 상단 우측 노란색 flat Manual 버튼 (x440으로 조정) ──
    ManualBtn := AboutGui.Add("Text", "x440 y65 w100 h32 BackgroundFFDD00 c1E1E24 Center +0x200", "📖 Manual")
    ManualBtn.SetFont("s10 Bold", "Segoe UI")
    ManualBtn.OnEvent("Click", (*) => ShowManualDialog())

    AppSub := AboutGui.Add("Text", "x20 y105 w520 h20 +BackgroundTrans cGray", "Version 1.1.0 • Screen Capture, Annotation & Translation Tool")
    AppSub.SetFont("s9", "Segoe UI")

    ; 구분선
    AboutGui.Add("Text", "x20 y130 w520 h1 Background3F3F46", "")

    ; ── Windows 시작 시 자동 실행 강조 카드 ──
    AboutGui.Add("Text", "x20 y142 w520 h52 Background2A2D3C", "") ; 푸른빛이 도는 세련된 강조 카드 배경
    isStartup := IsStartupEnabled()
    StartupChk := AboutGui.Add("CheckBox", "x38 y153 w480 h30 Background2A2D3C cWhite" (isStartup ? " Checked" : ""), "  Run app when Windows starts (윈도우 시작 시 자동 등록)")
    StartupChk.SetFont("s10 Bold", "Segoe UI")
    StartupChk.OnEvent("Click", OnStartupToggle)

    OnStartupToggle(*) {
        if StartupChk.Value
            EnableStartup()
        else
            DisableStartup()
    }

    ; 개발자 정보 카드 (높이 150으로 컴팩트하게 재조정)
    AboutGui.Add("Text", "x20 y210 w520 h150 Background27272A", "")

    DevTitle := AboutGui.Add("Text", "x35 y220 w490 h20 +BackgroundTrans cWhite", "👤 Developer Info")
    DevTitle.SetFont("s10 Bold", "Segoe UI")

    DevText1 := AboutGui.Add("Text", "x35 y245 w370 h20 +BackgroundTrans cCCCCCC", "KBPark (Financial Specialist)")
    DevText1.SetFont("s9 Bold", "Segoe UI")

    DevText2 := AboutGui.Add("Text", "x35 y265 w370 h80 +BackgroundTrans cA0A0A0", "A finance professional passionate about office automation and daily productivity.`n`n👉 Click the GitHub cat icon on the right to view other office apps!")
    DevText2.SetFont("s9", "Segoe UI")

    ; ── GitHub 자동화 도구 링크 및 이미지 버튼 추가 (1:1 비율 아이콘 사용으로 찌그러짐 방지) ──

    githubIconPath := A_ScriptDir "\github_icon.png"
    try FileCopy("C:\Users\kwangbeom.park\.gemini\antigravity\brain\c4b06f63-9081-401a-96e9-829693c01253\github_icon_solid_1780569397341.png", githubIconPath, true)

    if FileExist(githubIconPath) {
        try {
            ; 더 크게 확대(w110 h110) 및 우측 여백에 맞춰 정렬 배치
            GithubPic := AboutGui.Add("Picture", "x415 y230 w110 h110 +BackgroundTrans", githubIconPath)
            GithubPic.OnEvent("Click", (*) => Run("https://github.com/KwangBeomPark"))
        } catch {
            ; ignore load error
        }
    }

    ; 커피 후원 카드 (위로 조금 당겨서 y380으로 조정, 높이 170)
    AboutGui.Add("Text", "x20 y380 w520 h170 Background2D2D35", "")

    SupportTitle := AboutGui.Add("Text", "x35 y390 w490 h20 +BackgroundTrans cFFDD00", "☕ Support This Project")
    SupportTitle.SetFont("s11 Bold", "Segoe UI")

    SupportText := AboutGui.Add("Text", "x35 y415 w490 h50 +BackgroundTrans cE0E0E0", "If this tool helps reduce repetitive work or improve your productivity, your support will encourage me to continue building more practical automation tools for everyday workflows.")
    SupportText.SetFont("s9", "Segoe UI")

    ; 후원 버튼 이미지 (20% 축소: w176 h40, 중앙 정렬, y485)
    if FileExist(bmcBtnPath) {
        BmcPic := AboutGui.Add("Picture", "x192 y485 w176 h40 +BackgroundTrans", bmcBtnPath)
        BmcPic.OnEvent("Click", (*) => Run("https://www.buymeacoffee.com/KBPark_Bob"))
    } else {
        BmcLink := AboutGui.Add("Link", "x35 y490 w490 h30 Center Background2D2D35 cYellow", '<a href="https://www.buymeacoffee.com/KBPark_Bob">☕ Click here to Support on Buy Me a Coffee</a>')
        BmcLink.SetFont("s10 Bold", "Segoe UI")
    }

    ; ── 하단 버튼: Close (y600으로 이동하여 세로 레이아웃 최적화) ──
    CloseButton := AboutGui.Add("Button", "x210 y600 w140 h40", "Close")
    CloseButton.SetFont("s10", "Segoe UI")
    CloseButton.OnEvent("Click", DestroyAbout)

    AboutGui.OnEvent("Close", DestroyAbout)
    AboutGui.OnEvent("Escape", DestroyAbout)

    AboutGui.Show("w560 h660")
    AboutHwnd := AboutGui.Hwnd
}

; ── Windows 시작 시 자동 실행 헬퍼 ──
IsStartupEnabled() {
    static regKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        val := RegRead(regKey, "ScreenClipTool")
        return (val != "")
    } catch {
        return false
    }
}

EnableStartup() {
    static regKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    exePath := A_IsCompiled ? A_ScriptFullPath : ('"' A_AhkPath '" "' A_ScriptFullPath '"')
    try RegWrite(exePath, "REG_SZ", regKey, "ScreenClipTool")
}

DisableStartup() {
    static regKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    try RegDelete(regKey, "ScreenClipTool")
}

; ── 매뉴얼 다이얼로그 ──
global ManualHwnd := 0

ShowManualDialog() {
    global ManualHwnd

    if (ManualHwnd && WinExist("ahk_id " ManualHwnd)) {
        WinActivate("ahk_id " ManualHwnd)
        return
    }

    ManGui := Gui("+AlwaysOnTop +ToolWindow +Border +Resize -DPIScale +MinSize480x800", "📖 App Manual")
    ManGui.BackColor := "FFFFFF"
    ManGui.SetFont("s9", "Segoe UI")

    ; ── Language 드롭다운 ──
    ManGui.Add("Text", "x14 y12 w70 h22 cBlack", "Language:")
    ManGui.SetFont("s9", "Segoe UI")
    langList := ["KR 한국어", "US English", "PL Polski", "DE Deutsch", "FR Français", "ES Español"]
    LangDDL := ManGui.Add("DropDownList", "x90 y9 w140 Choose2", langList)

    ; ── 매뉴얼 텍스트 영역 ──
    ManEdit := ManGui.Add("Edit", "x14 y42 w552 h800 ReadOnly +Multi +VScroll", GetManualText("en"))

    ; ── 하단 Close 버튼 ──
    CloseMBtn := ManGui.Add("Button", "x240 y852 w100 h32", "Close")
    CloseMBtn.SetFont("s9", "Segoe UI")

    ; 언어 변경 이벤트
    OnManualLangChange(*) {
        selected := LangDDL.Text
        if InStr(selected, "한국어")
            lang := "ko"
        else if InStr(selected, "Polski")
            lang := "pl"
        else if InStr(selected, "Deutsch")
            lang := "de"
        else if InStr(selected, "Français")
            lang := "fr"
        else if InStr(selected, "Español")
            lang := "es"
        else
            lang := "en"
        ManEdit.Value := GetManualText(lang)
    }
    LangDDL.OnEvent("Change", OnManualLangChange)

    DestroyManual(*) {
        global ManualHwnd := 0
        ManGui.Destroy()
    }

    CloseMBtn.OnEvent("Click", DestroyManual)
    ManGui.OnEvent("Close", DestroyManual)
    ManGui.OnEvent("Escape", DestroyManual)

    ; Resize 핸들러
    OnManualResize(thisGui, MinMax, Width, Height) {
        if (MinMax == -1)
            return
        m := 14
        LangDDL.Move(90, 9, 140)
        ManEdit.Move(m, 42, Width - m * 2, Height - 42 - 50)
        CloseMBtn.Move((Width - 100) // 2, Height - 42, 100, 32)
    }
    ManGui.OnEvent("Size", OnManualResize)

    ManGui.Show("w580 h894")
    ManualHwnd := ManGui.Hwnd
}

GetManualText(lang) {
    if (lang == "ko") {
        return "
        (
            📖 ScreenClip Tool 사용 설명서
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            🚀 빠른 시작
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            1. 📸 화면 캡처  (Win + 마우스 드래그)
               - Win 키를 누른 채 마우스 왼쪽 버튼으로 영역을 드래그합니다.
               - 선택한 영역이 항상-위 플로팅 창으로 표시되고 자동으로 클립보드에 복사됩니다.
            
            2. 🌐 선택 텍스트 번역  (Win + CapsLock)
               - 번역할 텍스트를 선택한 후 Win + CapsLock을 누릅니다.
               - 번역 결과 창에서 언어 콤보박스로 EN, KO, PL 등 원하는 언어로 전환 가능합니다.
               - Settings에서 단축키와 기본 번역 언어를 변경할 수 있습니다.
            
            
            📸 캡처 창 기능
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • 더블클릭: 축소/복원 (미니 사이즈 ↔ 원래 크기)
            • 드래그: 창 이동
            • 우클릭: 컨텍스트 메뉴
            
              🟥 Shift + 드래그: 빨간 테두리 박스 그리기
              🟨 Ctrl + 드래그: 노란 형광펜 하이라이트
              🟩 Alt + 드래그: 초록 형광펜 하이라이트
              ↩️ Ctrl + Z: 그리기 실행 취소
            
              📋 Ctrl + C: 클립보드에 이미지 복사
              💾 Ctrl + S: 바탕화면에 PNG 저장
              Esc: 현재 캡처 창 닫기
              Ctrl + Esc: 모든 캡처 창 닫기
            
            
            🪟 창 관리
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Ctrl + ←: 모든 캡처 창 모니터별 정렬
            • Ctrl + ↑: 모든 캡처 창 축소
            • Ctrl + ↓: 모든 캡처 창 복원
            
            
            ⚙️ 설정 (Settings)
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • 클립보드 이미지 크기: 50% ~ 150%
            • 번역 단축키: Win+CapsLock 등 5가지 옵션
            • 번역 결과 언어: 한국어, 영어, 폴란드어 등 유럽 언어 49개 지원
        )"
    }

    if (lang == "pl") {
        return "
        (
            📖 ScreenClip Tool — Instrukcja obsługi
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            🚀 Szybki start
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            1. 📸 Przechwytywanie ekranu  (Win + przeciągnij myszą)
               - Przytrzymaj klawisz Win i przeciągnij lewym przyciskiem myszy.
               - Zaznaczony obszar pojawi się jako okno pływające i zostanie skopiowany do schowka.
            
            2. 🌐 Tłumaczenie zaznaczonego tekstu  (Win + CapsLock)
               - Zaznacz tekst, a następnie naciśnij Win + CapsLock.
               - W oknie tłumaczenia możesz zmienić język docelowy (EN, KO, PL itp.).
               - Skrót klawiszowy i domyślny język można zmienić w Ustawieniach.
            
            
            📸 Funkcje okna przechwytywania
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Podwójne kliknięcie: minimalizuj/przywróć
            • Przeciąganie: przesuń okno
            • Prawy przycisk myszy: menu kontekstowe
            
              🟥 Shift + przeciągnij: czerwona ramka
              🟨 Ctrl + przeciągnij: żółte podświetlenie
              🟩 Alt + przeciągnij: zielone podświetlenie
              ↩️ Ctrl + Z: cofnij rysowanie
            
              📋 Ctrl + C: kopiuj do schowka
              💾 Ctrl + S: zapisz na pulpicie
              Esc: zamknij bieżące okno
              Ctrl + Esc: zamknij wszystkie okna
            
            
            🪟 Zarządzanie oknami
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Ctrl + ←: sortuj okna kaskadowo
            • Ctrl + ↑: minimalizuj wszystkie
            • Ctrl + ↓: przywróć wszystkie
            
            
            ⚙️ Ustawienia
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Rozmiar obrazu w schowku: 50% ~ 150%
            • Skrót do tłumaczenia: 5 opcji
            • Język tłumaczenia: 49 języków europejskich
        )"
    }

    if (lang == "de") {
        return "
        (
            📖 ScreenClip Tool — Benutzerhandbuch
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            🚀 Schnellstart
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            1. 📸 Bildschirmaufnahme  (Win + Maus ziehen)
               - Halten Sie Win gedrückt und ziehen Sie mit der linken Maustaste.
               - Der ausgewählte Bereich wird als schwebendes Fenster angezeigt und in die Zwischenablage kopiert.
            
            2. 🌐 Markierten Text übersetzen  (Win + CapsLock)
               - Wählen Sie Text aus und drücken Sie Win + CapsLock.
               - Im Übersetzungsfenster können Sie die Zielsprache wechseln (EN, KO, PL usw.).
               - Tastenkürzel und Standardsprache können in den Einstellungen geändert werden.
            
            
            📸 Funktionen des Aufnahmefensters
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Doppelklick: Minimieren/Wiederherstellen
            • Ziehen: Fenster verschieben
            • Rechtsklick: Kontextmenü
            
              🟥 Shift + Ziehen: Roten Rahmen zeichnen
              🟨 Strg + Ziehen: Gelbe Hervorhebung
              🟩 Alt + Ziehen: Grüne Hervorhebung
              ↩️ Strg + Z: Zeichnung rückgängig machen
            
              📋 Strg + C: In Zwischenablage kopieren
              💾 Strg + S: Auf Desktop speichern
              Esc: Aktuelles Fenster schließen
              Strg + Esc: Alle Fenster schließen
            
            
            🪟 Fensterverwaltung
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Strg + ←: Kaskadiert sortieren
            • Strg + ↑: Alle minimieren
            • Strg + ↓: Alle wiederherstellen
            
            
            ⚙️ Einstellungen
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Zwischenablage-Bildgröße: 50% ~ 150%
            • Übersetzungs-Tastenkürzel: 5 Optionen
            • Übersetzungssprache: 49 europäische Sprachen
        )"
    }

    if (lang == "fr") {
        return "
        (
            📖 ScreenClip Tool — Manuel d'utilisation
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            🚀 Démarrage rapide
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            1. 📸 Capture d'écran  (Win + glisser la souris)
               - Maintenez Win et glissez avec le bouton gauche de la souris.
               - La zone sélectionnée s'affiche en fenêtre flottante et est copiée dans le presse-papiers.
            
            2. 🌐 Traduire le texte sélectionné  (Win + CapsLock)
               - Sélectionnez du texte, puis appuyez sur Win + CapsLock.
               - Dans la fenêtre de traduction, changez la langue cible (EN, KO, PL, etc.).
               - Le raccourci et la langue par défaut sont modifiables dans les Paramètres.
            
            
            📸 Fonctions de la fenêtre de capture
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Double-clic : minimiser/restaurer
            • Glisser : déplacer la fenêtre
            • Clic droit : menu contextuel
            
              🟥 Shift + glisser : cadre rouge
              🟨 Ctrl + glisser : surlignage jaune
              🟩 Alt + glisser : surlignage vert
              ↩️ Ctrl + Z : annuler le dessin
            
              📋 Ctrl + C : copier dans le presse-papiers
              💾 Ctrl + S : enregistrer sur le Bureau
              Esc : fermer la fenêtre actuelle
              Ctrl + Esc : fermer toutes les fenêtres
            
            
            🪟 Gestion des fenêtres
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Ctrl + ← : trier en cascade
            • Ctrl + ↑ : tout minimiser
            • Ctrl + ↓ : tout restaurer
            
            
            ⚙️ Paramètres
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Taille de l'image : 50% ~ 150%
            • Raccourci de traduction : 5 options
            • Langue de traduction : 49 langues européennes
        )"
    }

    if (lang == "es") {
        return "
        (
            📖 ScreenClip Tool — Manual de usuario
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            🚀 Inicio rápido
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            1. 📸 Captura de pantalla  (Win + arrastrar ratón)
               - Mantenga Win pulsado y arrastre con el botón izquierdo del ratón.
               - El área seleccionada aparece como ventana flotante y se copia al portapapeles.
            
            2. 🌐 Traducir texto seleccionado  (Win + CapsLock)
               - Seleccione el texto y pulse Win + CapsLock.
               - En la ventana de traducción, cambie el idioma de destino (EN, KO, PL, etc.).
               - El atajo y el idioma predeterminado se pueden cambiar en Configuración.
            
            
            📸 Funciones de la ventana de captura
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Doble clic: minimizar/restaurar
            • Arrastrar: mover la ventana
            • Clic derecho: menú contextual
            
              🟥 Shift + arrastrar: marco rojo
              🟨 Ctrl + arrastrar: resaltado amarillo
              🟩 Alt + arrastrar: resaltado verde
              ↩️ Ctrl + Z: deshacer dibujo
            
              📋 Ctrl + C: copiar al portapapeles
              💾 Ctrl + S: guardar en el escritorio
              Esc: cerrar ventana actual
              Ctrl + Esc: cerrar todas las ventanas
            
            
            🪟 Gestión de ventanas
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Ctrl + ←: ordenar en cascada
            • Ctrl + ↑: minimizar todas
            • Ctrl + ↓: restaurar todas
            
            
            ⚙️ Configuración
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            • Tamaño de imagen: 50% ~ 150%
            • Atajo de traducción: 5 opciones
            • Idioma de traducción: 49 idiomas europeos
        )"
    }

    ; Default: English
    return "
    (
        📖 ScreenClip Tool — User Manual
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        🚀 Quick Start
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        1. 📸 Screen Capture  (Win + Mouse Drag)
           - Hold Win and drag with the left mouse button.
           - The selected area appears as an always-on-top floating window and is auto-copied to clipboard.
        
        2. 🌐 Translate Selected Text  (Win + CapsLock)
           - Select text, then press Win + CapsLock.
           - In the translation window, switch target language (EN, KO, PL, etc.) via the combo box.
           - The hotkey and default language can be changed in Settings.
        
        
        📸 Capture Window Features
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        • Double-click: Minimize/Restore (mini size ↔ original)
        • Drag: Move window
        • Right-click: Context menu
        
          🟥 Shift + Drag: Draw a red border box
          🟨 Ctrl + Drag: Yellow highlight
          🟩 Alt + Drag: Green highlight
          ↩️ Ctrl + Z: Undo drawing
        
          📋 Ctrl + C: Copy image to clipboard
          💾 Ctrl + S: Save PNG to Desktop
          Esc: Close current capture window
          Ctrl + Esc: Close all capture windows
        
        
        🪟 Window Management
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        • Ctrl + ←: Cascade-sort all clips across monitors
        • Ctrl + ↑: Minimize all clips
        • Ctrl + ↓: Restore all clips
        
        
        ⚙️ Settings
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        • Clipboard image scale: 50% ~ 150%
        • Translation hotkey: 5 options available
        • Translation language: 49 European languages supported
    )"
}
