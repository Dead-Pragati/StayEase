-- StayEase: Hotel Room Reservation System
-- Note: Run this inside your selected MySQL database

DROP VIEW IF EXISTS active_bookings_view;
DROP TRIGGER IF EXISTS after_booking_insert;
DROP TRIGGER IF EXISTS after_booking_checkout;
DROP PROCEDURE IF EXISTS sp_create_booking;
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS guests;
DROP TABLE IF EXISTS rooms;

-- 1. DDL: Create Tables with Integrity Constraints (BCNF Normalized)
CREATE TABLE rooms (
    room_id INT PRIMARY KEY AUTO_INCREMENT,
    room_number VARCHAR(10) UNIQUE NOT NULL,
    room_type VARCHAR(30) NOT NULL,
    price_per_night DECIMAL(10, 2) NOT NULL CHECK (price_per_night > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'Available'
);

CREATE TABLE guests (
    guest_id INT PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(15) NOT NULL,
    id_proof VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE bookings (
    booking_id INT PRIMARY KEY AUTO_INCREMENT,
    guest_id INT NOT NULL,
    room_id INT NOT NULL,
    check_in DATE NOT NULL,
    nights INT NOT NULL CHECK (nights > 0),
    total_amount DECIMAL(10, 2) NOT NULL,
    booking_status VARCHAR(20) NOT NULL DEFAULT 'Active',
    FOREIGN KEY (guest_id) REFERENCES guests(guest_id) ON DELETE CASCADE,
    FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE
);

-- 2. Indexing for Query Optimization
CREATE INDEX idx_room_status ON rooms(status);

-- 3. View: Combined Guest, Room & Booking Details (Joins)
CREATE VIEW active_bookings_view AS
SELECT 
    b.booking_id,
    g.full_name,
    g.phone,
    g.id_proof,
    r.room_number,
    r.room_type,
    b.check_in,
    b.nights,
    b.total_amount,
    b.booking_status
FROM bookings b
JOIN guests g ON b.guest_id = g.guest_id
JOIN rooms r ON b.room_id = r.room_id
ORDER BY b.booking_id DESC;

-- 4. Triggers: Automatic Room Status Management
DELIMITER //

CREATE TRIGGER after_booking_insert
AFTER INSERT ON bookings
FOR EACH ROW
BEGIN
    UPDATE rooms 
    SET status = 'Booked' 
    WHERE room_id = NEW.room_id;
END //

CREATE TRIGGER after_booking_checkout
AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
    IF NEW.booking_status = 'Checked-Out' AND OLD.booking_status != 'Checked-Out' THEN
        UPDATE rooms 
        SET status = 'Available' 
        WHERE room_id = NEW.room_id;
    END IF;
END //

-- 5. Stored Procedure with Transaction Management (TCL: START TRANSACTION, COMMIT, ROLLBACK)
CREATE PROCEDURE sp_create_booking(
    IN p_name VARCHAR(100),
    IN p_phone VARCHAR(15),
    IN p_id_proof VARCHAR(50),
    IN p_room_id INT,
    IN p_check_in DATE,
    IN p_nights INT
)
BEGIN
    DECLARE v_price DECIMAL(10, 2);
    DECLARE v_status VARCHAR(20);
    DECLARE v_guest_id INT;
    DECLARE v_total DECIMAL(10, 2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT price_per_night, status INTO v_price, v_status
    FROM rooms 
    WHERE room_id = p_room_id 
    FOR UPDATE;

    IF v_status != 'Available' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Selected room is already booked';
    END IF;

    INSERT INTO guests (full_name, phone, id_proof)
    VALUES (p_name, p_phone, p_id_proof)
    ON DUPLICATE KEY UPDATE
        full_name = VALUES(full_name),
        phone = VALUES(phone),
        guest_id = LAST_INSERT_ID(guest_id);

    SET v_guest_id = LAST_INSERT_ID();
    SET v_total = v_price * p_nights;

    INSERT INTO bookings (guest_id, room_id, check_in, nights, total_amount)
    VALUES (v_guest_id, p_room_id, p_check_in, p_nights, v_total);

    COMMIT;
END //

DELIMITER ;

-- 6. DML: Initial Sample Data
INSERT INTO rooms (room_number, room_type, price_per_night) VALUES
('101', 'Standard', 1500.00),
('102', 'Standard', 1500.00),
('201', 'Deluxe', 2800.00),
('202', 'Deluxe', 2800.00),
('301', 'Suite', 4500.00);

CALL sp_create_booking('Rohan Sharma', '9876543210', 'AADHAR-1122', 3, CURDATE(), 2);
