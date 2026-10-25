#!/bin/sh
# Prueft das abgeleitete Abbild gegen das offizielle Coolify Abbild.
# Aufruf: sh test.sh <offizielles abbild> <abgeleitetes abbild>
set -eu

ORIG=${1:?offizielles Abbild fehlt}
NEU=${2:?abgeleitetes Abbild fehlt}
fehler=0

ok() { echo "ok: $*"; }
nok() { echo "FEHLER: $*"; fehler=1; }

# 1. Laufzeitkonfiguration unveraendert (Entrypoint, Cmd, Nutzer, Arbeitsverzeichnis,
#    Umgebung, Ports, Healthcheck, Stoppsignal, Volumes).
fmt='{{json .Config.Entrypoint}}|{{json .Config.Cmd}}|{{.Config.User}}|{{.Config.WorkingDir}}|{{json .Config.Env}}|{{json .Config.ExposedPorts}}|{{json .Config.Healthcheck}}|{{.Config.StopSignal}}|{{json .Config.Volumes}}'
a=$(docker image inspect -f "$fmt" "$ORIG")
b=$(docker image inspect -f "$fmt" "$NEU")
if [ "$a" = "$b" ]; then ok "Entrypoint, Cmd, Nutzer, Umgebung gleich"; else nok "Laufzeitkonfiguration weicht ab"; echo "  $a"; echo "  $b"; fi

# 2. Nur die zwei Binaries kommen als Schichten dazu.
la=$(docker image inspect -f '{{len .RootFS.Layers}}' "$ORIG")
lb=$(docker image inspect -f '{{len .RootFS.Layers}}' "$NEU")
if [ "$lb" -eq $((la + 2)) ]; then ok "genau 2 neue Schichten"; else nok "Schichten $la -> $lb, erwartet $((la + 2))"; fi
basis=$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$ORIG")
case "$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$NEU")" in
  "$basis"*) ok "Basisschichten unveraendert" ;;
  *) nok "Basisschichten weichen ab" ;;
esac

# 3. Pfade, Eigentuemer und Rechte wie im Original.
rechte='stat -c "%n %a %u %g" /usr/bin/mc /usr/local/bin/cloudflared'
a=$(docker run --rm --entrypoint sh "$ORIG" -c "$rechte")
b=$(docker run --rm --entrypoint sh "$NEU" -c "$rechte")
if [ "$a" = "$b" ]; then ok "Rechte gleich: $(echo "$b" | tr '\n' ';')"; else nok "Rechte weichen ab: $a / $b"; fi

# 4. Binaries laufen als Standardnutzer des Abbilds und stammen aus dem eigenen Bau.
if out=$(docker run --rm --entrypoint mc "$NEU" --version); then
  echo "$out" | sed 's/^/  /'
  echo "$out" | grep -q 'Runtime: go1\.' || nok "mc meldet keine Go Version"
  ok "mc --version"
else
  nok "mc --version"
fi
if out=$(docker run --rm --entrypoint cloudflared "$NEU" --version); then
  echo "  $out"
  ok "cloudflared --version"
else
  nok "cloudflared --version"
fi
a=$(docker run --rm --entrypoint sh "$ORIG" -c 'sha256sum /usr/bin/mc /usr/local/bin/cloudflared' | cut -d' ' -f1)
b=$(docker run --rm --entrypoint sh "$NEU" -c 'sha256sum /usr/bin/mc /usr/local/bin/cloudflared' | cut -d' ' -f1)
if [ "$(echo "$a" | sed -n 1p)" != "$(echo "$b" | sed -n 1p)" ] && [ "$(echo "$a" | sed -n 2p)" != "$(echo "$b" | sed -n 2p)" ]; then
  ok "beide Binaries ersetzt"
else
  nok "Binary nicht ersetzt"
fi

# 5. mc kann, was Coolify bei S3 Sicherungen aufruft: globales --resolve,
#    alias set, cp, stat --json, pipe --checksum.
hilfe=$(docker run --rm --entrypoint sh "$NEU" -c 'mc --help; mc pipe --help; mc stat --help; mc cp --help' 2>&1)
for flag in --resolve --checksum --json; do
  if echo "$hilfe" | grep -q -- "$flag"; then ok "mc kennt $flag"; else nok "mc kennt $flag nicht"; fi
done
if docker run --rm --entrypoint sh "$NEU" -c 'mc --resolve example.invalid:443=127.0.0.1 alias set probe https://example.invalid zugang geheimnis --api S3v4 >/dev/null 2>&1; mc alias list probe >/dev/null'; then
  ok "mc alias set mit --resolve"
else
  nok "mc alias set mit --resolve"
fi

# 6. cloudflared Unterbefehl, den Coolify als SSH ProxyCommand nutzt.
if docker run --rm --entrypoint cloudflared "$NEU" access ssh --help 2>&1 | grep -q -- '--hostname'; then ok "cloudflared access ssh --hostname"; else nok "cloudflared access ssh --hostname"; fi

if [ "$fehler" -ne 0 ]; then
  echo "Pruefung fehlgeschlagen"
  exit 1
fi
echo "Pruefung bestanden"
