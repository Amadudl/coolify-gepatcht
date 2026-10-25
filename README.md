# coolify-gepatcht

Offizielles Abbild `coollabsio/coolify:<version>` mit neu gebautem MinIO Client (`/usr/bin/mc`) und `cloudflared` (`/usr/local/bin/cloudflared`). Veröffentlicht als `ghcr.io/amadudl/coolify-gepatcht`.

## Warum

Trivy 0.76.1 meldet im offiziellen Abbild `coollabsio/coolify:4.5.0` 8 HIGH Befunde, alle in zwei mitgelieferten Go Programmen:

| Datei | Herkunft im Original | Befunde |
| --- | --- | --- |
| `/usr/bin/mc` | `quay.io/minio/aistor/mc:RELEASE.2026-09-06T02-44-40Z`, Go 1.26.6 | 7: Go Standardbibliothek, `golang.org/x/net` 0.58.0, `google.golang.org/grpc` 1.82.1 |
| `/usr/local/bin/cloudflared` | GitHub Release 2026.10.3 | 1: `github.com/klauspost/compress` 1.18.0 |

Weder Coolify noch MinIO (auch nicht das neuere AIStor `mc` vom 19.09.2026, dort noch 5 HIGH) noch Cloudflare liefern bisher Binaries mit den Korrekturen.

Dieses Abbild baut beide Programme aus der Quelle mit Go 1.27.3 und hebt die betroffenen Module an:

- `mc` aus `github.com/minio/mc`, Tag `RELEASE.2025-08-13T08-35-41Z` (letztes Release, Repo archiviert): `golang.org/x/net` 0.60.0, `google.golang.org/grpc` 1.83.2, `github.com/klauspost/compress` 1.18.7, `github.com/prometheus/prometheus` 0.311.3.
- `cloudflared` aus `github.com/cloudflare/cloudflared`, gleicher Tag wie im Basisabbild (bei 4.5.0: 2026.10.3), Bau per `make cloudflared` wie upstream: `github.com/klauspost/compress` 1.18.7.

Beide statisch (`CGO_ENABLED=0`), an dieselben Pfade, Eigentümer root, Rechte 755 wie im Original. Alles andere bleibt das offizielle Abbild: Basisschichten, Entrypoint, Cmd, Nutzer, Umgebung. Module werden nur angehoben, nie zurückgesetzt (`scripts/raise-modules.sh`).

Ergebnis für 4.5.0: 8 HIGH vorher, 0 HIGH oder CRITICAL (behebbar) nachher im ganzen Abbild.

## Tags

| Tag | Bedeutung |
| --- | --- |
| `4.5.0` usw. | Gleiche Version wie `coollabsio/coolify:<version>`. |
| `latest` | Neueste Coolify Version. |

Coolifys `upgrade.sh` zieht beim Update jedes Abbild aus `docker-compose.custom.yml` und bricht ab, wenn ein Tag fehlt. Deshalb sucht die Pipeline stündlich nach einer neuen Coolify Version und baut das Tag, sobald das offizielle Abbild auf Docker Hub liegt. Zwischen Coolify Release und eigenem Tag liegt also bis zu etwa eine Stunde plus Bauzeit; in dieser Zeit kein Coolify Update starten.

## Bau und Prüfung

Die Pipeline `.github/workflows/build.yml` läuft stündlich, bei jedem Push auf `main` und von Hand.

1. Neueste Coolify Version aus den GitHub Releases (ohne Vorabversionen) plus die gepinnte laufende Version (`PINNED`).
2. Stündlich nur fehlende Tags bauen; Push und Handstart bauen alle Zielversionen neu.
3. Digest von `coollabsio/coolify:<version>` als Basis pinnen, `cloudflared` Version aus dem Basisabbild lesen.
4. Bauen.
5. `test.sh`: Entrypoint, Cmd, Nutzer, Umgebung gleich; Basisschichten unverändert, genau 2 neue Schichten; Pfade und Rechte gleich; `mc --version` und `cloudflared --version` laufen als Standardnutzer; beide Binaries ersetzt; `mc` kennt `--resolve`, `pipe --checksum`, `stat --json` (Aufrufe aus Coolifys S3 Sicherung); `cloudflared access ssh --hostname` (SSH ProxyCommand).
6. Trivy 0.76.1 (wie der CVE Watch auf newserver): Abbruch bei behebbaren HIGH oder CRITICAL Befunden.
7. Nur auf `main`: Push von `<version>` und, für die neueste Version, `latest`.

Lokal:

```sh
docker build --build-arg BASE=coollabsio/coolify:4.5.0 -t coolify-test .
sh test.sh coollabsio/coolify:4.5.0 coolify-test
trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed coolify-test
```

## Einsatz auf newserver

`/data/coolify/source/docker-compose.custom.yml`:

```yaml
services:
  coolify:
    image: "ghcr.io/amadudl/coolify-gepatcht:${LATEST_IMAGE:-latest}"
```

Danach Coolify über `upgrade.sh` neu starten. Vorher prüfen, dass das Tag der laufenden Version in GHCR liegt.

## Rückweg

1. `docker-compose.custom.yml` verschieben (etwa nach `/root/coolify-backups/`), oder nur den Eintrag für `coolify` entfernen, falls die Datei weitere Dienste überschreibt.
2. `bash /data/coolify/source/upgrade.sh <laufende version> <helper version>` starten (zweites Argument: Tag von `coollabsio/coolify-helper`, den die Installation nutzt, siehe `docker images coollabsio/coolify-helper`). Coolify läuft dann wieder mit `coollabsio/coolify:<version>`.

Daten liegen in Datenbank und Volumes, nicht im Abbild; der Wechsel ändert sie nicht.

## Fallstricke

- `mc` stammt aus dem quelloffenen MinIO Client (AGPLv3, letztes Release 13.08.2025) statt aus dem AIStor Client, den Coolify mitliefert. Die von Coolify genutzten Befehle und Schalter sind vorhanden (`test.sh`). Neue Funktionen des AIStor Clients fehlen.
- Nur `linux/amd64` (wie newserver).
- Go Version und Modulversionen sind im `Dockerfile` gepinnt. Meldet Trivy neue Befunde, dort anheben; die Pipeline bricht bis dahin ab und veröffentlicht nichts.
- GitHub schaltet geplante Läufe in öffentlichen Repos nach 60 Tagen ohne Aktivität ab. Dann fehlen neue Tags und `upgrade.sh` bricht ab, bis der Lauf wieder aktiviert oder von Hand gestartet wird.
- Wechselt Coolify in einer neuen Version den `cloudflared` Tag, baut die Pipeline diesen Tag; fehlt das Modul oder bricht der Bau, gibt es für diese Version kein Tag.
