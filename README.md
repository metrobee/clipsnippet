# ClipSnippet 📋⚡️

ClipSnippet on kerge ja kiire macOS-i taustarakendus, mis ühendab endas **lõikelaua ajaloo (Clipboard History)** ja **tekstilaiendused (Snippets / Espanso)**. See on loodud asendama Alfredi lõikelauda ja Espansot ühes lihtsas, kiirelt kohandatavas programmis.

Rakendus töötab taustal, ei oma ikooni Dockis (töötab agent-režiimis) ning lisab süsteemi ülemisse menüüribasse väikese `📋` ikooni.

---

## 🚀 Kasutamine

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
    ":ar5": "Great guest, highly recommended! 5/5 stars.",
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
*   **Muutujad:** Snippetis saab kasutada kohahoidjat `[[muutuja_nimi]]`. Kui selline snippet käivitatakse, küsib rakendus sisendit hüpikaknaga ja asendab selle enne kleepimist.

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
