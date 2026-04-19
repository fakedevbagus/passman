# API Documentation

This outlines the endpoints exposed by the backend for **Passman**.

## Base URL
`/api`

---

## 🔐 Auth Flow

Authentication operates on a **Bearer Token (JWT)** mechanism. Before authentication, the client computes an initial hash of the master password using PBKDF2/SHA-256. This is transmitted during signup/login and then re-hashed server-side via Argon2.

### `POST /auth/signup`
Creates a new vault user.

**Request:**
```json
{
  "email": "user@example.com",
  "master_password_hash": "$hash_version_from_client",
  "kdf_salt": "base64_encoded_random_salt"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "userId": "uuid-string",
  "token": "jwt-token"
}
```

### `POST /auth/login`
Authenticates a user.

**Request:**
```json
{
  "email": "user@example.com",
  "master_password_hash": "$hash_version_from_client"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "userId": "uuid-string",
  "salt": "base64_encoded_random_salt",
  "token": "jwt-token"
}
```

### `GET /auth/verify`
Checks token validity without regenerating it.
**Headers:** `Authorization: Bearer <token>`

**Response (200 OK):**
```json
{ "valid": true, "userId": "uuid-string" }
```

---

## 🗄️ Vault Management

All vault endpoints *require* an Authorization header.
**Headers:** `Authorization: Bearer <token>`

### `GET /vault`
Retrieves all assets managed by the user. Ordered by `favorite` then `updated_at`.

**Response (200 OK):**
```json
[
  {
    "id": "uuid-string",
    "service_name": "Google",
    "encrypted_data": "base64_encoded_ciphertext",
    "iv": "base64_init_vector",
    "category": "email",
    "notes": "encrypted_json_string",
    "favorite": true,
    "created_at": "date_string",
    "updated_at": "date_string"
  }
]
```

### `GET /vault/stats`
Retrieves aggregated statistics for the user's dashboard.

**Response (200 OK):**
```json
{
  "total": 10,
  "favorites": 2,
  "categories": [
    { "category": "email", "count": "1" }
  ],
  "recentActivity": [
    { "service_name": "GitHub", "updated_at": "date_string" }
  ]
}
```

### `POST /vault`
Creates a new asset securely. `encryptedData` and `notes` are assumed entirely encrypted.

**Request:**
```json
{
  "serviceName": "Netflix",
  "encryptedData": "ciphered_text",
  "iv": "ciphered_iv",
  "category": "other",
  "notes": "ciphered_notes_json"
}
```

### `PUT /vault/:id`
Updates an existing asset based on changes. Supports partial updates via `COALESCE` in SQL.

**Request:** *(Fields optional)*
```json
{
  "serviceName": "Netflix Updated",
  "encryptedData": "ciphered_text_new",
  "favorite": false
}
```

### `PATCH /vault/:id/favorite`
Toggles the favorite flag dynamically.

### `DELETE /vault/:id`
Permanently destroys the resource.
