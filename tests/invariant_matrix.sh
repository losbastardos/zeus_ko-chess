#!/bin/bash
# ============================================================
# Invariant-clean matica — kontrola piece-list po make/unmake
# ============================================================
# Vstup: engine (default ./chess-static)
# Pozi:  pre kazdych 6 FEN z invariant_fens.env:
#        - 1x make (cez search depth 1)
#        - 1x unmake
#        - pl_verify_or_die bezi v make_move aj unmake_move (ENABLE_PL_INVARIANT=1)
#        - pri prvom zlyhani: exit 1 s vypisom FEN+index
# ============================================================

set -euo pipefail

cd "$(dirname "$0")/.."

ENGINE="${1:-./chess-static}"
FENS_FILE="${2:-tests/invariant_fens.env}"

if [[ ! -x "$ENGINE" ]]; then
    echo "ERROR: Engine not executable: $ENGINE" >&2
    exit 2
fi

if [[ ! -f "$FENS_FILE" ]]; then
    echo "ERROR: FEN file not found: $FENS_FILE" >&2
    exit 2
fi

idx=0
failed=0

while read -r line; do
    # ignora komentare a prazdne riadky
    [[ -z "$line" || "$line" == \#* ]] && continue

    # format: <index> <popis> <FEN>
    f=$(echo "$line" | awk '{print $3}')
    [[ -z "$f" ]] && continue

    fens="$fens $f"
    fens_count=$((fens_count + 1))
    ((idx++)) || true
done < "$FENS_FILE"

echo "Invariant matica: $fens_count FENov (ENABLE_PL_INVARIANT=1)"

# spustit engine cez UCI, kazdy FEN samostatne (make+unmake prebieha v ID loop depth 1)
try_fen() {
    local fen="$1"
    local n
    n=$(printf 'uci\nposition fen %s\ngo depth 1\nquit\n' "$fen" | "$ENGINE" --uci >/dev/null 2>&1)
    return $?
}

echo "--- Matica ---"
i=0
while read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue

    f=$(echo "$line" | awk '{print $3}')
    desc=$(echo "$line" | awk '{print $2}')
    [[ -z "$f" ]] && continue

    if try_fen "$f"; then
        echo "[PASS] idx=$i  desc=\"$desc\""
    else
        echo "[FAIL] idx=$i  desc=\"$desc\"  FEN=\"$f\""
        failed=1
        # dump: FEN + index + exit detail
        echo "--- Dump pri zlyhani ---"
        echo "FEN: $f"
        echo "Index: $i (\"$desc\")"
        echo "Engine exit code: 72-80 => invariant poruseny pri make/unmake (pl_verify_or_die => SYS_EXIT)"
        echo "------------------------"
        # prve zlyhanie — dalej uz nezistujeme
        break
    fi

    i=$((i + 1))
done < "$FENS_FILE"

echo ""
if [[ $failed -eq 0 ]]; then
    echo "INVAR-MATRIX PASS: vsetkych $fens_count FENov prejslo make+unmake invariant clean"
    exit 0
else
    echo "INVAR-MATRIX FAIL: aspon jeden FEN porusil invariant"
    exit 1
fi
