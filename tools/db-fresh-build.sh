#!/bin/bash
# يبني قاعدة مستر زاهي من الصفر من المستودع وحده: يطبق ملفات supabase/migrations بترتيب APPLIED_ORDER.txt،
# كل ملف مرة واحدة عند اول ظهور له، ويتوقف عند اول خطا. الاستعمال: tools/db-fresh-build.sh "<psql connection or -U user -d db>"
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/supabase/migrations"
PSQL="${1:?psql args}"
declare -A done=()
n=0
while IFS=$'\t' read -r version name file status; do
  [[ "$version" =~ ^# ]] && continue; [ -n "${file:-}" ] || continue
  [ -n "${done[$file]:-}" ] && continue; done[$file]=1
  n=$((n+1)); printf '%3d %s (%s %s)\n' "$n" "$file" "$version" "$status"
  psql $PSQL -v ON_ERROR_STOP=1 -q -f "$DIR/$file"
done < "$DIR/APPLIED_ORDER.txt"
echo "applied $n files"
