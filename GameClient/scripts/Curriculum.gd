class_name Curriculum
extends RefCounted

static var LEVELS = {
	# --- Giai đoạn 1: Hiragana Cơ bản ---
	1: [
        {"kana": "あ", "romaji": "a"}, {"kana": "い", "romaji": "i"}, {"kana": "う", "romaji": "u"}, {"kana": "え", "romaji": "e"}, {"kana": "お", "romaji": "o"},
        {"kana": "か", "romaji": "ka"}, {"kana": "き", "romaji": "ki"}, {"kana": "く", "romaji": "ku"}, {"kana": "け", "romaji": "ke"}, {"kana": "こ", "romaji": "ko"}
    ],
    2: [
        {"kana": "さ", "romaji": "sa"}, {"kana": "し", "romaji": "shi"}, {"kana": "す", "romaji": "su"}, {"kana": "せ", "romaji": "se"}, {"kana": "そ", "romaji": "so"},
        {"kana": "た", "romaji": "ta"}, {"kana": "ち", "romaji": "chi"}, {"kana": "つ", "romaji": "tsu"}, {"kana": "て", "romaji": "te"}, {"kana": "と", "romaji": "to"}
    ],
    3: [
        {"kana": "な", "romaji": "na"}, {"kana": "に", "romaji": "ni"}, {"kana": "ぬ", "romaji": "nu"}, {"kana": "ね", "romaji": "ne"}, {"kana": "の", "romaji": "no"},
        {"kana": "は", "romaji": "ha"}, {"kana": "ひ", "romaji": "hi"}, {"kana": "ふ", "romaji": "fu"}, {"kana": "へ", "romaji": "he"}, {"kana": "ほ", "romaji": "ho"}
    ],
    4: [
        {"kana": "ま", "romaji": "ma"}, {"kana": "み", "romaji": "mi"}, {"kana": "む", "romaji": "mu"}, {"kana": "め", "romaji": "me"}, {"kana": "も", "romaji": "mo"},
        {"kana": "や", "romaji": "ya"}, {"kana": "ゆ", "romaji": "yu"}, {"kana": "よ", "romaji": "yo"},
        {"kana": "わ", "romaji": "wa"}, {"kana": "を", "romaji": "o"}
    ],
    5: [
        {"kana": "ら", "romaji": "ra"}, {"kana": "り", "romaji": "ri"}, {"kana": "る", "romaji": "ru"}, {"kana": "れ", "romaji": "re"}, {"kana": "ろ", "romaji": "ro"},
        {"kana": "ん", "romaji": "n"},
        {"kana": "っk", "romaji": "kk"}, {"kana": "っs", "romaji": "ss"}, {"kana": "っt", "romaji": "tt"}, {"kana": "っp", "romaji": "pp"}
    ],
    
    # --- Giai đoạn 2: Biến âm - Dakuon & Handakuon ---
    6: [
        {"kana": "が", "romaji": "ga"}, {"kana": "ぎ", "romaji": "gi"}, {"kana": "ぐ", "romaji": "gu"}, {"kana": "げ", "romaji": "ge"}, {"kana": "ご", "romaji": "go"},
        {"kana": "ざ", "romaji": "za"}, {"kana": "じ", "romaji": "ji"}, {"kana": "ず", "romaji": "zu"}, {"kana": "ぜ", "romaji": "ze"}, {"kana": "ぞ", "romaji": "zo"}
    ],
    7: [
        {"kana": "だ", "romaji": "da"}, {"kana": "ぢ", "romaji": "ji"}, {"kana": "づ", "romaji": "zu"}, {"kana": "で", "romaji": "de"}, {"kana": "ど", "romaji": "do"},
        {"kana": "ば", "romaji": "ba"}, {"kana": "び", "romaji": "bi"}, {"kana": "ぶ", "romaji": "bu"}, {"kana": "べ", "romaji": "be"}, {"kana": "ぼ", "romaji": "bo"}
    ],
    8: [
        {"kana": "ぱ", "romaji": "pa"}, {"kana": "ぴ", "romaji": "pi"}, {"kana": "ぷ", "romaji": "pu"}, {"kana": "ぺ", "romaji": "pe"}, {"kana": "ぽ", "romaji": "po"},
        {"kana": "ああ", "romaji": "aa"}, {"kana": "いい", "romaji": "ii"}, {"kana": "うう", "romaji": "uu"}, {"kana": "ええ", "romaji": "ee"}, {"kana": "おお", "romaji": "oo"}
    ],
    
    # --- Giai đoạn 3: Âm ghép & Trường âm mở rộng ---
    9: [
        {"kana": "えい", "romaji": "ei"}, {"kana": "おう", "romaji": "ou"},
        {"kana": "きゃ", "romaji": "kya"}, {"kana": "きゅ", "romaji": "kyu"}, {"kana": "きょ", "romaji": "kyo"},
        {"kana": "ぎゃ", "romaji": "gya"}, {"kana": "ぎゅ", "romaji": "gyu"}, {"kana": "ぎょ", "romaji": "gyo"}
    ],
    10: [
        {"kana": "しゃ", "romaji": "sha"}, {"kana": "しゅ", "romaji": "shu"}, {"kana": "しょ", "romaji": "sho"},
        {"kana": "じゃ", "romaji": "ja"}, {"kana": "じゅ", "romaji": "ju"}, {"kana": "じょ", "romaji": "jo"},
        {"kana": "ちゃ", "romaji": "cha"}, {"kana": "ちゅ", "romaji": "chu"}, {"kana": "ちょ", "romaji": "cho"}
    ],
    11: [
        {"kana": "にゃ", "romaji": "nya"}, {"kana": "にゅ", "romaji": "nyu"}, {"kana": "にょ", "romaji": "nyo"},
        {"kana": "ひゃ", "romaji": "hya"}, {"kana": "ひゅ", "romaji": "hyu"}, {"kana": "ひょ", "romaji": "hyo"},
        {"kana": "びゃ", "romaji": "bya"}, {"kana": "びゅ", "romaji": "byu"}, {"kana": "びょ", "romaji": "byo"}
    ],
    12: [
        {"kana": "ぴゃ", "romaji": "pya"}, {"kana": "ぴゅ", "romaji": "pyu"}, {"kana": "ぴょ", "romaji": "pyo"},
        {"kana": "みゃ", "romaji": "mya"}, {"kana": "みゅ", "romaji": "myu"}, {"kana": "みょ", "romaji": "myo"},
        {"kana": "りゃ", "romaji": "rya"}, {"kana": "りゅ", "romaji": "ryu"}, {"kana": "りょ", "romaji": "ryo"}
    ],
    
    # --- Giai đoạn 4: Katakana Cơ bản ---
    13: [
        {"kana": "ア", "romaji": "a"}, {"kana": "イ", "romaji": "i"}, {"kana": "ウ", "romaji": "u"}, {"kana": "エ", "romaji": "e"}, {"kana": "オ", "romaji": "o"},
        {"kana": "カ", "romaji": "ka"}, {"kana": "キ", "romaji": "ki"}, {"kana": "ク", "romaji": "ku"}, {"kana": "ケ", "romaji": "ke"}, {"kana": "コ", "romaji": "ko"}
    ],
    14: [
        {"kana": "サ", "romaji": "sa"}, {"kana": "シ", "romaji": "shi"}, {"kana": "ス", "romaji": "su"}, {"kana": "セ", "romaji": "se"}, {"kana": "ソ", "romaji": "so"},
        {"kana": "タ", "romaji": "ta"}, {"kana": "チ", "romaji": "chi"}, {"kana": "ツ", "romaji": "tsu"}, {"kana": "テ", "romaji": "te"}, {"kana": "ト", "romaji": "to"}
    ],
    15: [
        {"kana": "ナ", "romaji": "na"}, {"kana": "ニ", "romaji": "ni"}, {"kana": "ヌ", "romaji": "nu"}, {"kana": "ネ", "romaji": "ne"}, {"kana": "ノ", "romaji": "no"},
        {"kana": "ハ", "romaji": "ha"}, {"kana": "ヒ", "romaji": "hi"}, {"kana": "フ", "romaji": "fu"}, {"kana": "ヘ", "romaji": "he"}, {"kana": "ホ", "romaji": "ho"}
    ],
    16: [
        {"kana": "マ", "romaji": "ma"}, {"kana": "ミ", "romaji": "mi"}, {"kana": "ム", "romaji": "mu"}, {"kana": "メ", "romaji": "me"}, {"kana": "モ", "romaji": "mo"},
        {"kana": "ヤ", "romaji": "ya"}, {"kana": "ユ", "romaji": "yu"}, {"kana": "ヨ", "romaji": "yo"},
        {"kana": "ワ", "romaji": "wa"}, {"kana": "ヲ", "romaji": "wo"}
    ],
    17: [
        {"kana": "ラ", "romaji": "ra"}, {"kana": "リ", "romaji": "ri"}, {"kana": "ル", "romaji": "ru"}, {"kana": "レ", "romaji": "re"}, {"kana": "ロ", "romaji": "ro"},
        {"kana": "ン", "romaji": "n"},
        {"kana": "っk", "romaji": "kk"}, {"kana": "っs", "romaji": "ss"}, {"kana": "っt", "romaji": "tt"}, {"kana": "っp", "romaji": "pp"}
    ],
    
    # --- Giai đoạn 5: Biến âm - Dakuon & Handakuon Katakana ---
    18: [
        {"kana": "ガ", "romaji": "ga"}, {"kana": "ギ", "romaji": "gi"}, {"kana": "グ", "romaji": "gu"}, {"kana": "ゲ", "romaji": "ge"}, {"kana": "ゴ", "romaji": "go"},
        {"kana": "ザ", "romaji": "za"}, {"kana": "ジ", "romaji": "ji"}, {"kana": "ズ", "romaji": "zu"}, {"kana": "ゼ", "romaji": "ze"}, {"kana": "ゾ", "romaji": "zo"}
    ],
    19: [
        {"kana": "ダ", "romaji": "da"}, {"kana": "ヂ", "romaji": "ji"}, {"kana": "ヅ", "romaji": "zu"}, {"kana": "デ", "romaji": "de"}, {"kana": "ド", "romaji": "do"},
        {"kana": "バ", "romaji": "ba"}, {"kana": "ビ", "romaji": "bi"}, {"kana": "ブ", "romaji": "bu"}, {"kana": "ベ", "romaji": "be"}, {"kana": "ボ", "romaji": "bo"}
    ],
    20: [
        {"kana": "パ", "romaji": "pa"}, {"kana": "ピ", "romaji": "pi"}, {"kana": "プ", "romaji": "pu"}, {"kana": "ペ", "romaji": "pe"}, {"kana": "ポ", "romaji": "po"},
        {"kana": "アー", "romaji": "aa"}, {"kana": "イー", "romaji": "ii"}, {"kana": "ウー", "romaji": "uu"}, {"kana": "エー", "romaji": "ee"}, {"kana": "オー", "romaji": "oo"}
    ],
    
    # --- Giai đoạn 6: Âm ghép Katakana - Combo ---
    21: [
        {"kana": "キャ", "romaji": "kya"}, {"kana": "キュ", "romaji": "kyu"}, {"kana": "キョ", "romaji": "kyo"},
        {"kana": "ギャ", "romaji": "gya"}, {"kana": "ギュ", "romaji": "gyu"}, {"kana": "ギョ", "romaji": "gyo"},
        {"kana": "シャ", "romaji": "sha"}, {"kana": "シュ", "romaji": "shu"}, {"kana": "ショ", "romaji": "sho"}
    ],
    22: [
        {"kana": "ジャ", "romaji": "ja"}, {"kana": "ジュ", "romaji": "ju"}, {"kana": "ジョ", "romaji": "jo"},
        {"kana": "チャ", "romaji": "cha"}, {"kana": "チュ", "romaji": "chu"}, {"kana": "チョ", "romaji": "cho"},
        {"kana": "ニャ", "romaji": "nya"}, {"kana": "ニュ", "romaji": "nyu"}, {"kana": "ニョ", "romaji": "nyo"}
    ],
    23: [
        {"kana": "ヒャ", "romaji": "hya"}, {"kana": "ヒュ", "romaji": "hyu"}, {"kana": "ヒョ", "romaji": "hyo"},
        {"kana": "ビャ", "romaji": "bya"}, {"kana": "ビュ", "romaji": "byu"}, {"kana": "びょ", "romaji": "byo"},
        {"kana": "ぴゃ", "romaji": "pya"}, {"kana": "ぴゅ", "romaji": "pyu"}, {"kana": "ぴょ", "romaji": "pyo"}
    ],
    24: [
        {"kana": "ミャ", "romaji": "mya"}, {"kana": "ミュ", "romaji": "myu"}, {"kana": "ミョ", "romaji": "myo"},
        {"kana": "りゃ", "romaji": "rya"}, {"kana": "りゅ", "romaji": "ryu"}, {"kana": "りょ", "romaji": "ryo"}
    ]
}

static var extended_levels: Dictionary = {}
static var is_json_loaded: bool = false

static func get_level(level: int) -> Array:
	if LEVELS.has(level):
		return LEVELS[level].duplicate()
		
	if not is_json_loaded:
		_load_extended_json()
		
	var key = str(level)
	if extended_levels.has(key):
		return extended_levels[key].duplicate()
		
	# Resilient fallback: Never return empty array to prevent client crashes
	var fallback_key = str(25 + (abs(level - 25) % 10))
	if extended_levels.has(fallback_key):
		return extended_levels[fallback_key].duplicate()
		
	return LEVELS[1].duplicate()

static func _load_extended_json():
	var file_path = "user://data/jmdict_levels.json"
	
	if not FileAccess.file_exists(file_path):
		file_path = "res://data/jmdict_levels.json"
		
	if not FileAccess.file_exists(file_path):
		is_json_loaded = true
		return
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var json = JSON.new()
		if json.parse(content) == OK:
			extended_levels = json.data
		is_json_loaded = true
