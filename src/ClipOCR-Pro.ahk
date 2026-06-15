#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetMainIcon ..\assets\ClipOCR-Pro.ico
#Include Gdip_All.ahk

; ── App metadata ──
global APP_NAME := "ClipOCR-Pro"
global APP_VERSION := "1.1.1"
global APP_ICON_PATH := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\..\assets\ClipOCR-Pro.ico"
global APP_SOURCE_ICON_PATH := A_ScriptDir "\..\assets\ClipOCR-Pro.ico"

; ── Global asset paths and initialization ──
global bmcBtnPath := A_Temp "\ClipOCR_bmc_btn.png"
global githubIconPath := A_Temp "\ClipOCR_github_favicon.png"

; Download the GitHub favicon in the background.
SetTimer(DownloadGithubIcon, -100)
DownloadGithubIcon() {
    global githubIconPath
    if !FileExist(githubIconPath) {
        try Download("https://www.google.com/s2/favicons?domain=github.com&sz=256", githubIconPath)
    }
}

; ── Per-Monitor DPI Aware V2: fixes scaling mismatches across monitors ──
; Use physical pixels for all coordinates so capture remains accurate across mixed-DPI monitors.
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

if !pToken := Gdip_Startup() {
    MsgBox "GDI+ failed to start."
    ExitApp
}

OnExit AppCleanup

AppCleanup(*) {
    global pToken, TEMP_FILES
    try Gdip_Shutdown(pToken)
    try FileDelete(A_Temp "\temp_clip.png")
    try {
        for _, filePath in TEMP_FILES {
            if FileExist(filePath)
                FileDelete(filePath)
        }
    }
}

; ── UI and behavior constants ──
global MINI_SIZE := 80          ; Minimized window size (px)
global MINI_OPACITY := 128      ; Minimized opacity (0-255)
global BORDER_WIDTH := 3        ; Capture window border width (px)
global UNDO_MAX := 5            ; Maximum undo steps
global TEXT_TRANSLATE_MAX_CHARS := 5000 ; Safe maximum length for Google Text Translation GET requests

; ── User settings: keep the Registry path name for backward compatibility ──
global REG_PATH := "HKCU\Software\ScreenClipTool"
global CLIP_SCALE := 1.0
global TEXT_TRANSLATE_LANG := "ko"
global TEXT_TRANSLATE_HOTKEY := "#CapsLock"
global TEXT_TRANSLATE_FONT_SIZE := 10
global IMAGE_TRANSLATE_LANGS := "ko,en,pl"

; ── Runtime state ──
global TRAY_TEXT_TRANSLATE_ITEM := ""
global TextTranslatePopupHwnd := 0
global DashboardHwnd := 0
global ManualHwnd := 0
global ANNOTATION_MODE := ""
global ANNOTATION_TARGET_HWND := 0
global TEXT_SOURCE_LAST_HWND := 0
global TEMP_FILES := []
global ENABLE_BMC_AUTO_DOWNLOAD := true

try {
    CLIP_SCALE := NormalizeClipScale(RegRead(REG_PATH, "Scale"))
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

try {
    TEXT_TRANSLATE_FONT_SIZE := NormalizeTextTranslateFontSize(RegRead(REG_PATH, "TextTranslateFontSize"))
} catch {
    TEXT_TRANSLATE_FONT_SIZE := 10
}

try {
    savedImageLangs := RegRead(REG_PATH, "ImageTranslateLangs")
    IMAGE_TRANSLATE_LANGS := NormalizeLangCodeList(savedImageLangs)
} catch {
    IMAGE_TRANSLATE_LANGS := NormalizeLangCodeList(IMAGE_TRANSLATE_LANGS)
}

; ── System tray icon and menu customization ──
try {
    if FileExist(APP_ICON_PATH)
        TraySetIcon(APP_ICON_PATH)
    else if FileExist(APP_SOURCE_ICON_PATH)
        TraySetIcon(APP_SOURCE_ICON_PATH)
    else
        TraySetIcon("shell32.dll", 260) ; Scissors icon fallback
} catch {
    ; Ignore failures and keep the default icon.
}
A_IconTip := APP_NAME
Tray := A_TrayMenu
Tray.Delete()
Tray.Add("📸 Capture (Win+Drag)", (*) => ScreenClip2Win(1))
TRAY_TEXT_TRANSLATE_ITEM := "🌐 Translate Selected Text (" GetTextTranslateHotkeyLabel(TEXT_TRANSLATE_HOTKEY) ")"
Tray.Add(TRAY_TEXT_TRANSLATE_ITEM, (*) => TranslateSelectedText(true))
Tray.Add("⚙️ Preferences & About", (*) => ShowDashboardDialog())
Tray.Add()
Tray.Add("📐 Sort All Clips (Ctrl+Left)", (*) => SCW_SortCascade())
Tray.Add("🔽 Minimize All (Ctrl+Up)", (*) => SCW_MinimizeAll())
Tray.Add("🔼 Restore All (Ctrl+Down)", (*) => SCW_RestoreAll())
Tray.Add("❌ Close All Clips (Ctrl+Esc)", (*) => SCW_CloseAll())
Tray.Add()
Tray.Add("🔄 Reload Script", (*) => Reload())
Tray.Add("🚪 Exit App", (*) => ExitApp())

; ── Capture window and context-menu state ──
global ClipWins := Map()
global RightClickedHwnd := 0
global ClipMenu := Menu()

; bmcBtnPath is defined with the global asset paths near the top of the script.

; Do not auto-download external images by default in corporate security environments.
if ENABLE_BMC_AUTO_DOWNLOAD
    SetTimer(DownloadBmcButton, -100)

DownloadBmcButton() {
    global bmcBtnPath
    if !FileExist(bmcBtnPath) {
        try {
            Download("https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png", bmcBtnPath)
        }
    }
}

; Google Image Translation submenu for target-language selection.
global ImgTransMenu := Menu()

UpdateImageTranslateMenu() {
    global ImgTransMenu, IMAGE_TRANSLATE_LANGS
    ImgTransMenu.Delete()
    IMAGE_TRANSLATE_LANGS := NormalizeLangCodeList(IMAGE_TRANSLATE_LANGS)

    langArray := StrSplit(IMAGE_TRANSLATE_LANGS, ",")
    if (langArray.Length == 0)
        langArray := ["ko"]

    options := GetTextTranslateLangOptions()

    for _, code in langArray {
        code := Trim(code)
        if (code == "")
            continue

        label := "🌐 Translate to " code
        for _, opt in options {
            if (opt.code == code) {
                label := "🌐 Translate to " opt.label
                break
            }
        }

        ; Bind through a local-scope function for lambda closure safety.
        BindGoogleImageTranslate(c) {
            return (*) => GoogleImageTranslate(c)
        }

        ImgTransMenu.Add(label, BindGoogleImageTranslate(code))
    }
}

UpdateImageTranslateMenu()

ClipMenu.Add("🌐 1. Google Translate (Image)", ImgTransMenu)
ClipMenu.Add() ; Separator

ClipMenu.Add("🟥 2. Red Box (Shift+Drag)", MenuHandler)
ClipMenu.Add("🟨 3. Yellow Highlight (Ctrl+Drag)", MenuHandler)
ClipMenu.Add("🟩 4. Green Highlight (Alt+Drag)", MenuHandler)
ClipMenu.Add("✍️ 5. Text Markup (Shift+Ctrl+Click)", MenuHandler)
ClipMenu.Add("↩️ 6. Undo Draw (Ctrl+Z)", MenuHandler)
ClipMenu.Add() ; Separator

ClipMenu.Add("📋 7. Copy to Clipboard (Ctrl+C)", MenuHandler)
ClipMenu.Add("💾 8. Save to Desktop (Ctrl+S)", MenuHandler)
ClipMenu.Add("🎨 9. Copy To Paint", MenuHandler)
ClipMenu.Add() ; Separator

; 10. Clipboard scale submenu
ScaleMenu := Menu()
ScaleMenu.Add("50%", (*) => SetClipScale(0.5))
ScaleMenu.Add("60%", (*) => SetClipScale(0.6))
ScaleMenu.Add("70%", (*) => SetClipScale(0.7))
ScaleMenu.Add("80%", (*) => SetClipScale(0.8))
ScaleMenu.Add("90%", (*) => SetClipScale(0.9))
ScaleMenu.Add("100%", (*) => SetClipScale(1.0))
ScaleMenu.Add("150%", (*) => SetClipScale(1.5))
UpdateScaleMenu()

ClipMenu.Add("⚙️ 10. Clipboard Scale", ScaleMenu)
ClipMenu.Add() ; Separator
ClipMenu.Add("📐 11. Sort All Clips (Ctrl+Left)", (*) => SCW_SortCascade())
ClipMenu.Add("🔽 12. Minimize All (Ctrl+Up)", (*) => SCW_MinimizeAll())
ClipMenu.Add("🔼 13. Restore All (Ctrl+Down)", (*) => SCW_RestoreAll())
ClipMenu.Add("❌ 14. Close All Clips (Ctrl+Esc)", (*) => SCW_CloseAll())
ClipMenu.Add("⚙️ 15. Preferences & About", (*) => ShowDashboardDialog())

; ── Startup welcome tooltip ──
ToolTip("📸 " APP_NAME " Ready!`r`nWin+드래그: 캡처`r`n" GetTextTranslateHotkeyLabel(TEXT_TRANSLATE_HOTKEY) ": 선택 텍스트 번역")
SetTimer(() => ToolTip(), -4000)

SetTimer(TrackLastTextSourceWindow, 250)
ApplyTextTranslateHotkey()

; Hotkeys
#LButton:: ScreenClip2Win(1)  ; Win+LButton -> floating clip + auto copy to clipboard
#CapsLock:: TranslateSelectedText(false) ; Default selected-text translation hotkey

#HotIf WinActive("ScreenClippingWindow ahk_class AutoHotkeyGUI")
^c:: SCW_Win2Clipboard()
^s:: SCW_Win2File()
^z:: SCW_Undo()
^Left:: SCW_SortCascade()
^Up:: SCW_MinimizeAll()
^Down:: SCW_RestoreAll()
Esc:: SCW_CloseWin()
^Esc:: SCW_CloseAll() ; Ctrl+Esc -> close all
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

NormalizeClipScale(value) {
    try {
        scale := Float(value)
    } catch {
        return 1.0
    }

    for _, allowed in [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.5] {
        if (Abs(scale - allowed) < 0.001)
            return allowed
    }
    return 1.0
}

NormalizeTextTranslateFontSize(value) {
    try {
        fontSize := Integer(value)
    } catch {
        return 10
    }

    ; Keep the translation popup in a practical size range.
    if (fontSize < 8 || fontSize > 18)
        return 10
    return fontSize
}

NormalizeLangCodeList(csvText, defaultCsv := "ko,en,pl") {
    result := []
    seen := Map()

    AddCode(code) {
        code := StrLower(Trim(code))
        if (code == "" || seen.Has(code) || !IsTextTranslateLangSupported(code))
            return
        seen[code] := true
        result.Push(code)
    }

    for _, code in StrSplit(String(csvText), ",")
        AddCode(code)

    if (result.Length == 0) {
        for _, code in StrSplit(defaultCsv, ",")
            AddCode(code)
    }

    if (result.Length == 0)
        result.Push("ko")

    normalized := ""
    for index, code in result
        normalized .= (index == 1 ? "" : ",") code
    return normalized
}

SafeClipboardBackup() {
    try {
        return { ok: true, data: ClipboardAll() }
    } catch {
        return { ok: false, data: "" }
    }
}

SafeClipboardRestore(clipBackup) {
    try {
        if clipBackup.ok {
            A_Clipboard := clipBackup.data
            return true
        }
    } catch {
        ; If the clipboard is locked, ignore only the restore failure and keep the app running.
    }
    return false
}

SafeSaveBitmapToFile(pBitmap, filePath) {
    if (!pBitmap || filePath == "")
        return false
    try {
        result := Gdip_SaveBitmapToFile(pBitmap, filePath)
        return (result == 0 && FileExist(filePath))
    } catch {
        return false
    }
}

SafeRegWriteString(value, regPath, valueName) {
    try {
        RegWrite(String(value), "REG_SZ", regPath, valueName)
        return true
    } catch {
        return false
    }
}

ShortErrorMessage(message, maxLen := 120) {
    message := Trim(String(message))
    if (message == "")
        message := "Unknown error"
    message := StrReplace(message, "`r`n", " ")
    message := StrReplace(message, "`n", " ")
    message := StrReplace(message, "`r", " ")
    if (StrLen(message) > maxLen)
        message := SubStr(message, 1, maxLen) "..."
    return message
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
    if !pBitmap {
        ToolTip("⚠️ 화면 캡처에 실패했습니다.`r`n⚠️ Screen capture failed.")
        SetTimer(() => ToolTip(), -3000)
        return
    }

    clipBackup := SafeClipboardBackup()
    if !clipBackup.ok {
        Gdip_DisposeImage(pBitmap)
        ToolTip("⚠️ 클립보드를 백업하지 못했습니다.`r`n⚠️ Could not back up clipboard.")
        SetTimer(() => ToolTip(), -3000)
        return
    }

    try {
        Gdip_SetBitmapToClipboard(pBitmap)
        Run("https://translate.google.com/?sl=auto&tl=ko&op=images")
        ToolTip("🌐 구글 번역(이미지) 열기 중...`r`n🌐 Opening Google Image Translation...")
        AutoPasteToGoogleTranslate(clipBackup)
    } catch as e {
        SafeClipboardRestore(clipBackup)
        ToolTip("⚠️ 이미지 번역 실행 실패: " ShortErrorMessage(e.Message) "`r`n⚠️ Image translation failed.")
        SetTimer(() => ToolTip(), -3500)
    } finally {
        Gdip_DisposeImage(pBitmap)
    }
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
    if !IsTextTranslateLangSupported(targetLang)
        targetLang := "ko"

    clipBackup := SafeClipboardBackup()
    if !clipBackup.ok {
        ToolTip("⚠️ 클립보드를 백업하지 못했습니다.`r`n⚠️ Could not back up clipboard.")
        SetTimer(() => ToolTip(), -3000)
        return
    }

    pBitmap := ClipWins[RightClickedHwnd].pBitmap
    try {
        Gdip_SetBitmapToClipboard(pBitmap)
        Run("https://translate.google.com/?sl=auto&tl=" UriEncode(targetLang) "&op=images")
        ToolTip("🌐 구글 번역(이미지) 열기 중...`r`n🌐 Opening Google Image Translation...")
        AutoPasteToGoogleTranslate(clipBackup)
    } catch as e {
        SafeClipboardRestore(clipBackup)
        ToolTip("⚠️ 이미지 번역 실행 실패: " ShortErrorMessage(e.Message) "`r`n⚠️ Image translation failed.")
        SetTimer(() => ToolTip(), -3500)
    }
}

IsGoogleTranslateWindow(hwnd, patterns) {
    if !hwnd
        return false
    try {
        title := WinGetTitle("ahk_id " hwnd)
    } catch {
        return false
    }
    for _, pattern in patterns {
        if InStr(title, pattern)
            return true
    }
    return false
}

/**
 * 구글 번역 브라우저 창을 감지하고 활성화한 후 클립보드의 이미지를 자동으로 붙여넣는(Ctrl+V) RPA 루틴
 * Detects the active browser translation tab and automates clipboard paste (Ctrl+V) inputs.
 * @returns {None}
 */
AutoPasteToGoogleTranslate(clipBackup := "") {
    SetTimer(_DoPaste, -1000)

    _DoPaste() {
        global ClipWins
        ; Multilingual browser title patterns.
        patterns := ["Google Translate", "Google 번역", "Tłumacz Google", "translate.google"]
        hwndTarget := 0
        loweredClips := []

        try {
            activeHwnd := WinExist("A")
            if IsGoogleTranslateWindow(activeHwnd, patterns)
                hwndTarget := activeHwnd

            ; Wait up to 5 seconds for the browser window.
            loop 10 {
                if hwndTarget
                    break
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
                    "⚠️ 브라우저를 찾을 수 없습니다. 이미지 번역을 다시 실행해 주세요.`r`n⚠️ Browser not found. Please try image translation again.")
                SetTimer(() => ToolTip(), -4000)
                return
            }

            ; Disable AlwaysOnTop on all capture windows and send them to the bottom of the z-order.
            for clipHwnd, _ in ClipWins {
                try {
                    WinSetAlwaysOnTop(false, "ahk_id " clipHwnd)
                    loweredClips.Push(clipHwnd)
                    ; HWND_BOTTOM=1, SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE=0x0013
                    DllCall("SetWindowPos", "ptr", clipHwnd, "ptr", 1, "int", 0, "int", 0, "int", 0, "int", 0,
                        "uint", 0x0013)
                }
            }

            try {
                WinActivate("ahk_id " hwndTarget)
                WinWaitActive("ahk_id " hwndTarget, , 3)
            }
            if !WinActive("ahk_id " hwndTarget)
                throw Error("Browser activation failed")
            if !IsGoogleTranslateWindow(WinExist("A"), patterns)
                throw Error("Active window is not Google Translate")

            Sleep(1500) ; Wait for page loading (1.5 seconds)

            ; Click the browser center to ensure page focus before pasting.
            WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwndTarget)
            CoordMode("Mouse", "Screen")
            Click(winX + winW // 2, winY + winH // 2)
            Send("^v")
            Sleep(300)

            ToolTip("✅ 이미지 붙여넣기 완료!`r`n✅ Image pasted to Google Translate!")
            SetTimer(() => ToolTip(), -3000)
        } catch as e {
            ToolTip("⚠️ 이미지 붙여넣기 실패: " ShortErrorMessage(e.Message) "`r`n⚠️ Image paste failed.")
            SetTimer(() => ToolTip(), -4000)
        } finally {
            for _, clipHwnd in loweredClips {
                if WinExist("ahk_id " clipHwnd)
                    try WinSetAlwaysOnTop(true, "ahk_id " clipHwnd)
            }
            SafeClipboardRestore(clipBackup)
        }
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
    global TEXT_TRANSLATE_LANG, TEXT_TRANSLATE_MAX_CHARS
    sourceHwnd := GetCopySourceHwnd(fromTray)
    clipSaved := SafeClipboardBackup()
    if !clipSaved.ok {
        ToolTip("⚠️ 클립보드를 백업하지 못했습니다.`r`n⚠️ Could not back up clipboard.")
        SetTimer(() => ToolTip(), -3000)
        return
    }

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

        if (StrLen(sourceText) > TEXT_TRANSLATE_MAX_CHARS) {
            ToolTip("⚠️ 선택 텍스트가 너무 깁니다. " TEXT_TRANSLATE_MAX_CHARS "자 이하만 번역합니다.`r`n⚠️ Selected text is too long.")
            SetTimer(() => ToolTip(), -3500)
            return
        }

        ToolTip("🌐 번역 중...`r`n🌐 Translating...")
        translatedText := TranslateTextViaGoogle(sourceText, TEXT_TRANSLATE_LANG)
        ToolTip()
        ShowTextTranslationPopup(sourceText, translatedText)
    } catch as e {
        ToolTip("❌ 번역 실패: " ShortErrorMessage(e.Message) "`r`n❌ Translation failed.")
        SetTimer(() => ToolTip(), -3500)
    } finally {
        SafeClipboardRestore(clipSaved)
    }
}

TranslateTextViaGoogle(text, targetLang) {
    global TEXT_TRANSLATE_MAX_CHARS
    if !IsTextTranslateLangSupported(targetLang)
        targetLang := "ko"
    if (Trim(text) == "")
        throw Error("No text to translate")
    if (StrLen(text) > TEXT_TRANSLATE_MAX_CHARS)
        throw Error("Text is too long. Max " TEXT_TRANSLATE_MAX_CHARS " characters.")

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
        ; Append only the first string in each translation result array.
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

            ; Skip source text and pronunciation data within the same sentence segment.
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

        ; Move to the next translation segment.
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

GetTextTranslationPopupLangItems() {
    langItems := ["ORIGINAL"]
    for _, label in GetTextTranslateLangLabels()
        langItems.Push(label)
    return langItems
}

UpdateTextTranslationPopupResult(sourceText, selectedLabel, resultEdit, currentTextRef) {
    if (selectedLabel == "ORIGINAL") {
        try {
            currentTextRef.Value := sourceText
            resultEdit.Value := sourceText
        }
        return
    }

    targetLang := GetTextTranslateLangCodeByLabel(selectedLabel)
    try resultEdit.Value := "🌐 Translating..."

    try {
        translated := TranslateTextViaGoogle(sourceText, targetLang)
        try {
            currentTextRef.Value := translated
            resultEdit.Value := translated
        }
    } catch as e {
        try {
            currentTextRef.Value := ""
            resultEdit.Value := "❌ Translation failed: " ShortErrorMessage(e.Message)
        }
    }
}

GetPopupPositionNearMouse(popupW, popupH) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
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
    return {
        x: Min(Max(mx + 16, workLeft), xMax),
        y: Min(Max(my + 16, workTop), yMax)
    }
}

ShowTextTranslationPopup(sourceText, translatedText) {
    global TextTranslatePopupHwnd, TEXT_TRANSLATE_LANG, TEXT_TRANSLATE_FONT_SIZE

    if (TextTranslatePopupHwnd && WinExist("ahk_id " TextTranslatePopupHwnd))
        WinClose("ahk_id " TextTranslatePopupHwnd)

    PopGui := Gui("+AlwaysOnTop +ToolWindow +Border +Resize -DPIScale +MinSize320x200", "Translation by Google")
    PopGui.BackColor := "1E1E24"
    PopGui.SetFont("s10", "Segoe UI")

    ; ── Top area: title and temporary translation-language selector ──
    TitleLabel := PopGui.Add("Text", "x14 y12 w220 h22 +BackgroundTrans cFFFFFF", "🌐 Translation by Google")
    TitleLabel.SetFont("s10 Bold", "Segoe UI")

    LangCombo := PopGui.Add("DropDownList", "x250 y9 w156 Choose" GetTextTranslateLangIndex(TEXT_TRANSLATE_LANG) + 1,
        GetTextTranslationPopupLangItems())

    ; ── Divider ──
    SepLine := PopGui.Add("Text", "x14 y38 w392 h1 Background3F3F46", "")

    ; ── Translation result text box (single read-only multiline control with scroll) ──
    ResultEdit := PopGui.Add("Edit", "x14 y46 w392 h164 ReadOnly +Multi +VScroll", translatedText)
    ResultEdit.SetFont("s" TEXT_TRANSLATE_FONT_SIZE, "Segoe UI")

    ; ── Bottom buttons ──
    CopyBtn := PopGui.Add("Button", "x218 y220 w90 h30", "Copy")
    CloseBtn := PopGui.Add("Button", "x316 y220 w90 h30", "Close")

    ; Store the currently displayed text in an object shared by internal events.
    currentText := { Value: translatedText }

    ; ── ComboBox change triggers automatic retranslation ──
    OnLangChange(*) {
        UpdateTextTranslationPopupResult(sourceText, LangCombo.Text, ResultEdit, currentText)
    }
    LangCombo.OnEvent("Change", OnLangChange)

    ; ── Copy button ──
    CopyTranslated(*) {
        A_Clipboard := currentText.Value
        ToolTip("✅ 번역 결과 복사 완료`r`n✅ Translation copied.")
        SetTimer(() => ToolTip(), -1500)
    }

    ; ── Close handling ──
    DestroyPopup(*) {
        global TextTranslatePopupHwnd := 0
        PopGui.Destroy()
    }

    CopyBtn.OnEvent("Click", CopyTranslated)
    CloseBtn.OnEvent("Click", DestroyPopup)
    PopGui.OnEvent("Close", DestroyPopup)
    PopGui.OnEvent("Escape", DestroyPopup)

    ; ── Resize handler: dynamically adjust control positions and sizes ──
    OnPopupResize(thisGui, MinMax, Width, Height) {
        if (MinMax == -1)  ; Skip resizing while minimized.
            return
        m := 14
        LangCombo.Move(Width - 170, 9, 156)
        SepLine.Move(m, 38, Width - m * 2)
        ResultEdit.Move(m, 46, Width - m * 2, Height - 46 - 50)
        CopyBtn.Move(Width - 202, Height - 40, 90, 30)
        CloseBtn.Move(Width - 104, Height - 40, 90, 30)
    }
    PopGui.OnEvent("Size", OnPopupResize)

    ; ── Show near the mouse cursor with dynamic size based on text length ──
    sizeFactor := Max(1.0, TEXT_TRANSLATE_FONT_SIZE / 10)
    popupW := Round(630 * sizeFactor)
    txtLen := Max(StrLen(sourceText), StrLen(translatedText))

    if (txtLen < 400)
        popupH := 540
    else if (txtLen < 1200)
        popupH := 1080
    else
        popupH := 1620

    ; Prevent the popup from becoming too large relative to the primary monitor.
    if (popupH > A_ScreenHeight - 80)
        popupH := A_ScreenHeight - 80

    popupPos := GetPopupPositionNearMouse(popupW, popupH)
    PopGui.Show("x" popupPos.x " y" popupPos.y " w" popupW " h" popupH)
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

    ; Find the lowest available number.
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

    ; Add a slightly smaller black layer behind the number for readability.
    NumBg := ClipGui.Add("Text", "x15 y15 w50 h50 Background222222 Hidden", "")

    ; Number shown while minimized.
    ; Keep the AHK Text control fully transparent and use GUI opacity for visibility.
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
    try hwnd := guiObj.Hwnd
    catch
        return

    if ClipWins.Has(hwnd) {
        winInfo := ClipWins[hwnd]
        try {
            for _, bmp in winInfo.UndoStack
                try Gdip_DisposeImage(bmp)
            try Gdip_DisposeImage(winInfo.pBitmap)
            ClipWins.Delete(hwnd)
        }
    }
    try guiObj.Destroy()
    UpdateTrayTip()
}

UpdateTrayTip() {
    global APP_NAME
    cnt := ClipWins.Count
    A_IconTip := APP_NAME . (cnt > 0 ? " (" cnt " clip" (cnt > 1 ? "s" : "") ")" : "")
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global ANNOTATION_MODE, ANNOTATION_TARGET_HWND
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

    ; --- Drawing modes (Shift: red box, Ctrl: yellow highlight, Alt: green highlight, Shift+Ctrl: text markup) ---
    if GetKeyState("Shift", "P") || GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") {
        if GetKeyState("Shift", "P") && GetKeyState("Ctrl", "P")
            SCW_ApplyAnnotation(hwnd, "Text")
        else if GetKeyState("Shift", "P")
            SCW_ApplyAnnotation(hwnd, "Red")
        else if GetKeyState("Ctrl", "P") {
            SCW_ApplyAnnotation(hwnd, "Yellow")
        } else if GetKeyState("Alt", "P")
            SCW_ApplyAnnotation(hwnd, "Green")
        return
    }
    isDoubleClick := (msg == 0x0203) || (hwnd == LastClickHwnd && A_TickCount - LastClickTime < DllCall(
        "GetDoubleClickTime"))

    ; Detect double-click.
    if isDoubleClick {
        LastClickTime := 0 ; Reset

        if winInfo.IsMinimized {
            ; Restore original size.
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
            WinSetTransparent(MINI_OPACITY, hwnd) ; Set 50% opacity.
            winInfo.NumBg.Visible := true ; Show the black background slightly.
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
    try WinGetPos(&winX, &winY, , , "ahk_id " hwnd)
    catch
        return

    if (mode == "Text") {
        ; Capture mouse position before opening InputBox
        CoordMode("Mouse", "Screen")
        MouseGetPos(&clickX, &clickY)

        ; Prevent dialog from opening behind the always-on-top window
        winInfo.gui.Opt("+OwnDialogs")

        ; Calculate position near the mouse
        pos := GetPopupPositionNearMouse(320, 130)

        ; Prompt for text annotation
        ib := InputBox("Enter the text to display on the image:`n(The text will be printed in red at the clicked location)", "Add Text Annotation", "X" pos.x " Y" pos.y " w320 h130")
        if (ib.Result != "OK" || ib.Value == "")
            return
        textVal := ib.Value
    }
    else if (mode == "Red")
        rect := DrawRectPreview("Red")
    else if (mode == "Yellow")
        rect := DrawRectPreview("Yellow", false)
    else if (mode == "Green")
        rect := DrawRectPreview("Lime", false)
    else
        return

    if (mode != "Text" && (rect.w <= 0 || rect.h <= 0))
        return

    clone := 0, pGraphics := 0, pPen := 0, pBrush := 0, hBitmap := 0
    try {
        clone := Gdip_CloneBitmapArea(winInfo.pBitmap, 0, 0, winInfo.w, winInfo.h)
        if !clone
            throw Error("Could not create undo image")

        if (mode == "Text") {
            rectX := clickX - (winX + BORDER_WIDTH)
            rectY := clickY - (winY + BORDER_WIDTH)
        } else {
            rectX := rect.x - (winX + BORDER_WIDTH)
            rectY := rect.y - (winY + BORDER_WIDTH)
        }

        pGraphics := Gdip_GraphicsFromImage(winInfo.pBitmap)
        if !pGraphics
            throw Error("Could not prepare drawing surface")

        if (mode == "Text") {
            status := Gdip_TextToGraphics(pGraphics, textVal, "x" rectX " y" rectY " cFFFF0000 s14 Bold", "Arial", winInfo.w - rectX, winInfo.h - rectY)
            if (status < 0)
                throw Error("Gdip_TextToGraphics failed with status " status)
        } else if (mode == "Red") {
            pPen := Gdip_CreatePen("0xFFFF0000", BORDER_WIDTH)
            if !pPen
                throw Error("Could not create pen")
            Gdip_DrawRectangle(pGraphics, pPen, rectX, rectY, rect.w, rect.h)
        } else if (mode == "Yellow") {
            pBrush := Gdip_BrushCreateSolid("0x77FFFF00")
            if !pBrush
                throw Error("Could not create brush")
            Gdip_FillRectangle(pGraphics, pBrush, rectX, rectY, rect.w, rect.h)
        } else if (mode == "Green") {
            pBrush := Gdip_BrushCreateSolid("0x7700FF00")
            if !pBrush
                throw Error("Could not create brush")
            Gdip_FillRectangle(pGraphics, pBrush, rectX, rectY, rect.w, rect.h)
        }

        hBitmap := Gdip_CreateHBITMAPFromBitmap(winInfo.pBitmap)
        if !hBitmap
            throw Error("Could not refresh image")
        winInfo.picCtrl.Value := "HBITMAP:*" hBitmap

        winInfo.UndoStack.Push(clone)
        clone := 0
        if (winInfo.UndoStack.Length > UNDO_MAX) {
            oldest := winInfo.UndoStack.RemoveAt(1)
            try Gdip_DisposeImage(oldest)
        }
    } catch as e {
        ToolTip("⚠️ 주석 그리기 실패: " ShortErrorMessage(e.Message) "`r`n⚠️ Annotation failed.")
        SetTimer(() => ToolTip(), -2500)
    } finally {
        if pPen
            Gdip_DeletePen(pPen)
        if pBrush
            Gdip_DeleteBrush(pBrush)
        if pGraphics
            Gdip_DeleteGraphics(pGraphics)
        if hBitmap
            DllCall("DeleteObject", "ptr", hBitmap)
        if clone
            Gdip_DisposeImage(clone)
    }
}

StartAnnotationMode(mode) {
    global ANNOTATION_MODE, ANNOTATION_TARGET_HWND, RightClickedHwnd
    if !ClipWins.Has(RightClickedHwnd)
        return

    ANNOTATION_MODE := mode
    ANNOTATION_TARGET_HWND := RightClickedHwnd
    WinActivate("ahk_id " ANNOTATION_TARGET_HWND)
    if (mode == "Text")
        ToolTip("✍️ 주석을 추가할 위치를 마우스로 클릭하세요.`r`n✍️ Click on the clip to add text.")
    else
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

    CopyBitmapToClipboard(ClipWins[hwnd].pBitmap)
}

SCW_Win2File() {
    hwnd := WinExist("A")
    if !ClipWins.Has(hwnd)
        return

    SaveBitmapToDesktop(ClipWins[hwnd].pBitmap)
}

CopyBitmapToClipboard(pBitmap) {
    global CLIP_SCALE
    pBordered := 0
    pScaled := 0
    try {
        if !pBitmap
            throw Error("Invalid bitmap")

        if (CLIP_SCALE != 1.0) {
            pScaled := ResizeBitmap(pBitmap, CLIP_SCALE)
            if !pScaled
                throw Error("Could not resize image")
            pBordered := AddBorderToBitmap(pScaled)
        } else {
            pBordered := AddBorderToBitmap(pBitmap)
        }
        if !pBordered
            throw Error("Could not prepare image")

        Gdip_SetBitmapToClipboard(pBordered)
        finalW := Gdip_GetImageWidth(pBordered)
        finalH := Gdip_GetImageHeight(pBordered)
        ToolTip("✅ 캡처 완료 (" finalW "×" finalH ") + 클립보드 복사`r`n✅ Copied to clipboard (" finalW "x" finalH ")")
        SetTimer(() => ToolTip(), -2000)
    } catch as e {
        ToolTip("⚠️ 클립보드 복사 실패: " ShortErrorMessage(e.Message) "`r`n⚠️ Copy to clipboard failed.")
        SetTimer(() => ToolTip(), -3500)
    } finally {
        if pScaled
            Gdip_DisposeImage(pScaled)
        if pBordered
            Gdip_DisposeImage(pBordered)
    }
}

SaveBitmapToDesktop(pBitmap) {
    pBordered := 0
    try {
        if !pBitmap
            throw Error("Invalid bitmap")
        pBordered := AddBorderToBitmap(pBitmap)
        if !pBordered
            throw Error("Could not prepare image")
        TodayDate := FormatTime(, "yyyy-MM-dd_HHmmss")
        FileOut := A_Desktop "\" TodayDate ".PNG"
        if !SafeSaveBitmapToFile(pBordered, FileOut)
            throw Error("Could not save PNG file")
        ToolTip("✅ 바탕화면에 저장 완료`r`n✅ Saved to Desktop:`r`n" FileOut)
        SetTimer(() => ToolTip(), -3000)
    } catch as e {
        ToolTip("⚠️ 바탕화면 저장 실패: " ShortErrorMessage(e.Message) "`r`n⚠️ Save to Desktop failed.")
        SetTimer(() => ToolTip(), -3500)
    } finally {
        if pBordered
            Gdip_DisposeImage(pBordered)
    }
}

CopyBitmapToPaint(pBitmap) {
    global TEMP_FILES
    try {
        if !pBitmap
            throw Error("Invalid bitmap")
        tempFile := A_Temp "\clipocr_pro_paint_" A_Now "_" A_TickCount ".png"
        if !SafeSaveBitmapToFile(pBitmap, tempFile)
            throw Error("Could not save temporary image")
        TEMP_FILES.Push(tempFile)
        Run("mspaint.exe `"" tempFile "`"")
    } catch as e {
        if IsSet(tempFile)
            try FileDelete(tempFile)
        ToolTip("⚠️ Paint 실행 실패: " ShortErrorMessage(e.Message) "`r`n⚠️ Could not open Paint.")
        SetTimer(() => ToolTip(), -3500)
    }
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
        ClipMenu.Enable("↩️ 6. Undo Draw (Ctrl+Z)")
    else
        ClipMenu.Disable("↩️ 6. Undo Draw (Ctrl+Z)")

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
    else if InStr(ItemName, "Text Markup") {
        StartAnnotationMode("Text")
    }
    else if InStr(ItemName, "Copy To Paint") {
        CopyBitmapToPaint(pBitmap)
    }
    else if InStr(ItemName, "Save to Desktop") {
        SaveBitmapToDesktop(pBitmap)
    }
    else if InStr(ItemName, "Copy to Clipboard") {
        CopyBitmapToClipboard(pBitmap)
    }
    else if InStr(ItemName, "Undo Draw") {
        SCW_Undo(RightClickedHwnd)
    }
}

; ── Image-border helper for clipboard/save output (1px solid black) ──
AddBorderToBitmap(pBitmap) {
    if !pBitmap
        return 0
    w := Gdip_GetImageWidth(pBitmap)
    h := Gdip_GetImageHeight(pBitmap)
    if (w <= 0 || h <= 0)
        return 0
    pNew := Gdip_CreateBitmap(w, h)
    if !pNew
        return 0
    pGraphics := Gdip_GraphicsFromImage(pNew)
    if !pGraphics {
        Gdip_DisposeImage(pNew)
        return 0
    }
    Gdip_DrawImage(pGraphics, pBitmap, 0, 0, w, h)
    pPen := Gdip_CreatePen("0xFF000000", 1)
    if pPen {
        Gdip_DrawRectangle(pGraphics, pPen, 0, 0, w - 1, h - 1)
        Gdip_DeletePen(pPen)
    }
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

; ── Clipboard image resize helper ──
ResizeBitmap(pBitmap, scale) {
    if !pBitmap
        return 0
    scale := NormalizeClipScale(scale)
    w := Gdip_GetImageWidth(pBitmap)
    h := Gdip_GetImageHeight(pBitmap)
    if (w <= 0 || h <= 0)
        return 0
    newW := Round(w * scale)
    newH := Round(h * scale)
    if (newW <= 0 || newH <= 0)
        return 0

    pNew := Gdip_CreateBitmap(newW, newH)
    if !pNew
        return 0
    pGraphics := Gdip_GraphicsFromImage(pNew)
    if !pGraphics {
        Gdip_DisposeImage(pNew)
        return 0
    }
    Gdip_SetInterpolationMode(pGraphics, 7) ; 7 = HighQualityBicubic
    Gdip_DrawImage(pGraphics, pBitmap, 0, 0, newW, newH, 0, 0, w, h)
    Gdip_DeleteGraphics(pGraphics)
    return pNew
}

; ── Scale-menu update and persistence ──
SetClipScale(scale) {
    global CLIP_SCALE, REG_PATH
    scale := NormalizeClipScale(scale)
    CLIP_SCALE := scale
    saved := SafeRegWriteString(scale, REG_PATH, "Scale")
    UpdateScaleMenu()
    return saved
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
    static options := 0
    if !options {
        options := [{ label: "Korean (ko)", code: "ko" }, { label: "English (en)", code: "en" }, { label: "Polish (pl)", code: "pl" }, { label: "Albanian (sq)", code: "sq" }, { label: "Armenian (hy)", code: "hy" }, { label: "Azerbaijani (az)", code: "az" }, { label: "Basque (eu)", code: "eu" }, { label: "Belarusian (be)", code: "be" }, { label: "Bosnian (bs)", code: "bs" }, { label: "Bulgarian (bg)", code: "bg" }, { label: "Catalan (ca)", code: "ca" }, { label: "Corsican (co)", code: "co" }, { label: "Croatian (hr)", code: "hr" }, { label: "Czech (cs)", code: "cs" }, { label: "Danish (da)", code: "da" }, { label: "Dutch (nl)", code: "nl" }, { label: "Esperanto (eo)", code: "eo" }, { label: "Estonian (et)", code: "et" }, { label: "Finnish (fi)", code: "fi" }, { label: "French (fr)", code: "fr" }, { label: "Frisian (fy)", code: "fy" }, { label: "Galician (gl)", code: "gl" }, { label: "Georgian (ka)", code: "ka" }, { label: "German (de)", code: "de" }, { label: "Greek (el)", code: "el" }, { label: "Hungarian (hu)", code: "hu" }, { label: "Icelandic (is)", code: "is" }, { label: "Irish (ga)", code: "ga" }, { label: "Italian (it)", code: "it" }, { label: "Latin (la)", code: "la" }, { label: "Latvian (lv)", code: "lv" }, { label: "Lithuanian (lt)", code: "lt" }, { label: "Luxembourgish (lb)", code: "lb" }, { label: "Macedonian (mk)", code: "mk" }, { label: "Maltese (mt)", code: "mt" }, { label: "Norwegian (no)", code: "no" }, { label: "Portuguese (pt)", code: "pt" }, { label: "Romanian (ro)", code: "ro" }, { label: "Russian (ru)", code: "ru" }, { label: "Scots Gaelic (gd)", code: "gd" }, { label: "Serbian (sr)", code: "sr" }, { label: "Slovak (sk)", code: "sk" }, { label: "Slovenian (sl)", code: "sl" }, { label: "Spanish (es)", code: "es" }, { label: "Swedish (sv)", code: "sv" }, { label: "Turkish (tr)", code: "tr" }, { label: "Ukrainian (uk)", code: "uk" }, { label: "Welsh (cy)", code: "cy" }, { label: "Yiddish (yi)", code: "yi" }
        ]
    }
    return options.Clone()
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
    return SafeRegWriteString(lang, REG_PATH, "TranslateLang")
}

SetTextTranslateFontSize(fontSize) {
    global TEXT_TRANSLATE_FONT_SIZE, REG_PATH
    fontSize := NormalizeTextTranslateFontSize(fontSize)
    TEXT_TRANSLATE_FONT_SIZE := fontSize
    return SafeRegWriteString(fontSize, REG_PATH, "TextTranslateFontSize")
}

GetTextTranslateHotkeyOptions() {
    return [{ label: "Win + CapsLock", hotkey: "#CapsLock" }, { label: "Win + Shift + CapsLock", hotkey: "#+CapsLock" }, { label: "Win + Alt + CapsLock", hotkey: "#!CapsLock" }, { label: "Ctrl + Alt + CapsLock", hotkey: "^!CapsLock" }, { label: "Ctrl + Shift + CapsLock", hotkey: "^+CapsLock" }
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
    ; Win+CapsLock is always registered as a static hotkey, so add only user-selected alternatives.
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

    saved := SafeRegWriteString(hotkey, REG_PATH, "TranslateHotkey")
    UpdateTrayTextTranslateMenuLabel()
    return saved
}

UpdateTrayTextTranslateMenuLabel() {
    global Tray, TRAY_TEXT_TRANSLATE_ITEM, TEXT_TRANSLATE_HOTKEY
    newItem := "🌐 Translate Selected Text (" GetTextTranslateHotkeyLabel(TEXT_TRANSLATE_HOTKEY) ")"
    try Tray.Rename(TRAY_TEXT_TRANSLATE_ITEM, newItem)
    TRAY_TEXT_TRANSLATE_ITEM := newItem
}

SwitchDashboardPanel(tabIndex, TabGenBtn, TabTrnBtn, TabAbtBtn, GenPanel, TrnPanel, AbtPanel) {
    TabGenBtn.Opt("cGray +BackgroundTrans")
    TabGenBtn.Redraw()
    TabTrnBtn.Opt("cGray +BackgroundTrans")
    TabTrnBtn.Redraw()
    TabAbtBtn.Opt("cGray +BackgroundTrans")
    TabAbtBtn.Redraw()

    for ctrl in GenPanel
        ctrl.Visible := false
    for ctrl in TrnPanel
        ctrl.Visible := false
    for ctrl in AbtPanel
        ctrl.Visible := false

    if (tabIndex == 1) {
        TabGenBtn.Opt("cWhite -BackgroundTrans Background3F3F46")
        TabGenBtn.Redraw()
        for ctrl in GenPanel
            ctrl.Visible := true
    } else if (tabIndex == 2) {
        TabTrnBtn.Opt("cWhite -BackgroundTrans Background3F3F46")
        TabTrnBtn.Redraw()
        for ctrl in TrnPanel
            ctrl.Visible := true
    } else if (tabIndex == 3) {
        TabAbtBtn.Opt("cWhite -BackgroundTrans Background3F3F46")
        TabAbtBtn.Redraw()
        for ctrl in AbtPanel
            ctrl.Visible := true
    }
}

SaveDashboardSettings(StartupChk, ScaleCombo, FontSizeEdit, HotkeyCombo, LangCombo, LV_ImageLangs) {
    global IMAGE_TRANSLATE_LANGS, REG_PATH
    settingsSaved := true

    if StartupChk.Value {
        if !EnableStartup()
            settingsSaved := false
    } else {
        if !DisableStartup()
            settingsSaved := false
    }

    if !SetClipScale(GetScaleFromLabel(ScaleCombo.Text))
        settingsSaved := false
    if !SetTextTranslateFontSize(FontSizeEdit.Value)
        settingsSaved := false
    if !SetTextTranslateHotkey(GetTextTranslateHotkeyByLabel(HotkeyCombo.Text))
        settingsSaved := false
    if !SetTextTranslateLang(GetTextTranslateLangCodeByLabel(LangCombo.Text))
        settingsSaved := false

    selectedCodes := []
    row := 0
    Loop {
        row := LV_ImageLangs.GetNext(row, "Checked")
        if not row
            break
        label := LV_ImageLangs.GetText(row)
        selectedCodes.Push(GetTextTranslateLangCodeByLabel(label))
    }

    newImageLangs := ""
    for i, code in selectedCodes
        newImageLangs .= (i == 1 ? "" : ",") code
    IMAGE_TRANSLATE_LANGS := NormalizeLangCodeList(newImageLangs)
    if !SafeRegWriteString(IMAGE_TRANSLATE_LANGS, REG_PATH, "ImageTranslateLangs")
        settingsSaved := false
    UpdateImageTranslateMenu()

    return settingsSaved
}

ShowDashboardDialog() {
    global APP_NAME, APP_VERSION, DashboardHwnd, CLIP_SCALE, TEXT_TRANSLATE_LANG, TEXT_TRANSLATE_HOTKEY, TEXT_TRANSLATE_FONT_SIZE, IMAGE_TRANSLATE_LANGS, bmcBtnPath

    if (DashboardHwnd && WinExist("ahk_id " DashboardHwnd)) {
        WinActivate("ahk_id " DashboardHwnd)
        return
    }

    DashGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border -DPIScale", APP_NAME " Settings")
    DashGui.BackColor := "1E1E24"
    DashGui.SetFont("s9", "Segoe UI")

    ; --- Title bar ---
    DashGui.Add("Text", "x0 y0 w780 h45 Background141416", "")
    TitleTxt := DashGui.Add("Text", "x15 y12 w350 h25 +BackgroundTrans cWhite", "⚙️ " APP_NAME " Settings")
    TitleTxt.SetFont("s11 Bold", "Segoe UI")
    CloseBtn := DashGui.Add("Text", "x745 y10 w25 h25 Center +0x200 +BackgroundTrans cGray", "×")
    CloseBtn.SetFont("s16 Bold")

    DestroyDash(*) {
        global DashboardHwnd := 0
        DashGui.Destroy()
    }
    CloseBtn.OnEvent("Click", DestroyDash)

    ; --- Left sidebar ---
    DashGui.Add("Text", "x0 y45 w160 h455 Background27272A", "") ; Sidebar background

    ; Tab buttons
    TabGenBtn := DashGui.Add("Text", "x10 y60 w140 h40 +0x200 Center +BackgroundTrans cWhite Background3F3F46", "⚙️ General")
    TabGenBtn.SetFont("s10 Bold", "Segoe UI")

    TabTrnBtn := DashGui.Add("Text", "x10 y110 w140 h40 +0x200 Center +BackgroundTrans cGray", "🌐 Translation")
    TabTrnBtn.SetFont("s10 Bold", "Segoe UI")

    TabAbtBtn := DashGui.Add("Text", "x10 y160 w140 h40 +0x200 Center +BackgroundTrans cGray", "ℹ️ About")
    TabAbtBtn.SetFont("s10 Bold", "Segoe UI")

    ManualBtn := DashGui.Add("Text", "x10 y450 w140 h32 BackgroundFFDD00 c1E1E24 Center +0x200", "📖 Manual")
    ManualBtn.SetFont("s10 Bold", "Segoe UI")
    ManualBtn.OnEvent("Click", (*) => ShowManualDialog())

    ; --- Right content container ---

    ; 1. General Panel
    GenPanel := []
    lbl1 := DashGui.Add("Text", "x180 y60 w580 h22 +BackgroundTrans cFFFFFF", "Image Paste Default")
    lbl1.SetFont("s10 Bold")
    GenPanel.Push(lbl1)

    GenPanel.Push(DashGui.Add("Text", "x180 y94 w180 h22 +BackgroundTrans cCCCCCC", "Clipboard Image Size"))
    ScaleCombo := DashGui.Add("DropDownList", "x380 y90 w150 Choose" GetScaleIndex(CLIP_SCALE), GetScaleLabels())
    GenPanel.Push(ScaleCombo)

    GenPanel.Push(DashGui.Add("Text", "x180 y126 w580 h1 Background3F3F46", ""))

    lblTextSize := DashGui.Add("Text", "x180 y145 w580 h22 +BackgroundTrans cFFFFFF", "Selected Text Translation")
    lblTextSize.SetFont("s10 Bold")
    GenPanel.Push(lblTextSize)

    GenPanel.Push(DashGui.Add("Text", "x180 y178 w180 h22 +BackgroundTrans cCCCCCC", "Translate Font Size"))
    FontSizeEdit := DashGui.Add("Edit", "x380 y174 w80 h24 Number", TEXT_TRANSLATE_FONT_SIZE)
    GenPanel.Push(FontSizeEdit)

    GenPanel.Push(DashGui.Add("Text", "x180 y214 w580 h1 Background3F3F46", ""))

    lbl2 := DashGui.Add("Text", "x180 y235 w580 h22 +BackgroundTrans cFFFFFF", "System Settings")
    lbl2.SetFont("s10 Bold")
    GenPanel.Push(lbl2)
    GenPanel.Push(DashGui.Add("Text", "x180 y265 w580 h52 Background2A2D3C", ""))
    isStartup := IsStartupEnabled()
    StartupChk := DashGui.Add("CheckBox", "x195 y275 w550 h30 Background2A2D3C cWhite" (isStartup ? " Checked" : ""), "  Run app when Windows starts")
    StartupChk.SetFont("s10 Bold", "Segoe UI")
    GenPanel.Push(StartupChk)

    ; 2. Translation Panel
    TrnPanel := []
    lbl3 := DashGui.Add("Text", "x180 y60 w580 h22 +BackgroundTrans cFFFFFF", "Text Translation Default")
    lbl3.SetFont("s10 Bold")
    TrnPanel.Push(lbl3)

    TrnPanel.Push(DashGui.Add("Text", "x180 y90 w180 h22 +BackgroundTrans cCCCCCC", "Translation Hotkey"))
    HotkeyCombo := DashGui.Add("DropDownList", "x360 y86 w390 Choose" GetTextTranslateHotkeyIndex(TEXT_TRANSLATE_HOTKEY), GetTextTranslateHotkeyLabels())
    TrnPanel.Push(HotkeyCombo)

    TrnPanel.Push(DashGui.Add("Text", "x180 y132 w180 h22 +BackgroundTrans cCCCCCC", "Target Language"))
    LangCombo := DashGui.Add("DropDownList", "x360 y128 w390 Choose" GetTextTranslateLangIndex(TEXT_TRANSLATE_LANG), GetTextTranslateLangLabels())
    TrnPanel.Push(LangCombo)

    TrnPanel.Push(DashGui.Add("Text", "x180 y180 w580 h1 Background3F3F46", ""))

    lbl4 := DashGui.Add("Text", "x180 y195 w580 h22 +BackgroundTrans cFFFFFF", "Image Translate Menu Languages (Multi-select)")
    lbl4.SetFont("s10 Bold")
    TrnPanel.Push(lbl4)
    LV_ImageLangs := DashGui.Add("ListView", "x180 y225 w470 h180 +Checked -Hdr Background2D2D35 cE0E0E0", ["Language"])
    LV_ImageLangs.SetFont("s9", "Segoe UI")
    TrnPanel.Push(LV_ImageLangs)

    UpBtn := DashGui.Add("Button", "x660 y225 w100 h30", "▲ Up")
    DownBtn := DashGui.Add("Button", "x660 y265 w100 h30", "▼ Down")
    TrnPanel.Push(UpBtn)
    TrnPanel.Push(DownBtn)

    langArray := StrSplit(IMAGE_TRANSLATE_LANGS, ",")
    options := GetTextTranslateLangOptions()

    ; 1. Add saved languages first, preserving checked order.
    for _, code in langArray {
        code := Trim(code)
        if (code == "")
            continue
        for idx, opt in options {
            if (opt.code == code) {
                LV_ImageLangs.Add("Check", opt.label)
                options.RemoveAt(idx)
                break
            }
        }
    }

    ; 2. Append remaining languages unchecked.
    for _, opt in options {
        LV_ImageLangs.Add("", opt.label)
    }

    ; --- List item up/down movement helpers ---
    IsRowChecked(r) {
        curr := 0
        Loop {
            curr := LV_ImageLangs.GetNext(curr, "Checked")
            if (!curr)
                return false
            if (curr == r)
                return true
        }
        return false
    }

    MoveItemUp(*) {
        row := LV_ImageLangs.GetNext(0, "Focused")
        if (row > 1) {
            txt1 := LV_ImageLangs.GetText(row)
            chk1 := IsRowChecked(row)

            txt2 := LV_ImageLangs.GetText(row - 1)
            chk2 := IsRowChecked(row - 1)

            LV_ImageLangs.Modify(row, (chk2 ? "Check" : "-Check") " -Select", txt2)
            LV_ImageLangs.Modify(row - 1, (chk1 ? "Check" : "-Check") " Select Focus", txt1)
        }
    }

    MoveItemDown(*) {
        row := LV_ImageLangs.GetNext(0, "Focused")
        if (row > 0 && row < LV_ImageLangs.GetCount()) {
            txt1 := LV_ImageLangs.GetText(row)
            chk1 := IsRowChecked(row)

            txt2 := LV_ImageLangs.GetText(row + 1)
            chk2 := IsRowChecked(row + 1)

            LV_ImageLangs.Modify(row, (chk2 ? "Check" : "-Check") " -Select", txt2)
            LV_ImageLangs.Modify(row + 1, (chk1 ? "Check" : "-Check") " Select Focus", txt1)
        }
    }

    UpBtn.OnEvent("Click", MoveItemUp)
    DownBtn.OnEvent("Click", MoveItemDown)

    ; 3. About Panel
    AbtPanel := []
    lbl5 := DashGui.Add("Text", "x180 y60 w430 h35 +BackgroundTrans cWhite", APP_NAME)
    lbl5.SetFont("s10 Bold")
    AbtPanel.Push(lbl5)

    AbtPanel.Push(DashGui.Add("Text", "x180 y100 w580 h20 +BackgroundTrans cGray", "Version " APP_VERSION " • Screen Capture, Annotation & Translation Tool"))


    AbtPanel.Push(DashGui.Add("Text", "x180 y130 w580 h1 Background3F3F46", ""))

    AbtPanel.Push(DashGui.Add("Text", "x180 y150 w580 h120 Background27272A", ""))

    lbl6 := DashGui.Add("Text", "x195 y160 w550 h20 +BackgroundTrans cWhite", "👤 Developer Info")
    lbl6.SetFont("s10 Bold")
    AbtPanel.Push(lbl6)
    AbtPanel.Push(DashGui.Add("Text", "x195 y185 w430 h20 +BackgroundTrans cCCCCCC", "Kwang Beom Park (Bob)"))
    AbtPanel.Push(DashGui.Add("Text", "x195 y205 w430 h50 +BackgroundTrans cA0A0A0", "A finance professional passionate about office automation and daily productivity."))

    githubLoaded := false
    if FileExist(githubIconPath) {
        try {
            GithubPic := DashGui.Add("Picture", "x650 y165 w64 h64 +BackgroundTrans", githubIconPath)
            GithubPic.OnEvent("Click", (*) => Run("https://github.com/KwangBeomPark"))
            AbtPanel.Push(GithubPic)
            githubLoaded := true
        }
    }

    if !githubLoaded {
        GithubLink := DashGui.Add("Link", "x650 y195 w90 h30 Center Background27272A", '<a href="https://github.com/KwangBeomPark" id="github">GitHub</a>')
        AbtPanel.Push(GithubLink)
    }

    AbtPanel.Push(DashGui.Add("Text", "x180 y285 w580 h135 Background2D2D35", ""))
    AbtPanel.Push(DashGui.Add("Text", "x195 y295 w550 h20 +BackgroundTrans cFFDD00", "☕ Support This Project"))
    AbtPanel.Push(DashGui.Add("Text", "x195 y320 w550 h40 +BackgroundTrans cE0E0E0", "If this tool helps reduce repetitive work, your support will encourage me to continue building more tools."))

    if FileExist(bmcBtnPath) {
        BmcPic := DashGui.Add("Picture", "x382 y370 w176 h40 +BackgroundTrans", bmcBtnPath)
        BmcPic.OnEvent("Click", (*) => Run("https://www.buymeacoffee.com/KBPark_Bob"))
        AbtPanel.Push(BmcPic)
    } else {
        BmcLink := DashGui.Add("Link", "x195 y375 w550 h30 Center Background2D2D35 cYellow", '<a href="https://www.buymeacoffee.com/KBPark_Bob">☕ Click here to Support</a>')
        AbtPanel.Push(BmcLink)
    }

    TabGenBtn.OnEvent("Click", (*) => SwitchDashboardPanel(1, TabGenBtn, TabTrnBtn, TabAbtBtn, GenPanel, TrnPanel,
        AbtPanel))
    TabTrnBtn.OnEvent("Click", (*) => SwitchDashboardPanel(2, TabGenBtn, TabTrnBtn, TabAbtBtn, GenPanel, TrnPanel,
        AbtPanel))
    TabAbtBtn.OnEvent("Click", (*) => SwitchDashboardPanel(3, TabGenBtn, TabTrnBtn, TabAbtBtn, GenPanel, TrnPanel,
        AbtPanel))

    ; --- Shared bottom buttons ---
    DashGui.Add("Text", "x160 y440 w620 h1 Background3F3F46", "") ; Top border divider
    SaveBtn := DashGui.Add("Button", "x550 y455 w100 h32", "Save && Close")
    CancelBtn := DashGui.Add("Button", "x660 y455 w100 h32", "Cancel")

    SaveAllSettings(*) {
        settingsSaved := SaveDashboardSettings(StartupChk, ScaleCombo, FontSizeEdit, HotkeyCombo, LangCombo, LV_ImageLangs)
        if settingsSaved
            ToolTip("✅ All settings saved.")
        else
            ToolTip("⚠️ Some settings could not be saved.`r`n⚠️ 일부 설정을 저장하지 못했습니다.")
        SetTimer(() => ToolTip(), -1500)
        DestroyDash()
    }

    SaveBtn.OnEvent("Click", SaveAllSettings)
    CancelBtn.OnEvent("Click", DestroyDash)

    DashGui.OnEvent("Close", DestroyDash)
    DashGui.OnEvent("Escape", DestroyDash)

    ; Initial tab setup
    SwitchDashboardPanel(1, TabGenBtn, TabTrnBtn, TabAbtBtn, GenPanel, TrnPanel, AbtPanel)

    ; ── Center the settings window on the monitor containing the mouse cursor ──
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    monLeft := 0, monTop := 0, monRight := A_ScreenWidth, monBottom := A_ScreenHeight
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
        if (mx >= mLeft && mx <= mRight && my >= mTop && my <= mBottom) {
            monLeft := mLeft, monTop := mTop, monRight := mRight, monBottom := mBottom
            break
        }
    }
    centerX := monLeft + (monRight - monLeft - 780) // 2
    centerY := monTop + (monBottom - monTop - 500) // 2

    DashGui.Show("x" centerX " y" centerY " w780 h500")
    DashboardHwnd := DashGui.Hwnd
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
    ; Iterate the map and close all windows.
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
    static currentMonitor := 0  ; Monitor toggle state

    arr := []
    for hwnd, winInfo in ClipWins {
        arr.Push(winInfo)
    }

    n := arr.Length
    if (n == 0)
        return

    ; Check monitor count and cycle the target monitor.
    monCount := MonitorGetCount()
    currentMonitor := Mod(currentMonitor, monCount) + 1  ; 1 → 2 → ... → 1

    ; Get the top-left coordinates of the selected monitor.
    MonitorGet(currentMonitor, &monLeft, &monTop)

    ; Sort by ID using bubble sort.
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

    ; Cascade windows from the selected monitor's top-left corner.
    for index, winInfo in arr {
        x := monLeft + (n - index) * MINI_SIZE
        y := monTop + (index - 1) * MINI_SIZE
        WinMove(x, y, , , winInfo.gui.Hwnd)
        WinMoveTop("ahk_id " winInfo.gui.Hwnd)
    }

    ToolTip("📐 모니터 " currentMonitor "/" monCount " 정렬`r`n📐 Sorted to Monitor " currentMonitor "/" monCount)
    SetTimer(() => ToolTip(), -1500)
}

; ── Windows startup auto-run helpers ──
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
    return SafeRegWriteString(exePath, regKey, "ScreenClipTool")
}

DisableStartup() {
    static regKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    try RegDelete(regKey, "ScreenClipTool")
    return !IsStartupEnabled()
}

; ── Manual dialog ──
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

    ; ── Language dropdown ──
    ManGui.Add("Text", "x14 y12 w70 h22 cBlack", "Language:")
    ManGui.SetFont("s9", "Segoe UI")
    langList := ["KR 한국어", "US English", "PL Polski", "DE Deutsch", "FR Français", "ES Español"]
    LangDDL := ManGui.Add("DropDownList", "x90 y9 w140 Choose2", langList)

    ; ── Manual text area ──
    ManEdit := ManGui.Add("Edit", "x14 y42 w552 h800 ReadOnly +Multi +VScroll", GetManualText("en"))

    ; ── Bottom Close button ──
    CloseMBtn := ManGui.Add("Button", "x240 y852 w100 h32", "Close")
    CloseMBtn.SetFont("s9", "Segoe UI")

    ; Language-change event
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

    ; Resize handler
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
