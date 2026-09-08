# Datenschutz und Datensicherheit

> **Alle Daten in diesem Projekt sind synthetisch.** Der Generator
> ([r/datagen](../r/datagen/generate.R)) erzeugt fiktive Schulen, fiktive
> Schüler:innen und fiktive Antworten aus einem festen Zufalls-Seed. Es
> werden zu keinem Zeitpunkt Personendaten verarbeitet. Dieses Dokument
> beschreibt, wie die Architektur mit *echten* Assessment-Daten umgehen
> würde — denn Datenschutz muss in der Architektur stecken, nicht in der
> Absichtserklärung.

## Datenschutz durch Technikgestaltung (Privacy by Design)

**Pseudonymisierung.** Die Identifikatoren (`STU00001`, `SCH0001`) tragen
keine Semantik. In einem echten Erhebungskontext würden Pseudonyme durch
eine getrennte Stelle vergeben und die Zuordnungstabelle niemals dieses
System erreichen; das Schema enthält bewusst keine Felder für Namen,
Geburtsdaten oder Adressen.

**Trennung der Zugriffspfade.** Drei Datenbankrollen mit strikt
verschiedenen Rechten (Details in [security.md](security.md)): die
öffentliche API kann Einzeldaten nicht einmal lesen — das erzwingt die
Datenbank, nicht die Anwendungslogik. Analysen laufen unter einer eigenen
Rolle mit Lesezugriff auf pseudonymisierte Einzeldaten, aber ohne
Schreibrechte.

**Nur Aggregate verlassen das System.** Die API liefert ausschliesslich
gewichtete Kennwerte pro Kanton bzw. Sprachregion. Ein Test schlägt fehl,
wenn ein Endpunkt je ein Feld auf Einzeldatenebene liefern würde
([test_api.py](../python/tests/test_api.py)).

**Kleinzellen-Unterdrückung.** Zellen mit weniger als 10 teilnehmenden
Schüler:innen werden nicht publiziert. Die Regel ist dreifach implementiert
— in den SQL-Views, im R-Paket und als Guard in der API — und auf jeder
Ebene durch Tests abgesichert, die fehlschlagen, sobald eine zu kleine
Zelle publiziert würde. Der Schwellwert 10 ist als gängige Untergrenze der
amtlichen Statistik gewählt und zentral konfigurierbar (`LSA_MIN_CELL_SIZE`).

**Audit-Log.** Jede Datenabfrage über die API wird mit Request-ID,
Endpunkt und Parametern protokolliert ([0004](../db/migrations/0004_audit.sql)).
Die API-Rolle kann das Log nur beschreiben, nicht lesen oder ändern.

## Aufbewahrung und Löschung (dokumentierte Policy)

| Datenart | Aufbewahrung | Begründung |
| -------- | ------------ | ---------- |
| Roh-CSV-Lieferungen | bis zum erfolgreichen, geprüften Import, danach Löschung | nur Transportform; die Datenbank ist die Quelle der Wahrheit |
| Einzeldaten in der Datenbank | Dauer des Erhebungszyklus plus dokumentierte Analysefrist | Nachberechnungen und Qualitätssicherung |
| Aggregierte Ergebnisse | unbefristet | enthalten keine Personendaten mehr |
| Backups | rollierend, gleiche Frist wie Einzeldaten | ein Backup ist eine Kopie der Daten und erbt deren Schutzbedarf |
| Audit-Log | getrennte, längere Frist | Nachvollziehbarkeit von Zugriffen |

Im Demo-Betrieb ist all das gegenstandslos (synthetische Daten, `make
kind-down` löscht alles); die Tabelle zeigt, welche Entscheidungen ein
echter Betrieb dokumentieren müsste.

## Einordnung: DSG und DSGVO

*Ohne Anspruch auf Rechtsberatung — ich bin kein Jurist. Die folgende
Zuordnung zeigt, welche Pflichten die Architektur adressiert.*

Echte Leistungsdaten von Schüler:innen wären Personendaten im Sinne des
Schweizer DSG; je nach Kontext können sie als besonders schützenswert
gelten. Relevante Grundsätze und ihre technische Entsprechung hier:

- **Verhältnismässigkeit / Datenminimierung** (DSG Art. 6; DSGVO Art. 5):
  das Schema erhebt nur die für die Auswertung nötigen Merkmale; die
  öffentliche Schnittstelle gibt nur Aggregate heraus.
- **Datenschutz durch Technik und datenschutzfreundliche Voreinstellungen**
  (DSG Art. 7; DSGVO Art. 25): Suppression, Rollentrennung und
  Pseudonymisierung sind Code und Datenbankregeln, keine Prozessanweisung.
- **Datensicherheit / technische und organisatorische Massnahmen**
  (DSG Art. 8; DSGVO Art. 32): Least-Privilege-Rollen, verschlüsselter
  Transport bis zum TLS-Terminierungspunkt ([network.md](network.md)),
  gehärtete Container, Secret-Handhabung und Scanning — siehe
  [security.md](security.md).
- **Nachvollziehbarkeit**: das Audit-Log dokumentiert, wer was abgefragt
  hat.

Was dieses Projekt bewusst *nicht* abbildet: Rechtsgrundlagen der
Erhebung, Informationspflichten, Auskunftsrechte, Auftragsverhältnisse und
die organisatorische Seite der TOMs — das sind Prozess- und Rechtsfragen,
keine Architekturfragen, und sie gehören in einem echten Projekt zu den
ersten Klärungen.
