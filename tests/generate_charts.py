#!/usr/bin/env python3
"""
generate_charts.py — Gera gráficos a partir dos CSVs produzidos por run_tests.sh
Uso: python3 tests/generate_charts.py
Requer: pip install matplotlib pandas
"""

import os, sys
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

RESULTS = os.path.join(os.path.dirname(__file__), "results")
CHARTS  = os.path.join(RESULTS, "charts")
os.makedirs(CHARTS, exist_ok=True)

plt.rcParams.update({"figure.dpi": 120, "font.size": 11})

# ─── helpers ────────────────────────────────────────────────────────────────

def save(fig, name):
    path = os.path.join(CHARTS, name)
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    print(f"  Guardado: {path}")

def load(filename):
    path = os.path.join(RESULTS, filename)
    if not os.path.exists(path):
        print(f"  [SKIP] {filename} não encontrado — corre primeiro run_tests.sh")
        return None
    df = pd.read_csv(path)
    if df.empty:
        print(f"  [SKIP] {filename} está vazio")
        return None
    return df

# ─── 1. FIFO vs RR — wait médio por utilizador ──────────────────────────────

def chart_fifo_vs_rr():
    df = load("fifo_vs_rr.csv")
    if df is None: return

    summary = df.groupby(["policy", "user_id"])["wait_ms"].mean().reset_index()
    policies = summary["policy"].unique()
    users    = sorted(summary["user_id"].unique())

    x     = range(len(users))
    width = 0.35
    colors = {"FIFO": "#4C72B0", "RR": "#DD8452"}

    fig, ax = plt.subplots(figsize=(8, 5))
    for i, pol in enumerate(policies):
        vals = [summary[(summary.policy == pol) & (summary.user_id == u)]["wait_ms"].values
                for u in users]
        vals = [v[0] if len(v) else 0 for v in vals]
        ax.bar([xi + i * width for xi in x], vals, width, label=pol,
               color=colors.get(pol, "gray"))

    ax.set_xlabel("Utilizador")
    ax.set_ylabel("Tempo de espera médio (ms)")
    ax.set_title("FIFO vs Round-Robin — Tempo de espera médio por utilizador")
    ax.set_xticks([xi + width / 2 for xi in x])
    ax.set_xticklabels([f"user {u}" for u in users])
    ax.legend()
    ax.grid(axis="y", alpha=0.4)
    save(fig, "fifo_vs_rr_wait.png")

    # Boxplot de distribuição de waits
    fig2, ax2 = plt.subplots(figsize=(8, 5))
    data_box = [df[df.policy == p]["wait_ms"].values for p in policies]
    bp = ax2.boxplot(data_box, labels=list(policies), patch_artist=True)
    for patch, pol in zip(bp["boxes"], policies):
        patch.set_facecolor(colors.get(pol, "gray"))
    ax2.set_ylabel("Tempo de espera (ms)")
    ax2.set_title("Distribuição de tempos de espera — FIFO vs RR")
    ax2.grid(axis="y", alpha=0.4)
    save(fig2, "fifo_vs_rr_boxplot.png")

# ─── 2. Paralelismo — tempo total (wall clock) ──────────────────────────────

def chart_parallelism():
    df = load("parallelism.csv")
    if df is None: return

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    # Barra do tempo wall
    ax = axes[0]
    colors = ["#4C72B0", "#DD8452", "#55A868"]
    bars = ax.bar(df["parallel"].astype(str), df["total_wall_ms"] / 1000,
                  color=colors[:len(df)])
    ax.bar_label(bars, fmt="%.1fs", padding=3)
    ax.set_xlabel("Número de comandos em paralelo")
    ax.set_ylabel("Tempo total (s)")
    ax.set_title("Tempo total de execução vs Nível de paralelismo\n(8 comandos × sleep 1s)")
    ax.grid(axis="y", alpha=0.4)

    # Speedup relativo ao serial (parallel=1)
    ax2 = axes[1]
    base = df[df["parallel"] == 1]["total_wall_ms"].values[0] if 1 in df["parallel"].values else None
    if base:
        df2 = df.copy()
        df2["speedup"] = base / df2["total_wall_ms"]
        ax2.plot(df2["parallel"], df2["speedup"], "o-", color="#4C72B0", linewidth=2, markersize=8)
        # Speedup ideal
        ax2.plot(df2["parallel"], df2["parallel"].astype(float), "--", color="gray",
                 label="Speedup ideal")
        ax2.set_xlabel("Número de comandos em paralelo")
        ax2.set_ylabel("Speedup (×)")
        ax2.set_title("Speedup vs Paralelismo (base = parallel=1)")
        ax2.legend()
        ax2.grid(alpha=0.4)

    fig.tight_layout()
    save(fig, "parallelism.png")

# ─── 3. Stress — distribuição de waits por utilizador ───────────────────────

def chart_stress():
    df = load("stress.csv")
    if df is None: return

    users = sorted(df["user_id"].unique())

    fig, ax = plt.subplots(figsize=(9, 5))
    data = [df[df.user_id == u]["wait_ms"].values for u in users]
    bp = ax.boxplot(data, labels=[f"user {u}" for u in users], patch_artist=True)
    palette = ["#4C72B0", "#DD8452", "#55A868", "#C44E52"]
    for patch, col in zip(bp["boxes"], palette):
        patch.set_facecolor(col)

    ax.set_ylabel("Tempo de espera (ms)")
    ax.set_title("Distribuição de tempos de espera por utilizador\n(RR, parallel=3, 4 utilizadores × 4 comandos)")
    ax.grid(axis="y", alpha=0.4)
    save(fig, "stress_wait_distribution.png")

    # Throughput (cmds concluídos) por utilizador
    fig2, ax2 = plt.subplots(figsize=(7, 4))
    counts = df.groupby("user_id").size()
    ax2.bar([f"user {u}" for u in counts.index], counts.values,
            color=palette[:len(counts)])
    ax2.set_ylabel("Comandos executados")
    ax2.set_title("Comandos concluídos por utilizador (stress test)")
    ax2.grid(axis="y", alpha=0.4)
    save(fig2, "stress_throughput.png")

# ─── main ───────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("A gerar gráficos...")
    chart_fifo_vs_rr()
    chart_parallelism()
    chart_stress()
    print(f"\nGráficos guardados em: {CHARTS}/")
    print("Inclui no relatório: fifo_vs_rr_wait.png, fifo_vs_rr_boxplot.png,")
    print("  parallelism.png, stress_wait_distribution.png, stress_throughput.png")
