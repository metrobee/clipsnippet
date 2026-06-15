# ClipSnippet 📋⚡️

ClipSnippet on kerge ja kiire macOS-i taustarakendus, mis ühendab endas **lõikelaua ajaloo (Clipboard History)** ja **tekstilaiendused (Snippets / Espanso)**. See on loodud asendama Alfredi lõikelauda ja Espansot ühes lihtsas, kiirelt kohandatavas programmis.

Rakendus töötab taustal, ei oma ikooni Dockis (töötab agent-režiimis) ning lisab süsteemi ülemisse menüüribasse väikese `📋` ikooni.

---

## 🚀 Kasutamine

* **Käivitamine:** Vajuta klahvikombinatsiooni **`Cmd + Option + C`** (või klõpsa `📋` ikoonil menüüribal), et avada otsinguaken.
* **Otsimine:** Otsinguaken avaneb alati ekraani keskel ja on kohe kirjutamiseks valmis. Otsida saab nii kopeeritud tekstide sisust kui ka lühendite (trigerite) järgi.
  * `📋` tähistab lõikelaua ajaloo elemente.
  * `⚡️` tähistab tekstilaiendusi (snippets).
* **Sisestamine (kleepimine):**
  * Vali nooleklahvidega (Üles/Alla) sobiv rida ja vajuta **Enter** – aken sulgub ning tekst kleebitakse automaatselt sinu aktiivsesse tekstikasti.
  * Vajuta kiirklahvi **`Cmd + 1`** kuni **`Cmd + 9`**, et kleepida koheselt vastav rida otse nimekirjast (ilma nooltega navigeerimata).
* **Sulgemine:** Vajuta **Escape**, et otsinguaken peita ilma midagi kleepimata.

---

## ⚙️ Seadistamine ja Tekstilaiendused (Snippets)

Tekstilaiendused on kirjeldatud lihtsas JSON-failis, mis asub sinu kodukaustas teel:
`~/.clipsnippet_snippets.json`

Selle faili muutmiseks võid klõpsata menüüribal ikoonil `📋` ja valida **Edit Snippets...** – fail avaneb sinu vaikimisi tekstiredaktoris.

### Vaikimisi seadistatud laiendused:
* **`:date`** – Kleebib jooksva kuupäeva vormingus `YYYY-MM-DD` (näiteks `2026-06-15`).
* **`:time`** – Kleebib jooksva kellaaja vormingus `HH:MM:SS`.
* **`:shrug`** – Kleebib emoji: `¯\_(ツ)_/¯`.
* **`:br`** – Kleebib eeltäidetud kirjalõpu: `Best regards,\nMetrobee`.
* **`:koor`** – Kleebib koori nime: `Segakoor Hilaro`.

Uute laienduste lisamiseks lisa faili lihtsalt uus rida kujul `"triger": "väärtus"`. Muudatused rakenduvad koheselt pärast faili salvestamist ja otsinguakna uuesti avamist.

Lõikelaua ajalugu salvestatakse automaatselt faili `~/.clipsnippet_history.json` (kuni 100 viimast elementi).

---

## 🛠️ Automaatne käivitumine sisselogimisel

Et rakendus käivituks alati koos arvutiga:
1. Ava **System Settings** -> **General** -> **Login Items**.
2. Klõpsa allpool plussmärgile (`+`).
3. Vali kaustast `/Users/metrobee/GEMINI/clipsnippet/` fail **`ClipSnippet.app`** ja lisa see nimekirja.

---

## 💻 Koodi uuesti kompileerimine (vajadusel)

Kui soovid tulevikus koodi muuta, saad rakenduse uuesti kompileerida ja pakkida käivitades samast kaustast terminalis:
```bash
swiftc -sdk $(xcrun --show-sdk-path) -O main.swift -o ClipSnippet && ./package.sh
```
