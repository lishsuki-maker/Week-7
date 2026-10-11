from flask import Flask, jsonify, request
import mysql.connector
import os

app = Flask(__name__)

db_config = {
    "host": os.getenv("DB_HOST", "db"),
    "user": os.getenv("MYSQL_USER", "MySQLUser"),
    "password": os.getenv("MYSQL_PASSWORD", "MySQLPassword"),
    "database": os.getenv("DB_NAME", "ContainerizedRESTAPI"),
    "port": int(os.getenv("DB_PORT", 3306))
}


def get_connection():
    return mysql.connector.connect(**db_config)

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

@app.route("/api/feedback", methods=["POST"])
def create_feedback():
    data = request.get_json()
    feedback = data.get("feedback", "")

    if len(feedback.split()) < 3:
        return jsonify({"error": "Feedback must contain at least 3 words"}), 400

    database = get_connection()
    cursor = database.cursor()
    cursor.execute(
        "INSERT INTO Feedback (feedback) VALUES (%s)",
        (feedback,)
    )
    database.commit()
    cursor.close()
    database.close()
    return jsonify({"message": "Your feedback has been successfully created"}), 201

@app.route("/api/feedback", methods=["GET"])
def list_feedback():
    database = get_connection()
    cursor = database.cursor(dictionary=True)
    cursor.execute("SELECT * FROM Feedback")
    feedback = cursor.fetchall()
    cursor.close()
    database.close()
    return jsonify(feedback), 200

@app.route("/api/feedback/<int:feedback_id>", methods=["GET"])
def get_feedback(feedback_id):
    database = get_connection()
    cursor = database.cursor(dictionary=True)
    cursor.execute(
        "SELECT * FROM Feedback WHERE id = %s",
        (feedback_id,)
    )
    feedback = cursor.fetchone()
    cursor.close()
    database.close()
    if feedback is None:
        return jsonify({"error": "Feedback not found"}), 404 
    return jsonify(feedback), 200
