const express = require('express');
const Kuroshiro = require('kuroshiro').default || require('kuroshiro');
const KuromojiAnalyzer = require('kuroshiro-analyzer-kuromoji');

const app = express();
app.use(express.json());

const kuroshiro = new Kuroshiro();
let isReady = false;

// Initialize Kuroshiro with Kuromoji
kuroshiro.init(new KuromojiAnalyzer())
    .then(() => {
        isReady = true;
        console.log("Kuroshiro is fully initialized and ready!");
    })
    .catch(err => {
        console.error("Failed to initialize Kuroshiro:", err);
    });

app.post('/convert', async (req, res) => {
    if (!isReady) {
        return res.status(503).json({ error: "Kuroshiro is still initializing. Please wait a moment." });
    }
    
    try {
        const text = req.body.text;
        if (!text) {
            return res.status(400).json({ error: "Missing 'text' in request body" });
        }
        
        // Convert using spaced Hepburn romaji (matching your game's required format)
        let romaji = await kuroshiro.convert(text, { 
            to: "romaji", 
            mode: "spaced", 
            romajiSystem: "hepburn" 
        });
        
        // Optional: Clean up punctuation weirdness that happens with spacing
        romaji = romaji.replace(/,/g, ", ");
        romaji = romaji.replace(/\./g, ". ");
        romaji = romaji.replace(/  +/g, " "); // Collapse multiple spaces
        romaji = romaji.replace(/ ,/g, ","); // Remove space before comma
        romaji = romaji.replace(/ \./g, "."); // Remove space before period
        
        // Polish Kuroshiro spaced mode specifically for the typing game
        romaji = romaji.replace(/ shi ta/g, " shita");
        romaji = romaji.replace(/ shi te/g, " shite");
        romaji = romaji.replace(/ sha/g, "sha");
        romaji = romaji.replace(/ teki/g, "teki");
        romaji = romaji.replace(/ ron teki/g, "ronteki");
        romaji = romaji.replace(/ gaku/g, "gaku");
        
        // Fix continuous verbs (te iru, te inai, te ita)
        romaji = romaji.replace(/te i nai/g, "te inai");
        romaji = romaji.replace(/de i nai/g, "de inai");
        romaji = romaji.replace(/te i ru/g, "te iru");
        romaji = romaji.replace(/de i ru/g, "de iru");
        romaji = romaji.replace(/te i ta/g, "te ita");
        romaji = romaji.replace(/de i ta/g, "de ita");
        
        // --- Custom User & AI Fixes ---
        // Fix Suffix Spacing
        romaji = romaji.replace(/ yasui/g, "yasui");
        romaji = romaji.replace(/musei ka /g, "museika ");
        romaji = romaji.replace(/taka sa /g, "takasa ");
        
        // Fix Kuroshiro Misreadings (Contextual to avoid breaking real words)
        romaji = romaji.replace(/katari no kumitate/g, "go no kumitate");
        romaji = romaji.replace(/fushi sanshō/g, "setsu sanshō");
        
        res.json({ romaji });
    } catch (err) {
        console.error("Conversion error:", err);
        res.status(500).json({ error: err.message });
    }
});

const PORT = 8081;
app.listen(PORT, () => {
    console.log(`Kuroshiro Microservice running on http://localhost:${PORT}`);
});
