import xml.etree.ElementTree as ET
import json
import os
import urllib.request
import gzip
import shutil
import pykakasi

kks = pykakasi.kakasi()

def to_romaji(text):
    result = kks.convert(text)
    return ''.join([item['hepburn'] for item in result])

script_dir = os.path.dirname(os.path.abspath(__file__))
project_dir = os.path.dirname(script_dir)
data_dir = os.path.join(project_dir, 'data')
os.makedirs(data_dir, exist_ok=True)

jmdict_path = os.path.join(data_dir, 'JMdict_e')

if not os.path.exists(jmdict_path):
    print("JMdict_e not found. Downloading...")
    url = "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
    gz_path = jmdict_path + ".gz"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response, open(gz_path, 'wb') as out_file:
        shutil.copyfileobj(response, out_file)
    print("Extracting JMdict_e...")
    with gzip.open(gz_path, 'rb') as f_in, open(jmdict_path, 'wb') as f_out:
        shutil.copyfileobj(f_in, f_out)
    os.remove(gz_path)
    print("Download and extraction complete.")

print("Parsing JMdict_e for ALL words...")
tree = ET.parse(jmdict_path)
root = tree.getroot()

vocab_list = []
for entry in root.findall('entry'):
    keb = ""
    k_ele = entry.find('k_ele')
    if k_ele is not None:
        keb_node = k_ele.find('keb')
        if keb_node is not None:
            keb = keb_node.text
            
    reb = ""
    r_ele = entry.find('r_ele')
    if r_ele is not None:
        reb_node = r_ele.find('reb')
        if reb_node is not None:
            reb = reb_node.text
            
    if not keb:
        keb = reb
        
    if not reb:
        continue
        
    meanings = []
    for sense in entry.findall('sense'):
        for gloss in sense.findall('gloss'):
            if gloss.text:
                meanings.append(gloss.text)
                
    if not meanings:
        continue
        
    meaning_str = ", ".join(meanings[:2]).replace('"', "'")
    
    actual_word_jp = keb if keb != reb else ""
    actual_kana = reb
    actual_romaji = to_romaji(reb)

    vocab_list.append({
        "wordJp": actual_word_jp,
        "kana": actual_kana,
        "romaji": actual_romaji,
        "meaning": meaning_str
    })

print(f"Found {len(vocab_list)} total words.")

levels_dict = {}
total_levels = len(vocab_list) // 10
print(f"Generating {total_levels} levels...")

for i in range(total_levels):
    start = i * 10
    end = start + 10
    level = 25 + i
    items = vocab_list[start:end]
    if len(items) == 0:
        break
    levels_dict[str(level)] = items

json_path = os.path.join(data_dir, 'jmdict_levels.json')

with open(json_path, 'w', encoding='utf-8') as f:
    json.dump(levels_dict, f, ensure_ascii=False)

print(f"Successfully exported {len(levels_dict)} levels to {json_path}!")
