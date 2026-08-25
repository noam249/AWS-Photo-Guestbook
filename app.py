from flask import Flask, render_template, request, redirect, url_for, flash
import boto3
import psycopg2
import os
from datetime import datetime
from werkzeug.utils import secure_filename
import uuid

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key')

# AWS Configuration
S3_BUCKET = os.environ.get('S3_BUCKET')
AWS_REGION = os.environ.get('AWS_REGION', 'eu-west-1')
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME', 'guestbook')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
AZ = os.environ.get('AZ', 'unknown')

# Initialize S3 client
s3_client = boto3.client('s3', region_name=AWS_REGION)

def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

def init_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS photos (
            id SERIAL PRIMARY KEY,
            message TEXT NOT NULL,
            s3_key VARCHAR(255) NOT NULL,
            s3_url VARCHAR(500) NOT NULL,
            uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    cursor.close()
    conn.close()

@app.route('/')
def index():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT id, message, s3_url, uploaded_at FROM photos ORDER BY uploaded_at DESC')
    photos = cursor.fetchall()
    cursor.close()
    conn.close()
    return render_template('index.html', photos=photos, az=AZ)

@app.route('/health')
def health():
    return {"status": "ok"}, 200

@app.route('/upload', methods=['POST'])
def upload():
    if 'photo' not in request.files:
        flash('No photo selected')
        return redirect(url_for('index'))

    file = request.files['photo']
    message = request.form.get('message', '').strip()

    if not message:
        flash('Please enter a message')
        return redirect(url_for('index'))

    if file.filename == '':
        flash('No photo selected')
        return redirect(url_for('index'))

    if file:
        filename = secure_filename(file.filename)
        s3_key = f"photos/{uuid.uuid4()}_{filename}"

        try:
            s3_client.upload_fileobj(
                file,
                S3_BUCKET,
                s3_key,
                ExtraArgs={'ContentType': file.content_type}
            )

            s3_url = f"https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/{s3_key}"

            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute(
                'INSERT INTO photos (message, s3_key, s3_url) VALUES (%s, %s, %s)',
                (message, s3_key, s3_url)
            )
            conn.commit()
            cursor.close()
            conn.close()

            flash('Photo uploaded successfully!')
        except Exception as e:
            flash(f'Error uploading photo: {str(e)}')

    return redirect(url_for('index'))

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=False)
