# 📸 ClipOCR-Pro: Office Screen Capture, OCR & Translation Tool
(AI-Assisted ScreenClip Tool v1)

<p align="center">
  <img src="./demo.gif" width="900">
</p>

---

I am **not a professional developer, but a finance practitioner**.
I started developing this to reduce repetitive tasks such as **screen capturing, selected text translation, document organization, and information sharing**,
and this small automation script has gradually evolved into a practical productivity tool.

> **Reducing repetitive work · Improving team productivity · Workflow automation · Solving practical problems**
This is a business support tool created with these goals in mind.


---

# 🚀 Download & Quick Start

**ClipOCR-Pro** is a **portable application** that runs immediately with a simple double-click—no tedious installation required.  
It is specifically designed for easy distribution, allowing general team members with no programming background or advanced computer skills to utilize it instantly with just one click.

### 📥 For General Users (One-Click Portable Download)
1. Navigate to the **[Releases]** tab on the right side of the GitHub page.
2. Download the latest standalone executable **`ClipOCR-Pro.zip`** or **`ClipOCR-Pro.exe`**.
3. Extract the ZIP file and double-click **`ClipOCR-Pro.exe`**. An icon will appear in your Windows system tray, and the tool will be ready to use immediately!
   - *💡 **Team Productivity Tip**: A manager can configure the optimal settings (`config.ini`) and distribute this configuration file to colleagues. Placing it in the same folder as the executable ensures an instant **standardization of productivity across the entire department**.*

### 🛠️ For Power Users & Developers (Custom Build)
This software is **100% open-source** with fully transparent code. If you wish to add custom features or enhance the tool, follow these steps:
1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone this repository and customize the `ClipOCR-Pro.ahk` source code to fit your needs.
3. Use the AutoHotkey compiler (Ahk2Exe) or the included build scripts to package your own custom `ClipOCR-Pro.exe` with personalized icons and metadata.

---

# 💼 Real-World Use Cases
- **Settlement & Supporting Document Review**: Highlight key information to help approvers quickly verify details
- **Translation of Overseas Emails & Documents**: Utilize selected text translation or Google Image Translation
- **Multi-Source Comparison**: Compare ERP / Excel / emails / supporting documents simultaneously
- **Report Preparation**: Keep multiple references visible on the screen while working
- **Meetings & Training Sessions**: Capture parts of manuals and explain by minimizing/restoring
- **Image Translation**: Check email attachments and scanned documents via Google Image Translation
- **Document Attachment Optimization**: Resize captured images based on app settings before pasting

---

# 📖 User Guide
✔ Always-on-top floating capture window, highlighter, multi-monitor alignment  
✔ Capture image → Paste into Google Translate browser (Korean / English / Polish)  
✔ Selected text translation, image resizing  

<p align="center">
<img src="./App01Manual.png" width="1000">
</p>

---

# ⌨️ Main Shortcuts

| Shortcut | Function |
|---------|------|
| `Win + Drag` | Capture screen and float on top |
| `Win + CapsLock` | Translate selected text using Google Translate API |
| `Mouse Right` on floating window | Open image translation, annotation, copy/save, and window management menu |
| `Double Click` on floating window | Minimize / Restore |
| `Ctrl + C` on floating window | Copy floating image |
| `Shift + Drag`, `Ctrl + Drag`, `Alt + Drag`, `Ctrl + Z` on floating window | RedBox, Yellow, Green, Undo |
| `Ctrl + ↑(Up)`, `Ctrl + ↓(Down)`, `Ctrl + ←(Left)`, `Ctrl + Esc` on floating window | (Adjust floating image) Minimize, Original size, Align left, Close all |

---

# Environment & License
🖥️ Supported Environment: Windows 10 / 11, ✘ macOS not supported (Would love to try with Rust someday~)
📄 License: MIT License (GDI+ wrapper by Tariq Porter (tic))

---

## ☕ Support This Project
If this tool has helped reduce repetitive work or improved your productivity,
your small support will be a great help in creating more practical automation tools in the future.

<p align="center">
  <a href="https://www.buymeacoffee.com/KBPark_Bob">
    <img
      src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
      width="220">
  </a>
</p>
