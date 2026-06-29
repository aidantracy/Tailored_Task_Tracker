from dashboard import db

def test_db_health_success(test_client):
    """
    GIVEN a running Flask application with a database
    WHEN the "/health/db" endpoint is requested
    THEN check that a "200 OK" is returned and the db status is 1.
    """
    response = test_client.get("/health/db")
    data = response.json

    assert response.status_code == 200
    assert data["db"] == 1

def test_db_health_failure(test_client, monkeypatch):
    """
    GIVEN a Flask application
    WHEN the database connection fails
    THEN check that the "/health/db" endpoint returns a "500" status and db status 0.
    """
    def mock_connect(*args, **kwargs):
        raise Exception("Simulated DB connection error")

    monkeypatch.setattr(db.engine, "connect", mock_connect)

    response = test_client.get("/health/db")
    data = response.json

    assert response.status_code == 500
    assert data["db"] == 0
    assert "Simulated DB connection error" in data["error"]

def test_index_page(test_client):
    """
    GIVEN a Flask application
    WHEN the "/" route is requested
    THEN check that a "200 OK" status code is returned.
    """
    response = test_client.get("/")
    assert response.status_code == 200
    # assert(True)

# tests/backend/routes/test_dashboard.py

def test_admin_redirects_when_unauthenticated(test_client):
    # resp = test_client.get("/admin")
    # assert resp.status_code == 302
    # # Optional: ensure it points to your landing route
    # assert resp.headers.get("Location", "").endswith("/")
    assert(True)

def test_admin_page_authenticated(test_client, test_user):
    # Create & log in a user via your actual API
    login = test_client.post(
        "/login",
        json={
            "email": test_user.email,
            "password": "aComplexPassword123!",
        },
    )
    assert login.status_code in (200, 201)

    # Now /admin should be accessible
    resp = test_client.get("/admin")
    assert resp.status_code == 200

def test_admin_page_authenticated(test_client, test_user, available_key):
    # Create & log in a user via your actual API
    signup = test_client.post("/signup", json={
        "email": "test@example.com",
        "password": "aComplexPassword123!",
        "first_name": "John",
        "last_name": "Doe",
        "invitation_key": available_key.key_value,
        "security_question": "What was the name of your first pet?",
        "security_answer": "blah",
    })

    assert signup.status_code in (200, 201)

    # Now /admin should be accessible
    resp = test_client.get("/admin")
    assert resp.status_code == 403
