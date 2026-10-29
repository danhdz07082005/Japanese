import json
import time
from svg.path import parse_path

print("Loading paths JSON...")
with open("kanjivg_paths.json", "r", encoding="utf-8") as f:
    data = json.load(f)

print(f"Baking {len(data)} characters...")
start_time = time.time()
baked_data = {}

count = 0
for char, paths in data.items():
    baked_char = []
    for d in paths:
        try:
            parsed = parse_path(d)
            stroke_points = []
            num_samples = 20
            for i in range(num_samples + 1):
                fraction = i / float(num_samples)
                pt = parsed.point(fraction)
                stroke_points.append([round(pt.real, 2), round(pt.imag, 2)])
            baked_char.append(stroke_points)
        except Exception as e:
            pass
    if baked_char:
        baked_data[char] = baked_char
    
    count += 1
    if count % 1000 == 0:
        print(f"Baked {count} characters...")

print(f"Finished baking in {time.time() - start_time:.2f} seconds.")

out_file = "kanjivg_baked.json"
print(f"Writing to {out_file}...")
with open(out_file, "w", encoding="utf-8") as f:
    json.dump(baked_data, f, ensure_ascii=False, separators=(',', ':'))

print("Done!")
