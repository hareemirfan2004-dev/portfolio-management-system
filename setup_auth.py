import os
import mysql.connector
from werkzeug.security import generate_password_hash
from dotenv import load_dotenv

load_dotenv('.env')

conn = mysql.connector.connect(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', 3306)),
    user=os.getenv('DB_USER', 'root'),
    password=os.getenv('DB_PASSWORD', ''),
    database=os.getenv('DB_NAME', 'portfolio_db')
)
cur = conn.cursor()

cur.execute('''
CREATE TABLE IF NOT EXISTS Admins (
    Admin_ID INT AUTO_INCREMENT PRIMARY KEY,
    Username VARCHAR(50) NOT NULL UNIQUE,
    Password_Hash VARCHAR(255) NOT NULL
)
''')

cur.execute('DELETE FROM Admins WHERE Username = "admin"')

password_hash = generate_password_hash('password123')
cur.execute('INSERT INTO Admins (Username, Password_Hash) VALUES (%s, %s)', ('admin', password_hash))
conn.commit()
print("Auth setup complete.")
