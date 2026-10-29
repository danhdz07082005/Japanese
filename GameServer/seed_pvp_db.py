import sqlite3
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "test.db")
TXT_PATH = os.path.join(BASE_DIR, "pvp_paragraphs.txt")

def seed_database(db_path=DB_PATH, txt_path=TXT_PATH):
    print(f"Connecting to DB at {db_path}")
    
    # Create the db file if it doesn't exist
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Create table for PvP paragraphs
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS pvp_paragraphs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL
        )
    """)
    
    print(f"Reading paragraphs from {txt_path}...")
    if not os.path.exists(txt_path):
        print(f"Error: Paragraphs file not found at {txt_path}")
        return
        
    with open(txt_path, "r", encoding="utf-8") as f:
        paragraphs = [line.strip() for line in f if line.strip()]
        
    print(f"Inserting {len(paragraphs)} paragraphs into DB...")
    
    # Clear existing to avoid duplicates if re-run
    cursor.execute("DELETE FROM pvp_paragraphs")
    
    for p in paragraphs:
        cursor.execute("INSERT INTO pvp_paragraphs (content) VALUES (?)", (p,))
        
    conn.commit()
    conn.close()
    print("Database seeded successfully.")

if __name__ == "__main__":
    seed_database()
