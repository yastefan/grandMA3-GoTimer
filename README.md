# GoTimer – grandMA3 Plugin (0.5.0)

Misst im Theaterbetrieb die Zeit zwischen zwei Go+ und schreibt sie in die
Note der Cue, die durch das Go+ ausgelöst wurde:

```
[GT 0:41 (0:38-0:45) L0:42 n4] Stichwort: "...und dann ging das Licht aus" {42 38 45 41}
     │    │          │      │                                                │
     │    │          │      └ Anzahl Durchläufe                              └ Rohdaten in vollen Sekunden
     │    │          └ letzter Durchlauf                                       (neuester zuletzt)
     │    └ Range (min–max)
     └ Mittelwert
```

Steht man in Cue 11, zeigt die Note von **Cue 12** (= Next), wie lange nach dem
Go in Cue 11 üblicherweise das nächste Go kommt. Eigener Note-Text bleibt erhalten,
nur der `[GT …]`-Block und die Rohdaten am Ende werden ersetzt.

## Installation (onPC macOS / Konsole)

1. `GoTimer.xml` + `GoTimer.lua` kopieren nach
   `~/MALightingTechnology/gma3_library/datapools/plugins/`
   (Konsole: USB-Stick unter `gma3_library/datapools/plugins/`).
2. Plugin-Pool → leeres Feld editieren → **Import** → `GoTimer`.
3. Plugin im Pool antippen: die Live-Anzeige öffnet sich. Dort **Config** → **Go-Makro** wählen.
   Das legt im ersten freien Macro-Platz das Makro „GoTimer Go“ an, von Hand wäre es diese Zeile:
   ```
   Plugin "GoTimer" "go"
   ```
4. Das Makro auf einen Executor-Button oder X-Key legen.
   **Dieser Button ersetzt in Proben den normalen Go+.**

> **Update von 0.3.0:** Ohne Argument löst das Plugin kein Go mehr aus, sondern schaltet die Anzeige um.
> Ein altes Makro mit `Plugin "GoTimer"` muss auf `"go"` geändert werden.

## Argumente

| Befehl | Wirkung |
|---|---|
| `Plugin "GoTimer"` | Live-Anzeige an/aus, auch beim Antippen im Plugin-Pool |
| `Plugin "GoTimer" "go"` | Go+ auf der **selektierten Sequenz** + Messung |
| `Plugin "GoTimer" "go 5"` | Go+ auf Sequenz 5 + Messung |
| `Plugin "GoTimer" "break"` | Referenz verwerfen (Unterbrechung) – nächstes Go wird nicht gewertet |
| `Plugin "GoTimer" "rec"` / `"rec on"` / `"rec off"` | Aufnahme umschalten. Bei AUS macht der Button nur Go+ (für die Vorstellung) |
| `Plugin "GoTimer" "reset"` / `"reset 5"` | Messwerte + `[GT …]`-Marker der Sequenz löschen |
| `Plugin "GoTimer" "timer 1"` / `"timer on"` / `"timer off"` | Timer aus dem Timer-Pool bei jedem Go steuern. Standard: aus |
| `Plugin "GoTimer" "tmode auto"` | `auto` (Countdown wenn Daten da, sonst Stopwatch) · `countdown` · `stopwatch` |
| `Plugin "GoTimer" "gui"` | Einstellungs-Dialog öffnen (siehe unten) |
| `Plugin "GoTimer" "diag"` | Fehlersuche: zeigt den Status und testet das Schreiben an der nächsten Cue, stellt deren Note danach wieder her |
| `Plugin "GoTimer" "display"` / `"display on"` / `"display off"` | Live-Anzeige umschalten (siehe unten) |

## GUI (seit 0.3.0)

Plugin im Pool antippen und in der Live-Anzeige auf **Config** tippen.
Alternativ geht `Plugin "GoTimer" "gui"`, zum Beispiel als eigenes Makro.

Der Dialog zeigt oben die selektierte Sequenz, wie viele Cues schon Messwerte haben,
die aktuelle Cue und die nächste Go-Cue mit ihrem Mittelwert.

| Element | Wirkung |
|---|---|
| Schalter **Aufnahme** | wie `rec on/off` |
| Schalter **Timer** | Timer aus dem Pool mitsteuern. Standard: aus |
| Schalter **Popup bei 0:00** | AUS: Plugin setzt den Countdown-Alert auf `None` |
| **Timer-Nr** | welcher Timer aus dem Pool gesteuert wird |
| **Pause ab (Minuten)** | Abstände darüber werden nicht gewertet (Standard 15) |
| **Timer-Modus** | Auto · Countdown · Stopwatch |
| **Zeit in Anzeige** | Vergleichszeit oben in der Live-Anzeige: Durchschnitt oder letzter Durchlauf |
| Button **OK** | übernehmen und schließen |
| Button **Go-Makro** | legt das Makro „GoTimer Go“ im ersten freien Platz an. Ein vorhandenes wird nicht verändert |
| Button **Break** | Referenz verwerfen und Timer stoppen |
| Button **Reset Sequenz** | mit Rückfrage alle Messwerte der Sequenz löschen |
| Button **Abbrechen** | schließen, ohne zu übernehmen |

Go-Makro, Break und Reset übernehmen die Einstellungen ebenfalls und öffnen den Dialog danach wieder.

## Live-Anzeige (seit 0.4.0)

Eigenes, verschiebbares Fenster auf dem Display, das gerade den Fokus hat. Antippen des Plugins
im Pool schaltet es an und aus, alternativ `Plugin "GoTimer" "display"`.

```
0:53 / ~0:41  (+0:12)
Next: Cue 12  (0:38-0:45)
```

- **Oben:** Zeit seit dem letzten Go über das Plugin, Vergleichszeit der nächsten Go-Cue, Überziehung.
  Die Vergleichszeit ist der Durchschnitt (`~0:41`) oder der letzte Durchlauf (`L0:42`), einstellbar im Menü.
  Der Countdown des Pool-Timers nutzt immer den Durchschnitt.
- **Unten:** nächste Go-Cue und ihre gemessene Range.
- **Farbe:** normal, dann `DISPLAY_COLOR_WINDOW` innerhalb der Range, `DISPLAY_COLOR_OVER` über dem
  bisherigen Maximum. Farbnamen stehen in `CFG` (Name aus `Global` oder `Gruppe.Name`), die Liste am Pult zeigt
  `List Root().ColorTheme.ColorGroups.Global.*`.
- Die Anzeige läuft bis zum Schließen, auch bei `rec off`, und schreibt nichts in die Show.
- Schließen geht über das X im Fenster oder `display off`. `Esc` schließt sie bewusst nicht.
- Der Button **Config** in der Titelleiste öffnet das Einstellungs-Menü (siehe GUI).
  Solange das Menü offen ist, ist der Go-Button blockiert.
- Das Fenster öffnet nach jedem Start wieder an der Standardposition.

## Live-Timer (seit 0.2.0)

Nutzt den eingebauten **Timer-Pool** und das **Clock-Fenster**: kein eigenes UI nötig.

Einrichtung:
1. Timer 1 im Timer-Pool anlegen, **Restart Option = Reset**
   (Countdown-Alert wird vom Plugin auf None gesetzt, siehe `CFG.TIMER_ALERT`).
2. Clock-Fenster öffnen → Clock Source = **Timer** → Timer 1 wählen.
3. Im Menü den Schalter **Timer** einschalten und die Timer-Nr eintragen, oder einmalig
   `Plugin "GoTimer" "timer 1"` (Einstellung bleibt in den UserVars).

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

- **Messwerte** liegen seit 0.5.0 nur noch in der Note jeder Cue: die letzten 10 Durchläufe in vollen
  Sekunden am Ende der Note. Beim elften fällt der älteste heraus, alle Werte im `[GT …]`-Block beziehen
  sich auf die gespeicherten Durchläufe. Dadurch wandern sie beim Kopieren und Umnummerieren mit der Cue
  mit und hängen nicht am User-Profil. Der `{…}`-Block sollte nicht von Hand geändert werden.
- **Einstellungen** liegen weiter in UserVars (`GT_REC`, `GT_TIMER`, `GT_TMODE` usw.).
- **Update von 0.4.0:** Notes ohne Rohdaten werden weiter angezeigt. Beim nächsten Durchlauf wird aus dem
  `[GT …]`-Block eine Startliste mit gleichem Mittelwert und gleicher Range erzeugt. Das sind keine echten
  Einzelzeiten, sie rutschen mit neuen Durchläufen heraus. Sofort saubere Werte gibt es mit `reset`.
  Alte UserVars `GT_S…` werden dabei aufgeräumt.

## Teststatus (grandMA3 2.3.2.0)

| Funktion | Stand |
|---|---|
| Go+ über das Plugin, Messung, Schreiben in die Note | auf MA3 getestet |
| Live-Timer mit Countdown | auf MA3 getestet |
| Kein Popup bei 0:00 (`CountdownAlertType` = `None`) | noch nicht auf MA3 bestätigt |
| Überspringen von Follow-/Time-Cues | nur mit nachgebauter API getestet, Property-Name des Triggers nicht verifiziert |
| GUI (`"gui"`) | auf MA3 getestet |
| Schalter **Timer**, **Zeit in Anzeige** im Menü | noch nicht auf MA3 bestätigt |
| Antippen im Pool schaltet die Anzeige, Button **Go-Makro** | auf MA3 getestet |
| Fenstertyp der Live-Anzeige (Stabilität, Verschieben, Farbwechsel) | als Testvariante in onPC geprüft |
| Live-Anzeige in GoTimer, Go und Bedienung bei offener Anzeige | auf MA3 getestet |
| Farben der Anzeige, `Esc` schließt nicht, X schließt | auf MA3 getestet |
| Button **Config** in der Anzeige | auf MA3 getestet |
| Dauerbetrieb über 30 min | noch nicht auf MA3 bestätigt |
| Rohdaten in der Cue-Note, Übernahme alter Werte, Kopieren, Reset, Speichern und Laden | auf MA3 getestet |

## Bekannte Einschränkungen

- Gemessen wird nur, was über dieses Plugin ausgelöst wird. Der normale Go+-Button am Pult zählt nicht.
- Der Laufzeit-Zustand (letztes Go) liegt im Plugin-Speicher; nach Reload/Neustart
  ist das erste Go wieder nur Startpunkt.

## Lizenz

[MIT](LICENSE)
