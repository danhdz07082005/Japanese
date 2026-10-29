import urllib.request
import zipfile
import os
import json
import xml.etree.ElementTree as ET
from svg.path import parse_path

print("Fetching latest release info...")
req = urllib.request.Request("https://api.github.com/repos/KanjiVG/kanjivg/releases/latest")
req.add_header("User-Agent", "Mozilla/5.0")
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        assets = data.get("assets", [])
        zip_url = ""
        for asset in assets:
            if asset["name"].endswith("-main.zip") or asset["name"].endswith("all.zip") or asset["name"] == "kanjivg-20220427.zip":
                zip_url = asset["browser_download_url"]
                break
        
        if not zip_url and assets:
            zip_url = assets[0]["browser_download_url"]
except Exception as e:
    print("Error fetching release info, using fallback URL.", e)
    zip_url = "https://github.com/KanjiVG/kanjivg/releases/download/r20220427/kanjivg-20220427-main.zip"

zip_path = "kanjivg.zip"

if not os.path.exists("kanji"):
    if not os.path.exists(zip_path):
        print(f"Downloading KanjiVG from {zip_url}...")
        req = urllib.request.Request(zip_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response, open(zip_path, 'wb') as out_file:
            data = response.read()
            out_file.write(data)
    
    print("Extracting KanjiVG...")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(".")

print("Parsing KanjiVG SVGs...")
kanji_data = {}
kanji_dir = "kanji"

if not os.path.exists(kanji_dir):
    print(f"Directory {kanji_dir} not found. Ensure the zip extracted correctly.")
    exit(1)

count = 0
for filename in os.listdir(kanji_dir):
    if not filename.endswith(".svg"):
        continue
        
    try:
        hex_code = filename.split(".")[0]
        if "-" in hex_code:
            continue
            
        char = chr(int(hex_code, 16))
        
        filepath = os.path.join(kanji_dir, filename)
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        strokes = []
        ns = {'svg': 'http://www.w3.org/2000/svg'}
        
        for path_el in root.findall('.//svg:path', ns):
            d = path_el.get("d")
            if not d:
                continue
                
            parsed_path = parse_path(d)
            points = []
            
            num_samples = 20
            for i in range(num_samples + 1):
                fraction = i / float(num_samples)
                point = parsed_path.point(fraction)
                points.append([round(point.real, 2), round(point.imag, 2)])
                
            strokes.append(points)
            
        if strokes:
            kanji_data[char] = strokes
            
        count += 1
        if count % 1000 == 0:
            print(f"Processed {count} SVGs...")
            
    except Exception as e:
        print(f"Error on {filename}: {e}")
        pass

print(f"Total processed: {len(kanji_data)}")

output_file = "kanjivg_data.json"
print(f"Writing to {output_file}...")
with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(kanji_data, f, ensure_ascii=False, separators=(',', ':'))
    
print("Done!")
