#!/usr/bin/env python3
"""ASR baseline benchmark for Lyra Voice.

Повторяет ТОЧНО боевой вызов whisper-cli (см. WhisperCommand.swift) и замеряет:
  - wall-clock задержку (то, что чувствует пользователь);
  - RTF = wall / длительность аудио;
  - время загрузки модели (whisper timings) — потенциал «тёплого» ASR (шаг 0.3).

Это фиксирует точку отсчёта ДО предобработки аудио (шаг 0.2), чтобы доказуемо
сравнивать улучшения. Дефолты берутся из настроек приложения.
"""
from __future__ import annotations

import argparse
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
DEFAULT_BINARY = "/opt/homebrew/bin/whisper-cli"
DEFAULT_MODEL_DIR = HOME / "Library/Application Support/LyraVoice/Models"
MODEL_FILES = {
    "turbo": "ggml-large-v3-turbo.bin",
    "large-v3": "ggml-large-v3.bin",
    "medium": "ggml-medium.bin",
    "small": "ggml-small.bin",
    "tiny": "ggml-tiny.bin",
}
# Боевой промпт по умолчанию (settings.json → initialPrompt).
DEFAULT_PROMPT = ("Пиши грамотный русский текст с естественной пунктуацией, "
                  "запятыми, точками и вопросительными знаками.")


def audio_duration(path: Path) -> float:
    out = subprocess.run(["afinfo", str(path)], capture_output=True, text=True).stdout
    m = re.search(r"estimated duration:\s*([0-9.]+)", out)
    return float(m.group(1)) if m else 0.0


def thread_count() -> int:
    try:
        n = int(subprocess.run(["sysctl", "-n", "hw.activecpu"],
                               capture_output=True, text=True).stdout.strip())
    except Exception:
        n = 4
    return max(4, n)


def build_args(binary: str, model: Path, audio: Path, lang: str, prompt: str,
               threads: int, beam: int, quiet: bool) -> list[str]:
    """Идентично WhisperCommand.arguments."""
    args = [binary, "-m", str(model), "-f", str(audio), "-l", lang,
            "-t", str(threads), "-bs", str(beam), "-bo", str(beam)]
    if prompt.strip():
        args += ["--prompt", prompt, "--carry-initial-prompt"]
    args += ["-sns", "-nt"]
    if quiet:
        args.append("-np")          # боевой режим — без логов
    return args


def parse_timings(stderr: str) -> dict[str, float]:
    """Извлекает whisper_print_timings (мс)."""
    out = {}
    for key in ("load", "encode", "decode", "batchd", "prompt", "total"):
        m = re.search(rf"{key}\s+time\s*=\s*([0-9.]+)\s*ms", stderr)
        if m:
            out[key] = float(m.group(1))
    return out


def run_once(args: list[str], timeout: int) -> tuple[float, str, str, int]:
    start = time.perf_counter()
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    wall = time.perf_counter() - start
    return wall, p.stdout.strip(), p.stderr, p.returncode


def main() -> int:
    ap = argparse.ArgumentParser(description="Lyra Voice ASR baseline benchmark")
    here = Path(__file__).resolve().parent.parent
    ap.add_argument("--audio-dir", default=str(here / "benchmarks/audio"))
    ap.add_argument("--models", default="turbo,large-v3")
    ap.add_argument("--binary", default=DEFAULT_BINARY)
    ap.add_argument("--model-dir", default=str(DEFAULT_MODEL_DIR))
    ap.add_argument("--lang", default="auto")
    ap.add_argument("--prompt", default=DEFAULT_PROMPT)
    ap.add_argument("--beam", type=int, default=5)
    ap.add_argument("--runs", type=int, default=3, help="прогонов на пару (1-й = warmup, отбрасывается)")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--out", default=str(here / "benchmarks" / f"baseline-{time.strftime('%Y-%m-%d')}.md"))
    args = ap.parse_args()

    threads = thread_count()
    model_dir = Path(args.model_dir)
    audio_dir = Path(args.audio_dir)
    audios = sorted(audio_dir.glob("*.wav"))
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    if not audios:
        print(f"Нет .wav в {audio_dir} — сначала ./scripts/make-benchmark-audio.sh", file=sys.stderr)
        return 1

    print(f"binary={args.binary}\nmodel_dir={model_dir}\nthreads={threads} beam={args.beam} "
          f"lang={args.lang} runs={args.runs}\naudios={len(audios)} models={models}\n")

    rows = []           # (audio, model, dur, wall_avg, rtf)
    load_times = {}     # model -> load ms
    transcripts = {}    # (audio, model) -> text

    for model_name in models:
        mf = model_dir / MODEL_FILES.get(model_name, f"ggml-{model_name}.bin")
        if not mf.exists():
            print(f"⚠ модель {model_name} не найдена ({mf}) — пропуск")
            continue

        # Один диагностический прогон с таймингами (без -np) на самом длинном файле.
        longest = max(audios, key=audio_duration)
        diag_args = build_args(args.binary, mf, longest, args.lang, args.prompt,
                               threads, args.beam, quiet=False)
        try:
            _, _, stderr, _ = run_once(diag_args, args.timeout)
            t = parse_timings(stderr)
            if "load" in t:
                load_times[model_name] = t["load"]
        except Exception as e:
            print(f"  диагностика таймингов {model_name}: {e}")

        for audio in audios:
            dur = audio_duration(audio)
            walls = []
            text = ""
            run_args = build_args(args.binary, mf, audio, args.lang, args.prompt,
                                  threads, args.beam, quiet=True)
            for r in range(args.runs):
                try:
                    wall, stdout, _, rc = run_once(run_args, args.timeout)
                except subprocess.TimeoutExpired:
                    print(f"  ⏱ timeout {model_name} {audio.name}")
                    wall, stdout, rc = float("nan"), "", -1
                if rc == 0:
                    text = stdout
                if r > 0:               # 1-й прогон — warmup
                    walls.append(wall)
            wall_avg = statistics.mean(walls) if walls else float("nan")
            rtf = wall_avg / dur if dur else float("nan")
            rows.append((audio.name, model_name, dur, wall_avg, rtf))
            transcripts[(audio.name, model_name)] = text
            print(f"  {model_name:9} {audio.name:16} dur={dur:6.2f}s  wall={wall_avg:6.2f}s  RTF={rtf:4.2f}")

    write_report(Path(args.out), args, threads, rows, load_times, transcripts)
    print(f"\nОтчёт: {args.out}")
    return 0


def write_report(path, args, threads, rows, load_times, transcripts):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    lines.append(f"# ASR baseline — {time.strftime('%Y-%m-%d %H:%M')}")
    lines.append("")
    lines.append("Точка отсчёта ДО предобработки аудио (P0, шаг 0.1). Вызов идентичен "
                 "`WhisperCommand` в приложении. Корпус синтетический (`say` Milena) — "
                 "валиден для скорости/RTF, не для WER.")
    lines.append("")
    lines.append("## Конфигурация")
    lines.append("")
    lines.append(f"- binary: `{args.binary}`")
    lines.append(f"- threads: {threads} · beam: {args.beam} · lang: `{args.lang}`")
    lines.append(f"- runs на пару: {args.runs} (первый — warmup, отброшен)")
    lines.append(f"- prompt: `{args.prompt[:60]}…`")
    lines.append("")
    lines.append("## Задержка по файлам")
    lines.append("")
    lines.append("| Файл | Модель | Длит., с | Wall, с | RTF |")
    lines.append("|---|---|---:|---:|---:|")
    for name, model, dur, wall, rtf in rows:
        lines.append(f"| {name} | {model} | {dur:.2f} | {wall:.2f} | {rtf:.2f} |")
    lines.append("")
    lines.append("## Сводка по моделям")
    lines.append("")
    lines.append("| Модель | Ср. RTF | Медиана wall, с | Load model, мс |")
    lines.append("|---|---:|---:|---:|")
    models = []
    for _, m, _, _, _ in rows:
        if m not in models:
            models.append(m)
    for m in models:
        rtfs = [r for (_, mm, _, _, r) in rows if mm == m and r == r]
        walls = [w for (_, mm, _, w, _) in rows if mm == m and w == w]
        avg_rtf = statistics.mean(rtfs) if rtfs else float("nan")
        med_wall = statistics.median(walls) if walls else float("nan")
        load = load_times.get(m)
        load_s = f"{load:.0f}" if load is not None else "—"
        lines.append(f"| {m} | {avg_rtf:.2f} | {med_wall:.2f} | {load_s} |")
    lines.append("")
    lines.append("> «Load model, мс» — сколько на каждой диктовке тратится только на "
                 "загрузку весов. Это устраняет «тёплый» ASR (шаг 0.3).")
    lines.append("")
    lines.append("## Распознанный текст (для глаза)")
    lines.append("")
    for (name, model), text in transcripts.items():
        lines.append(f"- **{name}** / {model}: {text or '∅'}")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
