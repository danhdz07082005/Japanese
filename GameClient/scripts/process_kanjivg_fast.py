import urllib.request
import zipfile
import os
import json
import xml.etree.ElementTree as ET

zip_path = "kanjivg.zip"

if not os.path.exists("kanji"):
    print("Extracting KanjiVG...")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(".")

print("Parsing KanjiVG SVGs...")
kanji_data = {}
kanji_dir = "kanji"

if not os.path.exists(kanji_dir):
    print(f"Directory {kanji_dir} not found.")
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
        
        # Read the raw SVG content
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Quick and dirty path extraction without heavy XML parsing
        import re
        paths = re.findall(r'<path[^>]*d="([^"]+)"', content)
        
        if paths:
            kanji_data[char] = paths
            
        count += 1
        if count % 2000 == 0:
            print(f"Processed {count} SVGs...")
            
    except Exception as e:
        print(f"Error on {filename}: {e}")
        pass

print(f"Total processed: {len(kanji_data)}")

output_file = "kanjivg_paths.json"
print(f"Writing to {output_file}...")
with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(kanji_data, f, ensure_ascii=False, separators=(',', ':'))
    
print("Done!")
