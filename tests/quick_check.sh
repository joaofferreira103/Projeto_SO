#!/bin/bash
# =============================================================================
# quick_check.sh — Verificação rápida de que tudo funciona antes dos testes
# Uso: ./tests/quick_check.sh
# =============================================================================

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$PROJ_DIR/bin"
PASS=0; FAIL=0

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${YELLOW}[....] $1${NC}"; }

cd "$PROJ_DIR"

# Limpar FIFOs de execuções anteriores
rm -f tmp/main_fifo tmp/fifo_*

# 1 — Binários existem?
if [ ! -f "$BIN/controller" ] || [ ! -f "$BIN/runner" ]; then
    info "Binários não encontrados. A compilar..."
    make all || { fail "Compilação falhou."; exit 1; }
fi
ok "controller existe"
ok "runner existe"

# Arrancar controller
"$BIN/controller" 2 FIFO > /dev/null 2>&1 &
CTRL=$!
sleep 0.8

# 2 — FIFO principal criado?
[ -p "tmp/main_fifo" ] && ok "main_fifo criado" || fail "main_fifo não existe"

# 3 — Runner -e básico
info "A testar runner -e..."
OUT=$("$BIN/runner" -e 1 "echo ping_test" 2>&1)
echo "$OUT" | grep -q "ping_test" && ok "echo executado e output visível" || fail "echo não produziu output (got: $OUT)"

# 4 — Runner -c (status)
info "A testar runner -c..."
STATUS=$("$BIN/runner" -c 2>&1)
echo "$STATUS" | grep -qiE "Executing|Scheduled" && ok "runner -c retorna cabeçalhos" || fail "runner -c output inesperado: $STATUS"

# 5 — Runner -e com sleep em paralelo
info "A testar submissão múltipla..."
"$BIN/runner" -e 2 "sleep 0.5" > /dev/null 2>&1 &
PID2=$!
"$BIN/runner" -e 3 "sleep 0.5" > /dev/null 2>&1 &
PID3=$!
wait $PID2
wait $PID3

# Dar tempo ao controller para processar os REQ_FINISHED
sleep 1.5

# 6 — Log registado?
[ -s "logs/log.txt" ] && ok "logs/log.txt tem conteúdo" || fail "log.txt vazio ou ausente"

# 7 — Shutdown
info "A testar runner -s..."
"$BIN/runner" -s > /dev/null 2>&1

# Esperar até 5s que o controller termine
for i in $(seq 1 10); do
    sleep 0.5
    kill -0 $CTRL 2>/dev/null || break
done

if kill -0 $CTRL 2>/dev/null; then
    fail "Controller não terminou após shutdown (bug no controller)"
    kill $CTRL 2>/dev/null
else
    ok "Controller terminou após shutdown"
fi

[ ! -p "tmp/main_fifo" ] && ok "main_fifo removido após shutdown" || fail "main_fifo ainda existe"

# Limpeza
rm -f tmp/fifo_* tmp/main_fifo

echo ""
echo "──────────────────────────────"
echo -e "Resultado: ${GREEN}$PASS PASS${NC} | ${RED}$FAIL FAIL${NC}"
[ "$FAIL" -eq 0 ] && echo -e "${GREEN}Tudo OK. Podes correr run_tests.sh${NC}" \
                  || echo -e "${RED}Corrige os erros antes de correr os testes completos.${NC}"