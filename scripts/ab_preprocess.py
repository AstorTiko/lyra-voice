#!/usr/bin/env python3
"""A/B: влияние AudioPreprocessor на качество распознавания.

Берёт реальный корпус recordings/ (raw WAV + эталонный rawText из manifest),
прогоняет ОДИН И ТОТ ЖЕ боевой whisper-вызов двумя способами:
  A) сырое аудио (preprocess OFF)
  B) предобработанное аудио (точная цепочка AudioPreprocessor: silenceremove+dynaudnorm+loudnorm)
и считает близость к эталону (difflib ratio, выше = лучше) + длину.
"""
from __future__ import annotations
import json, subprocess, sys, tempfile, difflib, statistics, re
from pathlib import Path

HOME = Path.home()
BIN = "/opt/homebrew/bin/whisper-cli"
FFMPEG = "/opt/homebrew/bin/ffmpeg"
MODEL = HOME / "Library/Application Support/LyraVoice/Models/ggml-large-v3-turbo.bin"
VAD = HOME / "Library/Application Support/LyraVoice/Models/ggml-silero-v5.1.2.bin"
REC = Path(__file__).resolve().parents[2] / "recordings"
MANIFEST = REC / "manifest.jsonl"
PROMPT = ("Пиши грамотный русский текст с естественной пунктуацией. "
          "Не ставь точку, если мысль явно не завершена. Делай абзацы только при смене темы, "
          "смысловом переходе или явной команде нового абзаца. Не добавляй фразы вроде "
          "«Продолжение следует», если их не произнесли.")

def whisper(audio: Path) -> str:
    args = [BIN, "-m", str(MODEL), "-f", str(audio), "-l", "auto",
            "-t", "10", "-bs", "5", "-bo", "5",
            "--prompt", PROMPT, "--carry-initial-prompt", "-sns",
            "--vad", "-vm", str(VAD),
            "--vad-min-silence-duration-ms", "2000",
            "--vad-speech-pad-ms", "400", "--vad-max-speech-duration-s", "30",
            "-nt", "-np"]
    out = subprocess.run(args, capture_output=True, text=True)
    return out.stdout.strip()

def preprocess(audio: Path) -> Path:
    out = Path(tempfile.gettempdir()) / ("pp_" + audio.name)
    # Безопасная цепочка (после фикса): trim тишины ТОЛЬКО по краям + один мягкий loudnorm.
    trim = "silenceremove=start_periods=1:start_silence=0:start_threshold=-50dB:detection=peak"
    chain = f"{trim},areverse,{trim},areverse,loudnorm=I=-18:TP=-2:LRA=11"
    subprocess.run([FFMPEG, "-y", "-i", str(audio), "-af", chain,
                    "-ar", "16000", "-ac", "1", str(out)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return out

def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.lower().replace("ё", "е")).strip()

def ratio(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio()

def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 15
    rows = [json.loads(l) for l in MANIFEST.read_text().splitlines() if l.strip()]
    # равномерная выборка по корпусу
    step = max(1, len(rows) // n)
    sample = rows[::step][:n]
    ra_all, rb_all = [], []
    print(f"{'file':<32} {'dur':>5} {'refLen':>6} {'A→ref':>6} {'B→ref':>6} {'win':>4}")
    for r in sample:
        wav = REC / r["file"]
        if not wav.exists():
            continue
        ref = r.get("rawText", "")
        ta = whisper(wav)
        pp = preprocess(wav)
        tb = whisper(pp)
        ra, rb = ratio(ta, ref), ratio(tb, ref)
        ra_all.append(ra); rb_all.append(rb)
        win = "A" if ra > rb + 0.01 else ("B" if rb > ra + 0.01 else "=")
        print(f"{r['file']:<32} {r['durationSeconds']:>5.0f} {len(ref):>6} {ra:>6.3f} {rb:>6.3f} {win:>4}")
        try: pp.unlink()
        except OSError: pass
    print("-" * 64)
    print(f"{'MEAN A→ref (raw)':<32} {statistics.mean(ra_all):.3f}")
    print(f"{'MEAN B→ref (preprocessed)':<32} {statistics.mean(rb_all):.3f}")
    a_wins = sum(1 for a, b in zip(ra_all, rb_all) if a > b + 0.01)
    b_wins = sum(1 for a, b in zip(ra_all, rb_all) if b > a + 0.01)
    print(f"raw ближе к эталону: {a_wins}/{len(ra_all)} · preprocessed ближе: {b_wins}/{len(rb_all)}")

if __name__ == "__main__":
    main()
