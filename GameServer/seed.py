import json
import re

data = '''
Level 1: Nguyên âm & Hàng K (10 từ)
Nguyên âm: あ (a), い (i), う (u), え (e), お (o)
Hàng K: か (ka), き (ki), く (ku), け (ke), こ (ko)
Level 2: Hàng S & Hàng T (10 từ)
Hàng S: さ (sa), し (shi), す (su), せ (se), そ (so)
Hàng T: た (ta), ち (chi), つ (tsu), て (te), と (to)
Level 3: Hàng N & Hàng H (10 từ)
Hàng N: な (na), に (ni), ぬ (nu), ね (ne), の (no)
Hàng H: は (ha), ひ (hi), ふ (fu), へ (he), ほ (ho)
Level 4: Hàng M, Y, W (10 từ)
Hàng M: ま (ma), み (mi), む (mu), め (me), も (mo)
Hàng Y: や (ya), ゆ (yu), よ (yo)
Hàng W & O: わ (wa), を (o)
Level 5: Hàng R, Âm mũi & Xúc âm (10 từ)
Hàng R: ら (ra), り (ri), る (ru), れ (re), ろ (ro)
Âm mũi: ん (n)
Xúc âm (Small っ): っ (kk), っ (ss), っ (tt), っ (pp)
Level 6: Âm đục 1 - Hàng G & Z (10 từ)
Hàng G: が (ga), ぎ (gi), ぐ (gu), げ (ge), ご (go)
Hàng Z: ざ (za), じ (ji), ず (zu), ぜ (ze), ぞ (zo)
Level 7: Âm đục 2 - Hàng D & B (10 từ)
Hàng D: だ (da), ぢ (ji), づ (zu), で (de), ど (do)
Hàng B: ば (ba), び (bi), ぶ (bu), べ (be), ぼ (bo)
Level 8: Âm bán đục & Trường âm 1 (10 từ)
Hàng P: ぱ (pa), ぴ (pi), ぷ (pu), ぺ (pe), ぽ (po)
Trường âm: ああ (aa), いい (ii), うう (uu), ええ (ee), おお (oo)
Level 9: Trường âm 2 & Âm ghép 1 (8 từ)
Trường âm mở rộng: えい (ei), おう (ou)
Ghép K: きゃ (kya), きゅ (kyu), きょ (kyo)
Ghép G: ぎゃ (gya), ぎゅ (gyu), ぎょ (gyo)
Level 10: Âm ghép 2 (9 từ)
Ghép S: しゃ (sha), しゅ (shu), しょ (sho)
Ghép J: じゃ (ja), じゅ (ju), じょ (jo)
Ghép C: ちゃ (cha), ちゅ (chu), ちょ (cho)
Level 11: Âm ghép 3 (9 từ)
Ghép N: にゃ (nya), にゅ (nyu), にょ (nyo)
Ghép H: ひゃ (hya), ひゅ (hyu), ひょ (hyo)
Ghép B: びゃ (bya), びゅ (byu), びょ (byo)
Level 12: Âm ghép 4 (9 từ)
Ghép P: ぴゃ (pya), ぴゅ (pyu), ぴょ (pyo)
Ghép M: みゃ (mya), みゅ (myu), みょ (myo)
Ghép R: りゃ (rya), りゅ (ryu), りょ (ryo)
Level 13: Nguyên âm & Hàng K (10 từ)
Nguyên âm: ア (a), イ (i), ウ (u), エ (e), オ (o)
Hàng K: カ (ka), キ (ki), ク (ku), ケ (ke), コ (ko)
Level 14: Hàng S & Hàng T (10 từ)
Hàng S: サ (sa), シ (shi), ス (su), セ (se), ソ (so)
Hàng T: タ (ta), チ (chi), ツ (tsu), テ (te), ト (to)
Level 15: Hàng N & Hàng H (10 từ)
Hàng N: ナ (na), ニ (ni), ヌ (nu), ネ (ne), ノ (no)
Hàng H: ハ (ha), ヒ (hi), フ (fu), ヘ (he), ホ (ho)
Level 16: Hàng M, Y, W (10 từ)
Hàng M: マ (ma), ミ (mi), ム (mu), メ (me), モ (mo)
Hàng Y: ヤ (ya), ユ (yu), ヨ (yo)
Hàng W & O: ワ (wa), ヲ (wo)
Level 17: Hàng R, Âm mũi & Xúc âm (10 từ)
Hàng R: ラ (ra), リ (ri), ル (ru), レ (re), ロ (ro)
Âm mũi: ン (n)
Xúc âm (Small ッ): ッ (kk), ッ (ss), ッ (tt), ッ (pp)
Level 18: Âm đục 1 - Hàng G & Z (10 từ)
Hàng G: ガ (ga), ギ (gi), グ (gu), ゲ (ge), ゴ (go)
Hàng Z: ザ (za), ジ (ji), ズ (zu), ゼ (ze), ゾ (zo)
Level 19: Âm đục 2 - Hàng D & B (10 từ)
Hàng D: ダ (da), ヂ (ji), ヅ (zu), デ (de), ド (do)
Hàng B: バ (ba), ビ (bi), ブ (bu), ベ (be), ボ (bo)
Level 20: Âm bán đục & Trường âm (10 từ)
Hàng P: パ (pa), ピ (pi), プ (pu), ペ (pe), ポ (po)
Trường âm Katakana: アー (aa), イー (ii), ウー (uu), エー (ee), オー (oo)
Level 21: Ghép K, G, S (9 từ)
Ghép K: キャ (kya), キュ (kyu), キョ (kyo)
Ghép G: ギャ (gya), ギュ (gyu), ギョ (gyo)
Ghép S: シャ (sha), シュ (shu), ショ (sho)
Level 22: Ghép J, C, N (9 từ)
Ghép J: ジャ (ja), ジュ (ju), ジョ (jo)
Ghép C: チャ (cha), チュ (chu), チョ (cho)
Ghép N: ニャ (nya), ニュ (nyu), ニョ (nyo)
Level 23: Ghép H, B, P (9 từ)
Ghép H: ヒャ (hya), ヒュ (hyu), ヒョ (hyo)
Ghép B: ビャ (bya), ビュ (byu), ビョ (byo)
Ghép P: ピャ (pya), ピュ (pyu), ピョ (pyo)
Level 24: Ghép M & R (6 từ)
Ghép M: ミャ (mya), ミュ (myu), ミョ (myo)
Ghép R: リャ (rya), リュ (ryu), リョ (ryo)
'''

lines = data.split('\n')
current_level = 0
results = []
for line in lines:
    line = line.strip()
    if not line: continue
    m = re.match(r'^Level (\d+):', line)
    if m:
        current_level = int(m.group(1))
        continue
    
    # Extract pairs of char (romaji)
    pairs = re.findall(r'([^\s\(\),:]+)\s*\(([^)]+)\)', line)
    for char, romaji in pairs:
        # Check for bad matches like "âm", "Small"
        if char.lower() in ["âm", "small", "hàng", "trường", "xúc"]:
            continue
        
        # determine type
        if current_level <= 12:
            t = 'HIRAGANA'
        else:
            t = 'KATAKANA'
        
        # for these basic kanas, wordJp is empty, kana is char, romaji is romaji
        results.append(f'            createVocab(vList, "", "{char}", "{romaji}", "{romaji}", {current_level}, WordType.{t});')

java_code = """package com.example.japanesegame.config;

import com.example.japanesegame.entity.Vocabulary;
import com.example.japanesegame.entity.WordType;
import com.example.japanesegame.repository.VocabularyRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

@Component
@Order(2)
@RequiredArgsConstructor
public class VocabularySeeder implements CommandLineRunner {

    private final VocabularyRepository vocabularyRepository;

    @Override
    public void run(String... args) throws Exception {
        if (vocabularyRepository.count() == 0) {
            List<Vocabulary> vList = new ArrayList<>();
""" + '\n'.join(results) + """

            vocabularyRepository.saveAll(vList);
            System.out.println("Default vocabularies created (Levels 1-24).");
        }
    }

    private void createVocab(List<Vocabulary> list, String jp, String kana, String romaji, String meaning, int level, WordType type) {
        list.add(Vocabulary.builder()
                .wordJp(jp)
                .kana(kana)
                .romaji(romaji)
                .meaning(meaning)
                .levelRequired(level)
                .type(type)
                .build());
    }
}
"""

with open('src/main/java/com/example/japanesegame/config/VocabularySeeder.java', 'w', encoding='utf-8') as f:
    f.write(java_code)
