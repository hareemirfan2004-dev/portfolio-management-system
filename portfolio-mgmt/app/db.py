import os
from contextlib import contextmanager
import mysql.connector
from dotenv import load_dotenv

# Load .env from the project root (one directory above this file)
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env'))


def _connect():
    return mysql.connector.connect(
        host=os.getenv('DB_HOST', 'localhost'),
        port=int(os.getenv('DB_PORT', '3306')),
        user=os.getenv('DB_USER', 'root'),
        password=os.getenv('DB_PASSWORD', ''),
        database=os.getenv('DB_NAME', 'portfolio_db'),
        autocommit=False,
    )


@contextmanager
def get_db():
    """Yield (connection, dict-cursor); close both on exit.

    Usage:
        with get_db() as (conn, cur):
            cur.execute('SELECT ...')
            rows = cur.fetchall()
            conn.commit()   # only when writing

    Any uncommitted transaction is automatically rolled back when the
    connection closes (autocommit=False), so exceptions are safe.
    """
    conn = _connect()
    cur = conn.cursor(dictionary=True)
    try:
        yield conn, cur
    finally:
        cur.close()
        conn.close()
