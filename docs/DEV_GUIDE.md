# Development Guide

Welcome to the **Passman** developer documentation. This guide details how to contribute, the coding standards used, and provides an explanation of the core architecture.

## 🤝 How to Contribute

1. **Create an Issue:** Check existing issues or open a new one to discuss proposed changes.
2. **Branch Naming:** Create a new branch for your feature or bug fix:
   - `feature/your-feature-name`
   - `fix/your-bugfix-name`
   - `docs/your-doc-update`
3. **Draft a PR:** Provide clear documentation regarding what your Pull Request achieves.
4. **Test:** Validate that your code does not break the Zero-Knowledge crypto engine or API routing. Ensure that you have manually tested your changes on frontend.

## 🎨 Coding Standards

### General Standards
- **TypeScript First:** We exclusively use TypeScript. Try avoiding `any` types when strict typing (interfaces, classes, record types) can be clearly defined.
- **Clean Architecture:** Rely heavily on clear separation of concerns (e.g. `api/` controllers should pass data queries to `repository/`).
- **Formatting:** ESLint and standard typescript configurations should pass without errors before a commit.

### Security Standards
- **Wait before logging:** Never log plaintext master passwords, encryption keys, or initialization vectors inside the console. Logs should strictly contain action audits and metadata (e.g. "User logged in").
- **Client-Side Crypto:** Always ensure `deriveKey` and `encryptData` are executing on the *frontend* before posting data to the API.

## 🧠 Architecture Explanation

The monorepo applies a simplified but scalable clean architecture using two independent packages.

### 1. Client Architecture
The Next.js client handles data manipulation and rendering simultaneously. 
- **Vault Logic:** Handled within `VaultList` and `AddVaultItem`. 
- **Encryption Engine (`lib/crypto.ts`):** We use `window.crypto.subtle` for fast, native AES-256-GCM encryption. Master passwords are run through PBKDF2 with 600,000 iterations to derive secure encryption keys natively. 
- **API Engine (`lib/api.ts`):** Uses Axios interceptors to automatically connect tokens and route responses securely.

### 2. server Architecture
The backend Express app serves primarily as an unprivileged datastore. It stores encrypted blocks but has no capacity to decrypt them.
- **`/api` (Controllers):** Pure routing logic processing incoming parameters and authenticating requests via JWT.
- **`/repository` (Data Layer):** Interacts natively with PostgreSQL via `pg`. Decouples direct SQL syntax from the controller space.
- **Authentication:** For user authentication, initial hashing occurs on the frontend, which is then double-hashed securely using Argon2 before hitting the database table. This prevents collision issues and dictionary attacks even if the database is leaked.
