# Passman

Passman is a modern, zero-knowledge, enterprise-grade password manager. It is designed to ensure that your sensitive data never leaves your device unencrypted. With advanced cryptographic practices and a seamless, premium user interface, Passman redefines self-hosted password management.

## 🌟 Key Features

- **Zero-Knowledge Architecture:** Cryptographic keys are derived securely on the client. The server never sees your plaintext passwords.
- **Enterprise-grade Encryption:** Utilizes AES-256-GCM combined with PBKDF2/Argon2 for key derivation and data security.
- **Polished UI/UX:** A sleek modern interface featuring dynamic design, glassmorphism, responsive components, and fluid animations.
- **Auto-Locking Mechanism:** Intelligently protects your vault after periods of user inactivity.
- **Vault Organization:** Built-in password strength analyzer, robust password generator, categorized storage, favoring system, and encrypted vault notes.

## 🛠️ Tech Stack

### Frontend (Client)
- **Framework:** Next.js (React 19)
- **Language:** TypeScript
- **Styling:** Tailwind CSS V4
- **State/Querying:** React Query & Axios
- **Crypto:** Web Crypto API

### Backend (Server)
- **Runtime & Framework:** Node.js, Express.js
- **Language:** TypeScript
- **Database:** PostgreSQL (using `pg`)
- **Crypto & Security:** Argon2 (password hashing), JWT

## 🚀 How to Run Locally

### Prerequisites

- Node.js (v20+)
- PostgreSQL (v12+)
- NPM

### 1. Database Setup
Create a local PostgreSQL database for the password manager:
```sql
CREATE DATABASE passman_db;
```

### 2. Environment Setup
In the `server` directory, create a `.env` file from the example or use:
```env
PORT=3001
DATABASE_URL=postgres://username:password@localhost:5432/passman_db
JWT_SECRET=super_secret_jwt_key_example
FRONTEND_URL=http://localhost:3000
```
In the `client` directory, you can optionally create a `.env.local`:
```env
NEXT_PUBLIC_API_URL=http://localhost:3001
```

### 3. Install Dependencies
From the root directory, install all required dependencies across the monorepo:
```bash
npm run install:all
```

### 4. Start the Application
You can run both the server and the frontend concurrently from the root directory:
```bash
npm run dev
```

- **Frontend:** http://localhost:3000
- **Backend API:** http://localhost:3001

## 📁 Folder Structure Explanation

```
passman/
├── client/                 # Next.js Frontend Application
│   ├── src/app/            # App Router (pages and layouts)
│   ├── src/components/     # Reusable UI elements (Dashboard, Vault, etc.)
│   └── src/lib/            # Utility functions (crypto engine, api client)
│
├── server/                 # Express Backend Application
│   ├── src/api/            # API Route Controllers (auth, vault)
│   ├── src/config/         # App configs and environment loading
│   ├── src/lib/            # DB Connection and Initialization
│   ├── src/middleware/     # Security and auth verification
│   └── src/repository/     # Database logic layer
│
├── docs/                   # Additional documentation
│   ├── DEV_GUIDE.md        # Contributions and coding standards
│   └── API_DOCS.md         # Full REST API references
│
└── package.json            # Root configuration for monorepo scripts
```

## Security Best Practices

Because this handles security-critical data, **do NOT lower the KDF iterations** or **downgrade AES settings** unless strictly necessary for compatibility on extremely old devices. This codebase automatically upgrades older password hashes internally to maintain high standards.
