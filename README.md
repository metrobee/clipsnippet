# ClipSnippet 📋⚡️

[English](#english) | [Eesti keeles](#eesti-keeles)

---

## English

ClipSnippet is a lightweight, fast macOS background application that combines **clipboard history** and **text expansion (snippets)** in a single utility. It is designed to replace Alfred's clipboard history and Espanso in a single, simple, and highly customizable package.

The application runs silently in the background, does not show up in the Dock (runs in agent mode), and adds a small `📋` icon to the macOS menu bar.

### 🚀 Usage

*   **Activate:** Press **`Cmd + Option + C`** (or click the `📋` menu bar icon) to open the search window.
*   **Search:** The search window opens centered on your screen and is instantly ready for typing. You can search through clipboard history, snippet triggers, or snippet categories.
*   **Visual Grouping:** The list is grouped under native section headers:
    *   `📋 Clipboard History` – Your recently copied items (displayed first).
    *   `⚡️ Snippets: <Category>` – Your custom text expansions grouped by category.
*   **Insert (Paste):**
    *   Use the arrow keys (Up/Down) to select an item and press **Enter** – the window will hide and the text will be automatically pasted into the active text field.
    *   Press **`Cmd + 1`** through **`Cmd + 9`** to instantly paste the corresponding item from the list (headers are automatically skipped).
*   **Delete History Items (One-by-One):**
    *   Select a clipboard history item (`📋`) and press **`Cmd + Delete`**, **`Option + Delete`**, or **`Ctrl + Delete`** to delete it from the history and files instantly without confirmation dialogs.
    *   If the search input field is completely empty, you can also press the plain **`Delete`** (Backspace) key to delete the selected item.
*   **Close:** Press **Escape** to hide the window without pasting.

### ⚙️ Configuration & Snippets

Snippets are defined in a simple JSON file located in your home directory:
`~/.clipsnippet_snippets.json`

To edit this file, click the `📋` menu bar icon and choose **Edit Snippets...** – it will open in your default text editor.

Changes apply **instantly as soon as you save the file and reopen the search window** (no app restart needed).

#### Configuration Example:
```json
{
  "airbnb-review": {
    "::ar5": "Tere [[Guest Name]], aitäh külastamast! Great guest, highly recommended! 5/5 stars.",
    ":ar-clean": "Left the apartment extremely clean and tidy."
  },
  "personal": {
    ":phone": "+372 555 5555",
    ":email": "metrobee@example.com"
  },
  "General": {
    ":date": "Current Date",
    ":shrug": "¯\\_(ツ)_/¯"
  }
}
```

*   **Dynamic Snippets:** `:date` and `:time` are automatically replaced with the current date and time upon pasting.
*   **Variables:** You can use placeholders like `[[variable_name]]` (as shown in the `:ar5` example with `[[Guest Name]]`). When triggered, the app displays a dialog to fill in the variable value before pasting.

### 🛠️ Automatic Startup (LaunchAgent)

The application can start automatically at login using a macOS LaunchAgent.

The plist configuration file is located at:
`~/Library/LaunchAgents/com.metrobee.clipsnippet.plist`

*   **Enable auto-start (load):**
    ```bash
    launchctl load ~/Library/LaunchAgents/com.metrobee.clipsnippet.plist
    ```
*   **Disable auto-start (unload):**
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.metrobee.clipsnippet.plist
    ```

### 💻 Compiling and Packaging

To recompile, package, and automatically sign the application, run the following in the project directory:
```bash
swiftc -sdk $(xcrun --show-sdk-path) -O main.swift -o ClipSnippet && ./package.sh
```
*Note: `package.sh` signs the app bundle ad-hoc (`codesign`) to ensure macOS doesn't block global hotkeys.*

---

## Eesti keeles

ClipSnippet on kerge ja kiire macOS-i taustarakendus, mis ühendab endas **lõikelaua ajaloo (Clipboard History)** ja **tekstilaiendused (Snippets / Espanso)**. See on loodud asendama Alfredi lõikelauda ja Espanot ühes lihtsas, kiirelt kohandatavas programmis.

Rakendus töötab taustal, ei oma ikooni Dockis (töötab agent-režiimis) ning lisab süsteemi ülemisse menüüribasse väikese `📋` ikooni.

### 🚀 Kasutamine

*   **Käivitamine:** Vajuta klahvikombinatsiooni **`Cmd + Option + C`** (või klõpsa `📋` ikoonil menüüribal), et avada otsinguaken.
*   **Otsimine:** Otsinguaken avaneb alati ekraani keskel ja on kohe kirjutamiseks valmis. Otsida saab nii kopeeritud tekstide sisust, tekstilaienduste trigeritest kui ka kategooriatest.
*   **Grupeerimine:** Nimekiri on jagatud visuaalselt kategooriateks:
    *   `📋 Clipboard History` – Lõikelaua ajalugu (kuvatakse kõige esimesena).
    *   `⚡️ Snippets: <Kategooria>` – Kasutaja seadistatud laiendused vastavalt JSON-faili jaotustele.
*   **Sisestamine (kleepimine):**
    *   Vali nooleklahvidega (Üles/Alla) rida ja vajuta **Enter** – aken sulgub ning tekst kleebitakse automaatselt aktiivsesse tekstikasti.
    *   Vajuta kiirklahvi **`Cmd + 1`** kuni **`Cmd + 9`**, et kleepida koheselt vastav rida otse nimekirjast (sektsioonide pealkirjad hüpatakse otseteede loendamisel automaatselt üle).
*   **Ajaloo kustutamine (ükshaaval):**
    *   Vali noolega ajaloo rida (`📋`) ja vajuta **`Cmd + Delete`**, **`Option + Delete`** või **`Ctrl + Delete`**, et kustutada see element nimekirjast ja failist ilma hoiatusaknata.
    *   Kui otsingukast on täiesti tühi, saab valitud ajaloorea kustutada ka lihtsalt tavalise **`Delete`** (Backspace) klahviga.
*   **Sulgemine:** Vajuta **Escape**, et otsinguaken peita ilma midagi kleepimata.

---

## ⚙️ Seadistamine ja Tekstilaiendused (Snippets)

Tekstilaiendused on kirjeldatud lihtsas JSON-failis, mis asub sinu kodukaustas teel:
`~/.clipsnippet_snippets.json`

Selle faili muutmiseks võid klõpsata menüüribal ikoonil `📋` ja valida **Edit Snippets...** – fail avaneb sinu vaikimisi tekstiredaktoris.

Uued laiendused ja kategooriad rakenduvad **koheselt pärast faili salvestamist ja otsinguakna uuesti avamist** (rakendust ei ole vaja taaskäivitada).

### Seadistuse näide:
```json
{
  "airbnb-review": {
    ":ar5": "Tere [[Külalise nimi]], aitäh külastamast! Great guest, highly recommended! 5/5 stars.",
    ":ar-clean": "Left the apartment extremely clean and tidy."
  },
  "isiklik": {
    ":tel": "+372 555 5555",
    ":email": "metrobee@example.com"
  },
  "Üldised": {
    ":date": "Current Date",
    ":shrug": "¯\\_(ツ)_/¯"
  }
}
```

*   **Dünaamilised laiendused:** `:date` ja `:time` asendatakse kleepimisel automaatselt jooksva kuupäeva ja kellaajaga.
*   **Muutujad:** Snippetis saab kasutada kohahoidjat `[[muutuja_nimi]]` (nagu ülaltoodud `:ar5` näites `[[Külalise nimi]]`). Kui selline snippet käivitatakse, küsib rakendus sisendit hüpikaknaga ja asendab selle enne kleepimist.

---

## 🛠️ Automaatne käivitumine sisselogimisel (LaunchAgent)

Rakendus on seadistatud käivituma automaatselt arvuti sisselülitamisel macOS LaunchAgent abil.

Teenuse seadistusfail asub kaustas:
`~/Library/LaunchAgents/com.metrobee.clipsnippet.plist`

*   **Automaatse käivituse lubamine (registreerimine):**
    ```bash
    launchctl load ~/Library/LaunchAgents/com.metrobee.clipsnippet.plist
    ```
*   **Automaatse käivituse keelamine (eemaldamine):**
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.metrobee.clipsnippet.plist
    ```

---

## 💻 Koodi uuesti kompileerimine ja pakkimine

Kui teed koodis muudatusi, saad rakenduse uuesti kompileerida, pakkida ja automaatselt allkirjastada käivitades kaustas terminalis:
```bash
swiftc -sdk $(xcrun --show-sdk-path) -O main.swift -o ClipSnippet && ./package.sh
```
*Märkus: `package.sh` allkirjastab rakenduse ad-hoc allkirjaga (`codesign`), mis tagab, et macOS ei blokeeri selle tööd.*
