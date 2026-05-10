#!/bin/bash
# =============================================================================
# run_tests.sh — Script principal de testes do projeto SO
# Uso: ./tests/run_tests.sh [teste]
#   sem argumento : corre todos os testes
#   basic         : testes básicos de funcionamento
#   fifo_vs_rr    : comparação de políticas de escalonamento
#   parallelism   : testes de paralelismo com diferentes -n
#   stress        : teste de carga com múltiplos utilizadores
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

start_controller() {
    local parallel=$1 policy=$2
    "$BIN/controller" "$parallel" "$policy" &
    CTRL_PID=$!
    sleep 0.3   # dar tempo ao controller para criar o FIFO
    info "Controller iniciado (PID=$CTRL_PID, parallel=$parallel, policy=$policy)"
}

stop_controller() {
    "$BIN/runner" -s > /dev/null 2>&1
    wait $CTRL_PID 2>/dev/null
    rm -f "$PROJ_DIR/tmp/main_fifo" "$PROJ_DIR/tmp/fifo_"*
    info "Controller parado."
}

run_cmd() {
    # run_cmd <user_id> <command>  — executa em background, devolve PID
    "$BIN/runner" -e "$1" "$2" &
    echo $!
}

wait_all() { wait; }

# ---------------------------------------------------------------------------
# TESTE 1 — Funcionamento básico
# ---------------------------------------------------------------------------
test_basic() {
    info "=== TESTE BÁSICO ==="
    start_controller 1 FIFO

    # Submeter um comando simples e verificar output
    output=$("$BIN/runner" -e 1 "echo hello_world" 2>&1)
    if echo "$output" | grep -q "hello_world"; then
        ok "echo hello_world executado com sucesso"
    else
        fail "echo hello_world falhou. Output: $output"
    fi

    # Redirecionamento >
    TMP_OUT="$PROJ_DIR/tmp/test_redir.txt"
    "$BIN/runner" -e 1 "echo redir_test > $TMP_OUT" 2>&1 | grep -q "sucesso" && \
        ok "Redirecionamento > aceite pelo runner"
    if grep -q "redir_test" "$TMP_OUT" 2>/dev/null; then
        ok "Conteúdo redirecionado correctamente para ficheiro"
    else
        warn "Ficheiro de redirecionamento vazio ou ausente"
    fi

    # Consulta de status
    status=$("$BIN/runner" -c 2>&1)
    if echo "$status" | grep -qiE "Executing|Scheduled"; then
        ok "Consulta -c retorna output com cabeçalhos"
    else
        fail "Consulta -c não retornou formato esperado. Output: $status"
    fi

    stop_controller
    ok "=== TESTE BÁSICO CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 2 — Comparação FIFO vs Round-Robin
# ---------------------------------------------------------------------------
test_fifo_vs_rr() {
    info "=== TESTE FIFO vs RR ==="
    CSV="$RESULTS_DIR/fifo_vs_rr.csv"
    echo "policy,user_id,command_id,wait_ms,exec_ms,total_ms" > "$CSV"

    for POLICY in FIFO RR; do
        info "A testar política: $POLICY"

        # Limpar log antes de cada teste
        > "$PROJ_DIR/logs/log.txt"

        # Parallelism=1 para forçar fila e ver diferença de políticas
        start_controller 1 "$POLICY"

        # Utilizador 1 submete 3 comandos (comandos mais longos)
        run_cmd 1 "sleep 1" > /dev/null
        run_cmd 1 "sleep 1" > /dev/null
        run_cmd 1 "sleep 1" > /dev/null

        # Utilizador 2 submete 1 comando (deveria ser favorecido pelo RR)
        sleep 0.1   # garantir que user1 chegou primeiro
        run_cmd 2 "sleep 1" > /dev/null

        wait_all
        stop_controller

        # Extrair dados do log e adicionar ao CSV
        while IFS='|' read -r uid cid cmd espera exec total; do
            u=$(echo "$uid" | grep -oP '\d+')
            c=$(echo "$cid" | grep -oP '\d+')
            w=$(echo "$espera" | grep -oP '\d+')
            e=$(echo "$exec" | grep -oP '\d+')
            t=$(echo "$total" | grep -oP '\d+')
            echo "$POLICY,$u,$c,$w,$e,$t" >> "$CSV"
        done < "$PROJ_DIR/logs/log.txt"

        sleep 0.5
    done

    ok "Resultados guardados em $CSV"
    info "Resumo (wait médio por política e utilizador):"
    awk -F',' 'NR>1 {sum[$1","$2]+=$4; cnt[$1","$2]++}
               END {for(k in sum) printf "  %-10s user %s -> wait médio: %.0f ms\n", \
                   split(k,a,",")?a[1]:"?", a[2], sum[k]/cnt[k]}' "$CSV" | sort
    ok "=== FIFO vs RR CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 3 — Impacto do paralelismo (parallel = 1, 2, 4)
# ---------------------------------------------------------------------------
test_parallelism() {
    info "=== TESTE DE PARALELISMO ==="
    CSV="$RESULTS_DIR/parallelism.csv"
    echo "parallel,total_wall_ms" > "$CSV"

    for PAR in 1 2 4; do
        info "A testar parallel=$PAR"
        > "$PROJ_DIR/logs/log.txt"

        start_controller "$PAR" FIFO

        T_START=$(date +%s%3N)

        # 8 comandos de 1 segundo cada
        for i in $(seq 1 8); do
            run_cmd $((i % 4 + 1)) "sleep 1" > /dev/null
        done
        wait_all

        T_END=$(date +%s%3N)
        WALL=$((T_END - T_START))

        stop_controller

        echo "$PAR,$WALL" >> "$CSV"
        ok "parallel=$PAR -> tempo total (wall): ${WALL}ms"
        sleep 0.5
    done

    info "Resultados guardados em $CSV"
    info "Esperado: parallel=1 ~8s, parallel=2 ~4s, parallel=4 ~2s"
    ok "=== PARALELISMO CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 4 — Stress: múltiplos utilizadores simultâneos
# ---------------------------------------------------------------------------
test_stress() {
    info "=== TESTE DE STRESS ==="
    CSV="$RESULTS_DIR/stress.csv"
    echo "user_id,command_id,wait_ms,exec_ms,total_ms" > "$CSV"
    > "$PROJ_DIR/logs/log.txt"

    start_controller 3 RR

    # 4 utilizadores, cada um com 3 comandos (mix de durações)
    CMDS=("sleep 0.5" "sleep 1" "sleep 0.2" "echo stress_ok")
    for USER in 1 2 3 4; do
        for CMD in "${CMDS[@]}"; do
            run_cmd "$USER" "$CMD" > /dev/null
        done
    done

    wait_all
    stop_controller

    # Processar log
    while IFS='|' read -r uid cid cmd espera exec total; do
        u=$(echo "$uid" | grep -oP '\d+')
        c=$(echo "$cid" | grep -oP '\d+')
        w=$(echo "$espera" | grep -oP '\d+')
        e=$(echo "$exec" | grep -oP '\d+')
        t=$(echo "$total" | grep -oP '\d+')
        echo "$u,$c,$w,$e,$t" >> "$CSV"
    done < "$PROJ_DIR/logs/log.txt"

    info "Resultados guardados em $CSV"
    info "Waits por utilizador (RR, parallel=3):"
    awk -F',' 'NR>1 {sum[$1]+=$3; cnt[$1]++}
               END {for(u in sum) printf "  user %s -> wait médio: %.0f ms (%d cmds)\n", \
                   u, sum[u]/cnt[u], cnt[u]}' "$CSV" | sort
    ok "=== STRESS CONCLUÍDO ==="; echo
}

# ---------------------------------------------------------------------------
# TESTE 5 — Pipe e redirecionamentos
# ---------------------------------------------------------------------------
test_redirects() {
    info "=== TESTE PIPES E REDIRECIONAMENTOS ==="
    start_controller 2 FIFO

    OUT="$PROJ_DIR/tmp/pipe_test.txt"

    # Pipe: grep | wc
    "$BIN/runner" -e 1 "grep root /etc/passwd | wc -l > $OUT" 2>&1 | grep -q "sucesso" && \
        ok "Pipe + redirecionamento aceite"
    if [ -s "$OUT" ]; then
        ok "Ficheiro de saída criado com conteúdo: $(cat "$OUT")"
    else
        warn "Ficheiro de saída vazio ou ausente"
    fi

    # Redirecionamento de input
    echo "linha de teste" > "$PROJ_DIR/tmp/input.txt"
    OUT2="$PROJ_DIR/tmp/input_redir_out.txt"
    "$BIN/runner" -e 2 "wc -l < $PROJ_DIR/tmp/input.txt > $OUT2" 2>&1
    if [ -s "$OUT2" ]; then
        ok "Redirecionamento de input (<) funcionou: $(cat "$OUT2")"
    else
        warn "Redirecionamento de input (<) sem output"
    fi

    stop_controller
    ok "=== PIPES E REDIRECIONAMENTOS CONCLUÍDOS ==="; echo
}

# ---------------------------------------------------------------------------
# Dispatcher principal
# ---------------------------------------------------------------------------
cd "$PROJ_DIR"

if [ ! -f "$BIN/controller" ] || [ ! -f "$BIN/runner" ]; then
    warn "Binários não encontrados. A compilar..."
    make -C "$PROJ_DIR" all || { fail "Compilação falhou. Abortar."; exit 1; }
fi

CHOICE="${1:-all}"
case "$CHOICE" in
    basic)        test_basic ;;
    fifo_vs_rr)   test_fifo_vs_rr ;;
    parallelism)  test_parallelism ;;
    stress)       test_stress ;;
    redirects)    test_redirects ;;
    all)
        test_basic
        test_redirects
        test_fifo_vs_rr
        test_parallelism
        test_stress
        ;;
    *)
        echo "Uso: $0 [basic|fifo_vs_rr|parallelism|stress|redirects|all]"
        exit 1
        ;;
esac

info "Todos os resultados CSV estão em: $RESULTS_DIR/"
