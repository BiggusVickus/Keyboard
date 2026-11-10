"""Serves the trained Dutch <-> English models to the Taalhulp keyboard over your home network.

Point it at one of the packages from nl-en-translator/models (the folder with translate.py):

  # Raspberry Pi 4 (CPU, int8):
  python3 translate_server.py --package ~/nl-en-translator/models/pi4
  # PC with the GPU (falls back to CPU when CUDA isn't available):
  python translate_server.py --package G:/nl-en-translator/models/gpu16

Then put http://<this computer's IP>:8020 under Taalhulp → Settings → Translator.

  GET  /health     -> {"ok": true, "pairs": ["nl-en", "en-nl"], "device": "cuda"}
  POST /translate  {"text": "...", "source": "nl", "target": "en"} -> {"translation": "..."}

The models stay loaded in memory, so a translation takes well under a second on the GPU and
about a second per sentence on the Pi. There is no password: only run it on your own network
(or Tailscale), never forwarded to the internet.
"""
import argparse
import importlib.util
import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAIRS = ("nl-en", "en-nl")
MAX_CHARS = 5000
# A sentence ends at . ! ? or … followed by a space and something that can start a sentence.
SENTENCE_END = re.compile(r"(?<=[.!?…])\s+(?=[\"'“‘(\[]?[A-Z0-9À-Ý])")


def load_package(package_dir):
    """Imports translate.py from the package and returns translate(texts, pair) -> list of str."""
    package_dir = os.path.abspath(package_dir)
    spec = importlib.util.spec_from_file_location("package_translate", os.path.join(package_dir, "translate.py"))
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, package_dir)
    spec.loader.exec_module(module)

    if os.path.isdir(os.path.join(package_dir, "ct2")):
        # gpu16: one NLLB model for both directions. CUDA libraries load lazily, so translate once
        # to find out whether the GPU really works (and to warm it up).
        try:
            model, device = module.Translator(package_dir, device="cuda"), "cuda"
            model(["Hallo."], "nl-en")
        except Exception as error:  # no CUDA or no cuBLAS: still works, just slower
            print(f"GPU not usable ({error}); using the CPU. For the GPU on Windows: "
                  "pip install nvidia-cublas-cu12", file=sys.stderr)
            model, device = module.Translator(package_dir, device="cpu"), "cpu"
        return (lambda texts, pair: model(texts, pair)), device

    # pi4: one Marian model per direction, both loaded now so the first request is fast.
    threads = os.cpu_count() or 4
    models = {pair: module.Translator(pair, threads=threads) for pair in PAIRS}
    return (lambda texts, pair: models[pair](texts)), "cpu"


def split_sentences(text):
    """The models were trained on single sentences: split paragraphs into sentences and keep the layout."""
    pieces = []  # (sentence, separator after it)
    for line_index, line in enumerate(text.split("\n")):
        if line_index:
            if pieces:
                pieces[-1] = (pieces[-1][0], pieces[-1][1].rstrip(" ") + "\n")
            else:
                pieces.append(("", "\n"))
        sentences = [s for s in SENTENCE_END.split(line.strip()) if s]
        pieces.extend((s, " ") for s in sentences)
    if pieces:
        pieces[-1] = (pieces[-1][0], pieces[-1][1].rstrip(" "))
    return pieces


def make_handler(translate, device, lock):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, status, body):
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path.rstrip("/") == "/health":
                self._send(200, {"ok": True, "pairs": list(PAIRS), "device": device})
            else:
                self._send(404, {"error": "not found"})

        def do_POST(self):
            if self.path.rstrip("/") != "/translate":
                return self._send(404, {"error": "not found"})
            try:
                length = int(self.headers.get("Content-Length", 0))
                request = json.loads(self.rfile.read(length).decode("utf-8"))
                text = str(request["text"])[:MAX_CHARS]
                pair = f"{request['source']}-{request['target']}"
            except (ValueError, KeyError, TypeError):
                return self._send(400, {"error": "expected JSON with text, source and target"})
            if pair not in PAIRS:
                return self._send(400, {"error": f"only {', '.join(PAIRS)}"})

            pieces = split_sentences(text)
            sentences = [s for s, _ in pieces if s]
            try:
                with lock:  # one batch at a time keeps memory use predictable on the Pi
                    translated = iter(translate(sentences, pair)) if sentences else iter(())
            except Exception as error:
                print(f"Translation failed: {error}", file=sys.stderr, flush=True)
                return self._send(500, {"error": "translation failed"})
            result = "".join((next(translated) if s else "") + sep for s, sep in pieces)
            self._send(200, {"translation": result})

        def log_message(self, format, *args):
            pass  # keep the users' text out of the logs

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package", required=True, help="model package folder (models/pi4 or models/gpu16)")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8020)
    args = parser.parse_args()

    translate, device = load_package(args.package)
    print(f"Loaded {args.package} on {device}. Listening on http://{args.host}:{args.port}", flush=True)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(translate, device, threading.Lock()))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
