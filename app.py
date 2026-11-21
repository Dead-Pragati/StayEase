from flask import Flask, render_template, request, redirect, url_for, flash
import pymysql
from datetime import date

app = Flask(__name__)
app.secret_key = 'stayease_secret_key'

# MySQL Database Configuration (Update these details as per your setup)
DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'stayease_db',
    'cursorclass': pymysql.cursors.DictCursor
}

def get_db_connection():
    return pymysql.connect(**DB_CONFIG)

@app.route('/')
def index():
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            # Fetch all rooms
            cursor.execute("SELECT * FROM rooms ORDER BY room_number ASC")
            rooms = cursor.fetchall()

            # Fetch bookings using SQL View
            cursor.execute("SELECT * FROM active_bookings_view")
            bookings = cursor.fetchall()

            # Fetch dashboard stats using Aggregate Functions
            cursor.execute("""
                SELECT 
                    COUNT(*) AS total_rooms,
                    COALESCE(SUM(CASE WHEN status = 'Available' THEN 1 ELSE 0 END), 0) AS available_rooms,
                    COALESCE(SUM(CASE WHEN status = 'Booked' THEN 1 ELSE 0 END), 0) AS booked_rooms
                FROM rooms
            """)
            stats = cursor.fetchone()

            cursor.execute("SELECT COALESCE(SUM(total_amount), 0) AS total_revenue FROM bookings")
            stats['total_revenue'] = cursor.fetchone()['total_revenue']
    finally:
        conn.close()

    return render_template(
        'index.html',
        rooms=rooms,
        bookings=bookings,
        stats=stats,
        today=date.today().isoformat()
    )

@app.route('/book', methods=['POST'])
def book_room():
    full_name = request.form['full_name'].strip()
    phone = request.form['phone'].strip()
    id_proof = request.form['id_proof'].strip()
    room_id = int(request.form['room_id'])
    check_in = request.form['check_in']
    nights = int(request.form['nights'])

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            # Calls Stored Procedure (handles Transaction, Trigger & Bill Calculation)
            cursor.callproc('sp_create_booking', (full_name, phone, id_proof, room_id, check_in, nights))
        conn.commit()
        flash('Room booked successfully!', 'success')
    except pymysql.MySQLError as e:
        conn.rollback()
        flash(f'Booking failed: {e.args[1]}', 'danger')
    finally:
        conn.close()

    return redirect(url_for('index'))

@app.route('/checkout/<int:booking_id>', methods=['POST'])
def checkout_booking(booking_id):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            # Fires 'after_booking_checkout' Trigger automatically
            cursor.execute(
                "UPDATE bookings SET booking_status = 'Checked-Out' WHERE booking_id = %s",
                (booking_id,)
            )
        conn.commit()
        flash('Guest checked out! Room status automatically set to Available.', 'info')
    except pymysql.MySQLError as e:
        conn.rollback()
        flash(f'Error: {e.args[1]}', 'danger')
    finally:
        conn.close()

    return redirect(url_for('index'))

@app.route('/add_room', methods=['POST'])
def add_room():
    room_number = request.form['room_number'].strip()
    room_type = request.form['room_type']
    price_per_night = float(request.form['price_per_night'])

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "INSERT INTO rooms (room_number, room_type, price_per_night) VALUES (%s, %s, %s)",
                (room_number, room_type, price_per_night)
            )
        conn.commit()
        flash(f'Room {room_number} added successfully!', 'success')
    except pymysql.MySQLError as e:
        conn.rollback()
        flash(f'Could not add room: {e.args[1]}', 'danger')
    finally:
        conn.close()

    return redirect(url_for('index'))

@app.route('/delete_booking/<int:booking_id>', methods=['POST'])
def delete_booking(booking_id):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT room_id, booking_status FROM bookings WHERE booking_id = %s", (booking_id,))
            record = cursor.fetchone()
            if record:
                if record['booking_status'] == 'Active':
                    cursor.execute("UPDATE rooms SET status = 'Available' WHERE room_id = %s", (record['room_id'],))
                cursor.execute("DELETE FROM bookings WHERE booking_id = %s", (booking_id,))
        conn.commit()
        flash('Booking record deleted.', 'warning')
    except pymysql.MySQLError as e:
        conn.rollback()
        flash(f'Delete failed: {e.args[1]}', 'danger')
    finally:
        conn.close()

    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True)
