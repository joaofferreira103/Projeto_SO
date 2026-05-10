#!/bin/bash
# =============================================================================
# run_tests.sh — Script principal de testes do projeto SO
# Uso: ./tests/run_tests.sh [teste]
# =============================================================================

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$PROJ_DIR/bin"
RESULTS_DIR="$PROJ_DIR/tests/results"

mkdir -p "$RESULTS_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------

RUNNER_PIDS=()

start_controller() {
    local parallel=$1 policy=$2
    rm -f "$PROJ_DIR/tmp/main_fifo" "$PROJ_DIR/tmp/fifo_"*
    RUNNER_PIDS=()
    "$BIN/controller" "$parallel" "$policy" > /dev/null 2>&1 &
    CTRL_PID=$!
    sleep 0.8
    info "Controller iniciado (PID=$CTRL_PID, parallel=$parallel, policy=$policy)"
}

stop_controller() {
    # Esperar todos os runners terminarem
    for pid in "${RUNNER_PIDS[@]}"; do
        wait "$pid" 2>/dev/null
    done
    sleep 0.5  # dar tempo ao controller para processar os REQ_FINISHED
    "$BIN/runner" -s > /dev/null 2>&1
    for i in $(seq 1 10); do
        sleep 0.5
        kill -0 $CTRL_PID 2>/dev/null || break
    done
    kill $CTRL_PID 2>/dev/null
    rm -f "$PROJ_DIR/tmp/main_fifo" "$PROJ_DIR/tmp/fifo_"*
    info "Controller parado."
}

run_cmd() {
    # run_cmd <user_id> <command> — lança em background e regista o PID
    "$BIN/runner" -e "$1" "$2" > /dev/null 2>&1 &
    RUNNER_PIDS+=($!)
}

# ---------------------------------------------------------------------------
# TESTE 1 — Funcionamento básico
# ---------------------------------------------------------------------------
test_basic() {
    info "=== TESTE BÁSICO ==="
    start_controller 1 FIFO

    output=$("$BIN/runner" -e 1 "echo hello_world" 2>&1)
    if echo "$output" | grep -q "hello_world"; then
        ok "echo hello_world executado com sucesso"
    else
        fail "echo hello_world falhou. Output: $output"
    fi

    TMP_OUT="$PROJ_DIR/tmp/test_redir.txt"
    "$BIN/runner" -e 1 "echo redir_test > $TMP_OUT" > /dev/null 2>&1
    sleep 0.3
    if grep -q "redir_test" "$TMP_OUT" 2>/dev/null; then
        ok "Redirecionamento > funcionou"
    else
        warn "Redirecionamento > sem conteúdo"
    fi

    status=$("$BIN/runner" -c 2>&1)
    if echo "$status" | grep -qiE "Executing|Scheduled"; then
        ok "Consulta -c retorna output correcto"
    else
        fail "Consulta -c falhou. Output: $status"
    fi

    stop_controller
    ok "=== TESTE BÁSICO CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 2 — Pipes e redirecionamentos
# ---------------------------------------------------------------------------
test_redirects() {
    info "=== TESTE PIPES E REDIRECIONAMENTOS ==="
    start_controller 2 FIFO

    OUT="$PROJ_DIR/tmp/pipe_test.txt"
    "$BIN/runner" -e 1 "grep root /etc/passwd | wc -l > $OUT" > /dev/null 2>&1
    sleep 0.5
    if [ -s "$OUT" ]; then
        ok "Pipe + redirecionamento: $(cat "$OUT" | tr -d ' ')"
    else
        warn "Pipe sem output"
    fi

    echo "linha de teste" > "$PROJ_DIR/tmp/input.txt"
    OUT2="$PROJ_DIR/tmp/input_redir_out.txt"
    "$BIN/runner" -e 2 "wc -l < $PROJ_DIR/tmp/input.txt > $OUT2" > /dev/null 2>&1
    sleep 0.5
    if [ -s "$OUT2" ]; then
        ok "Redirecionamento input (<): $(cat "$OUT2" | tr -d ' ')"
    else
        warn "Redirecionamento input (<) sem output"
    fi

    stop_controller
    ok "=== PIPES E REDIRECIONAMENTOS CONCLUÍDOS ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 3 — Comparação FIFO vs Round-Robin
# ---------------------------------------------------------------------------
test_fifo_vs_rr() {
    info "=== TESTE FIFO vs RR ==="
    CSV="$RESULTS_DIR/fifo_vs_rr.csv"
    echo "policy,user_id,command_id,wait_ms,exec_ms,total_ms" > "$CSV"

    for POLICY in FIFO RR; do
        info "A testar política: $POLICY"
        > "$PROJ_DIR/logs/log.txt"

        start_controller 1 "$POLICY"

        # User 1 submete 3 comandos
        run_cmd 1 "sleep 1"
        run_cmd 1 "sleep 1"
        run_cmd 1 "sleep 1"
        # User 2 submete 1 comando depois
        sleep 0.5
        run_cmd 2 "sleep 1"

        stop_controller

        # Extrair dados do log
        while IFS='|' read -r uid cid cmd espera exec total; do
            u=$(echo "$uid" | grep -oE '[0-9]+')
            c=$(echo "$cid" | grep -oE '[0-9]+')
            w=$(echo "$espera" | grep -oE '[0-9]+')
            e=$(echo "$exec" | grep -oE '[0-9]+')
            t=$(echo "$total" | grep -oE '[0-9]+')
            [ -n "$u" ] && echo "$POLICY,$u,$c,$w,$e,$t" >> "$CSV"
        done < "$PROJ_DIR/logs/log.txt"

        sleep 0.5
    done

    ok "Resultados guardados em $CSV"
    info "Resumo (wait médio por política e utilizador):"
    awk -F',' 'NR>1 {sum[$1","$2]+=$4; cnt[$1","$2]++}
               END {for(k in sum) printf "  %-6s user %s -> wait medio: %.0f ms\n", \
                   split(k,a,",")?a[1]:"?", a[2], sum[k]/cnt[k]}' "$CSV" | sort
    ok "=== FIFO vs RR CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 4 — Impacto do paralelismo
# ---------------------------------------------------------------------------
test_parallelism() {
    info "=== TESTE DE PARALELISMO ==="
    CSV="$RESULTS_DIR/parallelism.csv"
    echo "parallel,total_wall_ms" > "$CSV"

    for PAR in 1 2 4; do
        info "A testar parallel=$PAR"
        > "$PROJ_DIR/logs/log.txt"

        start_controller "$PAR" FIFO
        T_START=$(python3 -c "import time; print(int(time.time()*1000))")

        for i in $(seq 1 8); do
            run_cmd $((i % 4 + 1)) "sleep 1"
        done

        stop_controller
        T_END=$(python3 -c "import time; print(int(time.time()*1000))")
        WALL=$((T_END - T_START))

        echo "$PAR,$WALL" >> "$CSV"
        ok "parallel=$PAR -> tempo total: ${WALL}ms"
        sleep 0.5
    done

    info "Resultados em $CSV"
    info "Esperado: parallel=1 ~8s, parallel=2 ~4s, parallel=4 ~2s"
    ok "=== PARALELISMO CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 5 — Stress multi-utilizador
# ---------------------------------------------------------------------------
test_stress() {
    info "=== TESTE DE STRESS ==="
    CSV="$RESULTS_DIR/stress.csv"
    echo "user_id,command_id,wait_ms,exec_ms,total_ms" > "$CSV"
    > "$PROJ_DIR/logs/log.txt"

    start_controller 3 RR

    for USER in 1 2 3 4; do
        run_cmd "$USER" "sleep 0.5"
        run_cmd "$USER" "sleep 1"
        run_cmd "$USER" "sleep 0.2"
        run_cmd "$USER" "echo stress_ok"
    done

    stop_controller

    while IFS='|' read -r uid cid cmd espera exec total; do
        u=$(echo "$uid" | grep -oE '[0-9]+')
        c=$(echo "$cid" | grep -oE '[0-9]+')
        w=$(echo "$espera" | grep -oE '[0-9]+')
        e=$(echo "$exec" | grep -oE '[0-9]+')
        t=$(echo "$total" | grep -oE '[0-9]+')
        [ -n "$u" ] && echo "$u,$c,$w,$e,$t" >> "$CSV"
    done < "$PROJ_DIR/logs/log.txt"

    info "Waits por utilizador (RR, parallel=3):"
    awk -F',' 'NR>1 {sum[$1]+=$3; cnt[$1]++}
               END {for(u in sum) printf "  user %s -> wait medio: %.0f ms (%d cmds)\n", \
                   u, sum[u]/cnt[u], cnt[u]}' "$CSV" | sort
    ok "=== STRESS CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
cd "$PROJ_DIR"

if [ ! -f "$BIN/controller" ] || [ ! -f "$BIN/runner" ]; then
    warn "Binários não encontrados. A compilar..."
    make -C "$PROJ_DIR" all || { fail "Compilação falhou."; exit 1; }
fi

CHOICE="${1:-all}"
case "$CHOICE" in
    basic)        test_basic ;;
    redirects)    test_redirects ;;
    fifo_vs_rr)   test_fifo_vs_rr ;;
    parallelism)  test_parallelism ;;
    stress)       test_stress ;;
    all)
        test_basic
        test_redirects
        test_fifo_vs_rr
        test_parallelism
        test_stress
        ;;
    *)
        echo "Uso: $0 [basic|redirects|fifo_vs_rr|parallelism|stress|all]"
        exit 1
        ;;
esac

info "Resultados CSV em: $RESULTS_DIR/"