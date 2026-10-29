import bz2
import re

def clean_wiki_text(text):
    # Remove Wiki markup, links, etc.
    text = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]+)\]\]', r'\1', text) # Remove wiki links but keep text
    text = re.sub(r'\{\{[^\}]+\}\}', '', text) # Remove templates
    text = re.sub(r'<ref[^>]*>.*?</ref>', '', text, flags=re.IGNORECASE|re.DOTALL) # Remove refs
    text = re.sub(r'<[^>]+>', '', text) # Remove HTML tags
    text = re.sub(r'={2,}.*?={2,}', '', text) # Remove headers
    text = re.sub(r'\[http[^\]]+\]', '', text) # Remove external links
    text = re.sub(r"''+", "", text) # Remove bold/italic markers
    text = re.sub(r'\*.*', '', text) # Remove lists
    return text.strip()

def is_japanese_text(text):
    # Match mostly Japanese characters (hiragana, katakana, kanji)
    # Reject lines that start with list elements or have weird symbols
    if re.search(r'^[;:*・#\|]', text) or re.search(r'(&lt|&gt)', text) or text.startswith('File:'):
        return False
        
    # Reject lines with residual image/wiki markdown
    if re.search(r'(thumb\||left\||right\||px\||\|)', text):
        return False
        
    if '[[' in text or ']]' in text or '{{' in text or '}}' in text or '}}。' in text:
        return False
        
    japanese_chars = len(re.findall(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]', text))
    # Require at least 20 Japanese characters
    return japanese_chars > 20

def extract_paragraphs(dump_path, out_path, limit=1000):
    paragraphs = set()
    
    print(f"Opening {dump_path}...")
    try:
        with bz2.open(dump_path, "rt", encoding="utf-8") as f:
            in_text_block = False
            current_text = ""
            
            for line in f:
                if '<text' in line:
                    in_text_block = True
                    current_text = line.split('>', 1)[-1] if '>' in line else ""
                elif '</text>' in line:
                    in_text_block = False
                    current_text += line.split('</text>')[0]
                    
                    # Process the accumulated text block
                    # Split by newlines to get potential paragraphs
                    lines = current_text.split('\n')
                    for p in lines:
                        cleaned = clean_wiki_text(p)
                        if 30 <= len(cleaned) <= 150:
                            if is_japanese_text(cleaned):
                                paragraphs.add(cleaned)
                                if len(paragraphs) >= limit:
                                    break
                    if len(paragraphs) >= limit:
                        break
                    
                    current_text = ""
                elif in_text_block:
                    current_text += line

        print(f"Extracted {len(paragraphs)} paragraphs.")
        
        with open(out_path, "w", encoding="utf-8") as out_f:
            for p in list(paragraphs):
                out_f.write(p + "\n")
                
        print(f"Saved to {out_path}.")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    DUMP_FILE = r"d:\Game\SWD\jawiki-latest-pages-articles.xml.bz2"
    OUT_FILE = r"d:\Game\SWD\JapaneseMasteryBackend\pvp_paragraphs.txt"
    extract_paragraphs(DUMP_FILE, OUT_FILE, limit=1000)
