# Ufrumä

Eine macOS-App (SwiftUI, macOS 27), die den Mac aufräumt – mit besonderem Augenmerk auf die Datenberge, die Xcode beim App-Entwickeln hinterlässt. Nur für den eigenen Mac gedacht (keine Sandbox, kein App Store).

## Grundsätze

- **Immer zuerst Vorschau.** Ufrumä scannt, zeigt alles mit Grösse und Häkchen – gelöscht wird erst nach Bestätigung.
- **Probelauf** ist standardmässig an: Es wird nichts gelöscht, nur angezeigt, was passieren würde. Ausschalten im gelben/blauen Banner oder unter Einstellungen.
- **Löschart pro Bereich:** Caches und Build-Daten werden direkt gelöscht (sie entstehen neu). Alles Persönliche oder Unersetzliche geht in den Papierkorb. Simulatoren und Paket-Caches werden über die offiziellen Werkzeuge entfernt (`xcrun simctl`, `npm cache clean` …).
- **Sicherheitsprüfung** (`SafetyGuard`) vor jedem Löschen: nur im Benutzerordner, nie wichtige Wurzelordner, nie Fotos-Mediathek/iCloud, nie etwas auf der Schutzliste.
- **Verlauf** aller Aufräum-Aktionen in `~/Library/Application Support/Ufrumae/history.json`.

## Bereiche und Regeln

| Bereich | Regel (Standard) | Löschart |
|---|---|---|
| iOS DeviceSupport | pro Gerätemodell nur die neueste iOS-Version behalten | direkt |
| Simulator-Geräte | „unavailable“ oder seit 60 Tagen nicht gestartet | `simctl delete` |
| Simulator-Runtimes | ältere Version, wenn neuere derselben Plattform da ist | `simctl runtime delete` |
| DerivedData | seit 14 Tagen nicht gebaut oder Projekt existiert nicht mehr | direkt |
| Archives | pro App die letzten 3 behalten | Papierkorb |
| Xcode-Caches | Previews, SwiftPM, Doku-Cache, Simulator-Logs … | direkt |
| App-Caches | `~/Library/Caches`, Fremd-Apps vorgewählt, Apple nur Ansicht | direkt |
| Logs | `~/Library/Logs` | direkt |
| Entwickler-Caches | npm, pip, Yarn, CocoaPods, Homebrew, Gradle, pnpm | Befehl / direkt |
| Papierkorb | leeren | endgültig |
| Alte Downloads | seit 90 Tagen nicht geöffnet | Papierkorb |
| Grosse Dateien | ab 1 GB, nur anzeigen, inkl. Ordnerübersicht | Papierkorb (wenn gewählt) |
| Doppelte Dateien | SHA-256, ab 1 MB, älteste Kopie bleibt | Papierkorb |
| Reste alter Apps | Bundle-ID ohne installierte App, nie vorgewählt | Papierkorb |
| iPhone-Backups, lokale Snapshots | nur Ansicht | – |

Alle Schwellen sind unter **Ufrumä → Einstellungen… (⌘,) → Regeln** anpassbar.

## Aufbau

```
Ufrumae/
  App/         UfrumaeApp.swift – Hauptfenster, Menüleiste, Einstellungen
  Model/       Category (Bereiche), CleanupItem (Funde), AppModel (Zustand + Einstellungen)
  Engine/      FileSystem, Shell, SafetyGuard, Cleaner (Löschen + Verlauf), ScanEngine
  Scanners/    XcodeScanners, GeneralScanners, AnalysisScanners – je ein Scanner pro Bereich
  Views/       Oberfläche
UfrumaeTests/  Regeln + Sicherheitsprüfung (RuleTests), Live-Scan nur auf Wunsch (LiveScanTests)
Design/       App-Icon (Original + 1024er-Vorlage mit macOS-Form)
Config/        Signierung (Team-ID lokal, nicht im Git), Entitlements
```

Neuer Bereich = neuer `CategoryID`-Fall + ein `Scanner` + Eintrag in `ScanEngine.scanner(for:)`.

## Bauen und testen

```bash
xcodebuild -project Ufrumae.xcodeproj -scheme Ufrumae -destination 'platform=macOS' test
```

Live-Scan deines echten Macs (liest nur, löscht nichts):

```bash
TEST_RUNNER_UFRUMAE_LIVE=1 xcodebuild -project Ufrumae.xcodeproj -scheme Ufrumae -destination 'platform=macOS' test -only-testing:UfrumaeTests/LiveScanTests
```

Einrichtung Schritt für Schritt: siehe [SETUP.md](SETUP.md).
