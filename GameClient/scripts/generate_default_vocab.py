import os
import re
import json

def generate_default_vocab():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    curriculum_path = os.path.join(script_dir, "Curriculum.gd")

    if not os.path.exists(curriculum_path):
        print(f"Curriculum.gd not found at {curriculum_path}")
        return

    with open(curriculum_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Search up to level 25
    idx_25 = content.find("25:")
    search_region = content[:idx_25] if idx_25 != -1 else content

    matches = re.findall(r'(\d+):\s*\[(.*?)\]', search_region, re.DOTALL)
    default_vocab = {}

    for lvl_str, block in matches:
        lvl = int(lvl_str)
        if lvl > 24:
            continue

        items = []
        for item_m in re.finditer(r'\{([^}]+)\}', block):
            raw = "{" + item_m.group(1) + "}"
            try:
                d = json.loads(raw)
                k = d.get("kana", "").strip()
                r = d.get("romaji", "").strip()
                m = d.get("meaning", r).strip()
                if not m:
                    m = r
                w_jp = d.get("wordJp", k).strip()
                if not w_jp:
                    w_jp = k

                word_type = "HIRAGANA" if lvl <= 12 else "KATAKANA"
                items.append({
                    "id": 0,
                    "wordJp": w_jp,
                    "kana": k,
                    "romaji": r,
                    "meaning": m,
                    "type": word_type,
                    "levelRequired": lvl
                })
            except Exception as e:
                print(f"Error parsing item in level {lvl}: {raw} -> {e}")

        if items:
            default_vocab[str(lvl)] = items

    print(f"Parsed {len(default_vocab)} levels for default_vocab.json.")

    # Target locations
    target_paths = [
        os.path.join(project_dir, "data", "default_vocab.json"),
        os.path.join(os.path.dirname(project_dir), "JapaneseMasteryUnity", "Assets", "StreamingAssets", "data", "default_vocab.json"),
        os.path.join(os.path.dirname(project_dir), "JapaneseMasteryBackendDotNet", "data", "default_vocab.json")
    ]

    for path in target_paths:
        target_dir = os.path.dirname(path)
        if os.path.exists(target_dir) or "JapaneseMastery/data" in path.replace("\\", "/"):
            os.makedirs(target_dir, exist_ok=True)
            with open(path, "w", encoding="utf-8") as out:
                json.dump(default_vocab, out, ensure_ascii=False, indent=2)
            print(f"Saved default_vocab.json to {path}")

if __name__ == "__main__":
    generate_default_vocab()

