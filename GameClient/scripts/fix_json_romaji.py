import json
import os
import pykakasi

kks = pykakasi.kakasi()

def to_romaji(text):
    result = kks.convert(text)
    return ''.join([item['hepburn'] for item in result])

data_path = 'D:/Game/SWD/JapaneseMastery/data/jmdict_levels.json'

with open(data_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for level, items in data.items():
    for item in items:
        kana = item.get('kana', '')
        romaji_field = item.get('romaji', '')
        
        # In current json, 'kana' holds Kanji, 'romaji' holds Kana.
        actual_word_jp = kana
        actual_kana = romaji_field
        
        # if 'wordJp' already exists, it means the json was already fixed
        if 'wordJp' in item:
            continue
            
        # Update the item
        if actual_word_jp != actual_kana:
            item['wordJp'] = actual_word_jp
            item['kana'] = actual_kana
            item['romaji'] = to_romaji(actual_kana)
        else:
            # Kana-only word
            item['wordJp'] = ""
            item['kana'] = actual_kana
            item['romaji'] = to_romaji(actual_kana)
            
        # Remove old fields if necessary? No, 'kana' and 'romaji' are updated.
        
with open(data_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False)

print("Successfully fixed jmdict_levels.json!")
