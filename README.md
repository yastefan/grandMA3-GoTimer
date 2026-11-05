# GoTimer – grandMA3 Plugin (0.3.0)

Misst im Theaterbetrieb die Zeit zwischen zwei Go+ und schreibt sie in die
Note der Cue, die durch das Go+ ausgelöst wurde:

```
[GT 0:41 (0:38-0:45) L0:42 n4] Stichwort: "...und dann ging das Licht aus"
     │    │          │      │
     │    │          │      └ Anzahl gewerteter Durchläufe
     │    │          └ letzter Durchlauf
     │    └ Range (min–max)
     └ Mittelwert
```

Steht man in Cue 11, zeigt die Note von **Cue 12** (= Next), wie lange nach dem
Go in Cue 11 üblicherweise das nächste Go kommt. Eigener Note-Text bleibt erhalten,
nur der `[GT …]`-Block wird ersetzt.

## Installation (onPC macOS / Konsole)

1. `GoTimer.xml` + `GoTimer.lua` kopieren nach
   `~/MALightingTechnology/gma3_library/datapools/plugins/`
   (Konsole: USB-Stick unter `gma3_library/datapools/plugins/`).
2. Plugin-Pool → leeres Feld editieren → **Import** → `GoTimer`.
3. Makro anlegen, z.B. Makro „GO+ Timed“ mit einer Zeile:
   ```
   Plugin "GoTimer"
   ```
   und das Makro auf einen Executor-Button oder X-Key legen.
   **Dieser Button ersetzt in Proben den normalen Go+.**

## Argumente

| Befehl | Wirkung |
|---|---|
| `Plugin "GoTimer"` / `"go"` | Go+ auf der **selektierten Sequenz** + Messung |
| `Plugin "GoTimer" "go 5"` | Go+ auf Sequenz 5 + Messung |
| `Plugin "GoTimer" "break"` | Referenz verwerfen (Unterbrechung) – nächstes Go wird nicht gewertet |
| `Plugin "GoTimer" "rec"` / `"rec on"` / `"rec off"` | Aufnahme umschalten. Bei AUS macht der Button nur Go+ (für die Vorstellung) |
| `Plugin "GoTimer" "reset"` / `"reset 5"` | Messwerte + `[GT …]`-Marker der Sequenz löschen |
| `Plugin "GoTimer" "timer 1"` / `"timer off"` | Live-Timer: Timer 1 aus dem Timer-Pool wird bei jedem Go gesteuert |
| `Plugin "GoTimer" "tmode auto"` | `auto` (Countdown wenn Daten da, sonst Stopwatch) · `countdown` · `stopwatch` |
| `Plugin "GoTimer" "gui"` | Einstellungs-Dialog öffnen (siehe unten) |

## GUI (seit 0.3.0)

Zweites Makro anlegen, z.B. „GoTimer Setup“ mit der Zeile `Plugin "GoTimer" "gui"`.
**Nicht** einfach das Plugin im Pool antippen: ohne Argument macht es ein Go+.

Der Dialog zeigt oben die selektierte Sequenz, wie viele Cues schon Messwerte haben,
die aktuelle Cue und die nächste Go-Cue mit ihrem Mittelwert.

| Element | Wirkung |
|---|---|
| Schalter **Aufnahme** | wie `rec on/off` |
| Schalter **Popup bei 0:00** | AUS: Plugin setzt den Countdown-Alert auf `None` |
| **Timer-Nr (0 = aus)** | Timer aus dem Pool für die Live-Anzeige |
| **Pause ab (Minuten)** | Abstände darüber werden nicht gewertet (Standard 15) |
| **Timer-Modus** | Auto · Countdown · Stopwatch |
| Button **OK** | übernehmen und schließen |
| Button **Statistik** | Liste aller Cues mit Messwerten (avg, Range, letzt, n), max. 30 Zeilen |
| Button **Break** | Referenz verwerfen und Timer stoppen |
| Button **Reset Sequenz** | mit Rückfrage alle Messwerte der Sequenz löschen |
| Button **Abbrechen** | schließen, ohne zu übernehmen |

Statistik, Break und Reset übernehmen die Einstellungen ebenfalls und öffnen den Dialog danach wieder.

## Live-Timer (seit 0.2.0)

Nutzt den eingebauten **Timer-Pool** und das **Clock-Fenster**: kein eigenes UI nötig.

Einrichtung:
1. Timer 1 im Timer-Pool anlegen, **Restart Option = Reset**
   (Countdown-Alert wird vom Plugin auf None gesetzt, siehe `CFG.TIMER_ALERT`).
2. Clock-Fenster öffnen → Clock Source = **Timer** → Timer 1 wählen.
3. Einmalig: `Plugin "GoTimer" "timer 1"` (Einstellung bleibt in den UserVars).

Bei jedem Go über das Plugin:
- Timer wird gestoppt, auf Countdown (Dauer = Mittelwert der nächsten Go-Cue) bzw. Stopwatch
  gesetzt, **umbenannt** in z.B. `Cue 12 ~0:41 (0:38-0:45)` und neu gestartet.
- Follow-/Time-Cues werden übersprungen, um die nächste manuelle Go-Cue zu finden.
- Läuft auch bei `rec off`, also in der Vorstellung.
- `break` und das Ausschalten der Sequenz stoppen den Timer.

**Countdown oder Stopwatch?** Ein Countdown bleibt bei 0:00 stehen, man sieht also nicht, wie weit
man drüber ist. Die Stopwatch zählt weiter, der Sollwert steht dann im Timer-Namen.

## Regeln, wann **nicht** gewertet wird

- erstes Go nach Plugin-Reload oder bei ausgeschalteter Sequenz (nur Startpunkt)
- Abstand > 15 min (Pause) oder < 0,3 s (Doppel-Tipp)
- seit dem letzten Go wurde zurückgesprungen (Goto/Go−); Vorwärts durch Follows ist ok
- Go+ auf der letzten Cue (Wrap/Ende)

Grenzen in `CFG` oben in `GoTimer.lua` anpassbar.

## Datenhaltung

- **UserVars** `GT_S<seq>_C<cueNo>` = `n;sum;min;max;last` (volle Genauigkeit), `GT_REC` = 0/1
- **Fallback**: fehlt die UserVar (anderer User-Profil, neue Show-Kopie), werden die Werte
  aus dem `[GT …]`-Block der Note rekonstruiert (auf Sekunden gerundet) und weitergeführt.

## Teststatus (grandMA3 2.3.2.0)

| Funktion | Stand |
|---|---|
| Go+ über das Plugin, Messung, Schreiben in die Note | auf MA3 getestet |
| Live-Timer mit Countdown | auf MA3 getestet |
| Kein Popup bei 0:00 (`CountdownAlertType` = `None`) | noch nicht auf MA3 bestätigt |
| Überspringen von Follow-/Time-Cues | nur mit nachgebauter API getestet, Property-Name des Triggers nicht verifiziert |
| GUI (`"gui"`) | nur mit nachgebauter API getestet |

## Bekannte Einschränkungen

- Gemessen wird nur, was über dieses Plugin ausgelöst wird. Der normale Go+-Button am Pult zählt nicht.
- Der Laufzeit-Zustand (letztes Go) liegt im Plugin-Speicher; nach Reload/Neustart
  ist das erste Go wieder nur Startpunkt.

## Lizenz

[MIT](LICENSE)
