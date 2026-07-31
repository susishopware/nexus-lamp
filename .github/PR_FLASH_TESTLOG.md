# PR-Flash Testlog

Regelmäßige Funktionschecks der Lampen-Automatisierung. Seit 2026-07-31 werden
die PR-Events nicht mehr von einer GitHub-Action pro Repo publisht, sondern von
einem n8n-Workflow: GitHub-Trigger (Event `pull_request`, ein Node pro
beobachtetem Repo) → Filter (`action` ∈ opened/reopened/synchronize/closed) →
Mapping → MQTT-Publish auf `nexus/v1/pr/<repo>` (QoS 1, kein Retain). Die
beobachteten Repositories brauchen damit weder Workflow-Dateien noch Secrets.

Erwartetes Verhalten der Lampen im Feld:

- PR geöffnet / aktualisiert → Shopware-Blau, 2× blinken
- PR gemerged → Violett, 3× blinken
- PR geschlossen ohne Merge → Grau, 2× blinken

| Datum | Anlass | Ergebnis |
|---|---|---|
| 2026-07-31 | Routinecheck: Action + Lampen nach Firmware-Release (PR #1) | OK — Publish-Secrets (`MQTT_HOST`/`MQTT_USER`/`MQTT_PASS`) fehlten und wurden nachgetragen; danach `opened` bestätigt: 2× blau |
| 2026-07-31 | Umstellung auf n8n, Ende-zu-Ende-Test (nexus-workflow-builder#1096) | OK — opened/synchronize → blau, issue_comment → keine Reaktion (Filter), closed → grau; `pr-flash.yml` daraufhin entfernt |
