#!/bin/sh
# Respaldo de la base de datos de Emily Natación (Supabase) a archivos JSON locales.
# Usa la sesión de la CLI de Supabase (supabase login); no guarda contraseñas.
# Destino: ~/Respaldos/emily-natacion/AAAA-MM-DD/ (fuera del repositorio, que es público). Conserva los 12 más recientes.
# Las contraseñas de los usuarios no se respaldan: Supabase Auth las guarda cifradas.
set -eu

PROJECT=zdrtfhnppwvoxnphfnkg
SUPABASE=${SUPABASE_BIN:-/opt/homebrew/bin/supabase}
BASE="$HOME/Respaldos/emily-natacion"
DEST="$BASE/$(date +%Y-%m-%d)"

umask 077
mkdir -p "$DEST"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"  # la CLI crea archivos temporales donde se ejecuta

for table in profiles students bookings payments class_types schedule plans; do
  "$SUPABASE" db query --linked --project-ref "$PROJECT" --output-format json \
    "select coalesce(json_agg(t), '[]'::json) as filas from public.$table t" > "$WORK/$table.raw" 2>/dev/null
  # Se guarda solo el arreglo de filas.
  python3 -c '
import json, sys
raw = json.load(open(sys.argv[1]))
rows = raw["rows"] if isinstance(raw, dict) else raw  # la CLI solo envuelve el resultado cuando la ejecuta un agente
filas = rows[0]["filas"]
json.dump(filas, open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
print(sys.argv[2], len(filas), "filas")
' "$WORK/$table.raw" "$DEST/$table.json"
done

# Conserva solo los 12 respaldos más recientes.
total=$(ls -1d "$BASE"/20??-??-?? 2>/dev/null | wc -l)
ls -1d "$BASE"/20??-??-?? 2>/dev/null | sort | awk -v n="$total" 'NR <= n - 12' | while read -r old; do rm -rf "$old"; done
echo "Respaldo listo en $DEST"
