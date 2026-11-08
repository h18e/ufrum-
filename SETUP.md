# Ufrumä – Einrichtung

## 1. Signierung (einmalig)

Die Datei `Config/Signing.local.xcconfig` enthält deine Team-ID und ist bewusst **nicht** im Git.
Auf deinem MacBook ist sie schon angelegt. Auf einem anderen Mac:

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

Dann die Team-ID eintragen (Xcode → Settings… (⌘,) → Accounts → dein Account → Team).

## 2. App bauen und nach /Applications kopieren

Wichtig: Der **Festplattenvollzugriff ist an den Speicherort und die Signatur gebunden**. Am stabilsten ist es, die App einmal nach `/Applications` zu legen und von dort zu starten.

1. `Ufrumae.xcodeproj` in Xcode öffnen
2. Oben links das Schema **Ufrumae** und **My Mac** wählen
3. **Product → Archive** – oder schneller: **Product → Build (⌘B)**, dann
   **Product → Show Build Folder in Finder**, in `Products/Debug` liegt `Ufrumae.app`
4. `Ufrumae.app` nach **Programme** (`/Applications`) ziehen und dort starten

Zum schnellen Ausprobieren geht auch **⌘R** direkt in Xcode – dann musst du den Festplattenvollzugriff aber evtl. nach Builds neu erteilen.

## 3. Festplattenvollzugriff erteilen

Ohne ihn sieht Ufrumä z. B. den Papierkorb nicht, und macOS unterbricht den Scan mit Rückfragen („Ufrumä möchte auf Downloads zugreifen“).

1. Ufrumä starten → im orangen Banner auf **Einstellungen öffnen**
   (oder: **Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff**)
2. Falls Ufrumä nicht in der Liste steht: **+** klicken → `/Applications/Ufrumae.app` wählen
3. Schalter bei **Ufrumä** einschalten
4. Ufrumä **beenden und neu starten** (⌘Q)

## 4. Erster Durchlauf

1. Ufrumä scannt beim Start automatisch (sobald der Vollzugriff da ist), sonst oben auf **Scannen** (⌘R).
2. **Probelauf ist an** – klicke auf **Probelauf starten**: Ufrumä zeigt, was frei würde, löscht aber nichts.
3. Bereiche in der Seitenleiste durchgehen, Häkchen prüfen. Rechtsklick auf einen Eintrag:
   **Im Finder zeigen**, **Ordner/Datei schützen**, **Immer ignorieren**.
   Zurück zur Gesamtansicht: oben links **‹ Übersicht** oder **⌘[** (oder ganz oben in der Seitenleiste auf **Übersicht**).
4. Wenn alles passt: im blauen Banner **Probelauf beenden** → **Aufräumen**.

## 5. Menüleiste und Autostart

- Das Laufwerk-Symbol oben rechts zeigt den freien Speicher, warnt unter 20 GB und bietet einen **Schnell-Scan** (ohne grosse Dateien und Duplikate).
- Autostart: **Ufrumä → Einstellungen… (⌘,) → Allgemein → „Ufrumä beim Anmelden starten“**.

## Häufige Stolpersteine

| Meldung / Verhalten | Ursache / Lösung |
|---|---|
| Scan bleibt bei „Alte Downloads“ oder „App-Caches“ hängen | macOS wartet auf eine Erlaubnis-Abfrage (evtl. hinter dem Fenster). Erlauben klicken – oder Festplattenvollzugriff erteilen. |
| „Festplattenvollzugriff fehlt“, obwohl eingeschaltet | Ufrumä neu starten (⌘Q). Prüfen, dass in der Liste genau die App aus `/Applications` eingeschaltet ist – nach einem neuen Build die alte Kopie in Programme durch die neue ersetzen. Notfalls Ufrumä in der Liste mit **–** entfernen und mit **+** neu hinzufügen. |
| Simulator wird nicht gelöscht: „Läuft gerade“ | Simulator-App beenden, neu scannen. |
| Xcode-Caches nicht vorgewählt | Xcode läuft – beenden, neu scannen. |
| Archives fehlen im Organizer | Liegen im Papierkorb – dort „Zurücklegen“. |
