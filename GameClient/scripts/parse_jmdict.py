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
    alt_path = os.path.join(project_dir, 'JMdict_e')
    if os.path.exists(alt_path):
        jmdict_path = alt_path

if not os.path.exists(jmdict_path):
    print("JMdict_e not found. Downloading...")
    url = "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
    gz_path = os.path.join(data_dir, "JMdict_e.gz")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response, open(gz_path, 'wb') as out_file:
        shutil.copyfileobj(response, out_file)
    print("Extracting JMdict_e...")
    with gzip.open(gz_path, 'rb') as f_in, open(jmdict_path, 'wb') as f_out:
        shutil.copyfileobj(f_in, f_out)
    if os.path.exists(gz_path):
        os.remove(gz_path)
    print("Download and extraction complete.")

print(f"Parsing {jmdict_path}...")
tree = ET.parse(jmdict_path)
root = tree.getroot()

vocab_list = []
common_priorities = {'news1', 'ichi1', 'spec1', 'gai1', 'news2', 'ichi2', 'spec2', 'gai2'}

for entry in root.findall('entry'):
    is_common = False
    for pri in entry.findall('.//ke_pri') + entry.findall('.//re_pri'):
        if pri.text in common_priorities:
            is_common = True
            break
    
    if not is_common:
        continue
        
    keb = ""
    k_ele = entry.find('k_ele')
    if k_ele is not None:
        keb_node = k_ele.find('keb')
        if keb_node is not None and keb_node.text:
            keb = keb_node.text
            
    reb = ""
    r_ele = entry.find('r_ele')
    if r_ele is not None:
        reb_node = r_ele.find('reb')
        if reb_node is not None and reb_node.text:
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
    
    if len(vocab_list) >= 760: # Level 25 to 100 is 76 levels * 10 = 760 words
        break

print(f"Found {len(vocab_list)} common words.")

levels_gd = []
levels_dict = {}
for i in range(76):
    start = i * 10
    end = start + 10
    level = 25 + i
    items = vocab_list[start:end]
    if len(items) == 0:
        break
        
    items_str = ", ".join([json.dumps(x, ensure_ascii=False) for x in items])
    levels_gd.append(f"\t{level}: [{items_str}],")
    levels_dict[str(level)] = items

# Also export to jmdict_levels.json
json_path = os.path.join(data_dir, 'jmdict_levels.json')
with open(json_path, 'w', encoding='utf-8') as f:
    json.dump(levels_dict, f, ensure_ascii=False)
print(f"Exported levels to {json_path}")

print("Updating Curriculum.gd...")
curriculum_path = os.path.join(script_dir, 'Curriculum.gd')
if os.path.exists(curriculum_path):
    with open(curriculum_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find where LEVELS dict ends (before static var extended_levels)
    target = "static var extended_levels"
    target_idx = content.find(target)
    
    search_region = content[:target_idx] if target_idx != -1 else content
    last_brace_idx = search_region.rfind('}')
    
    if last_brace_idx != -1:
        prefix = content[:last_brace_idx].rstrip()
        suffix = content[last_brace_idx:]
        
        if not prefix.endswith(','):
            prefix += ",\n"
        else:
            prefix += "\n"
            
        inserted_code = "\n".join(levels_gd) + "\n"
        new_content = prefix + inserted_code + suffix
        
        with open(curriculum_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print("Successfully updated Curriculum.gd with Levels 25 to 100!")
    else:
        print("Could not find closing brace for LEVELS in Curriculum.gd.")
else:
    print(f"Curriculum.gd not found at {curriculum_path}")
