import xml.etree.ElementTree as ET
import json
import os
import pykakasi

kks = pykakasi.kakasi()

def to_romaji(text):
    result = kks.convert(text)
    return ''.join([item['hepburn'] for item in result])

print("Parsing JMdict_e...")
tree = ET.parse(r'd:\Game\SWD\JMdict_e')
root = tree.getroot()

vocab_list = []
for entry in root.findall('entry'):
    is_common = False
    for k_ele in entry.findall('k_ele'):
        for pri in k_ele.findall('ke_pri'):
            if pri.text in ['news1', 'ichi1']:
                is_common = True
                break
    
    if not is_common:
        for r_ele in entry.findall('r_ele'):
            for pri in r_ele.findall('re_pri'):
                if pri.text in ['news1', 'ichi1']:
                    is_common = True
                    break
    
    if not is_common:
        continue
        
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
    
    if len(vocab_list) >= 760: # Level 25 to 100 is 76 levels * 10 = 760 words
        break

print(f"Found {len(vocab_list)} common words.")

levels_gd = []
for i in range(76):
    start = i * 10
    end = start + 10
    level = 25 + i
    items = vocab_list[start:end]
    if len(items) == 0:
        break
        
    items_str = ", ".join([json.dumps(x, ensure_ascii=False) for x in items])
    levels_gd.append(f"\t{level}: [{items_str}],")

print("Updating Curriculum.gd...")
curriculum_path = r'd:\Game\SWD\JapaneseMastery\scripts\Curriculum.gd'
with open(curriculum_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find the last closing brace of the LEVELS dictionary
last_brace_idx = content.rfind('}')
if last_brace_idx != -1:
    new_content = content[:last_brace_idx]
    if not new_content.endswith(',\n') and not new_content.endswith(','):
        new_content = new_content.rstrip() + ",\n"
    
    for l in levels_gd:
        new_content += l + "\n"
        
    new_content += "}\n"
    
    with open(curriculum_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Successfully added Levels 25 to 100 to Curriculum.gd!")
else:
    print("Could not find closing brace in Curriculum.gd.")
