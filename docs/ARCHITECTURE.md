# Passman Monorepo Architecture

This document describes the flow of data, encryption protocols, and structural choices of the project.

## Monorepo Structure
Passman employs a folder-based monorepo layout, partitioned mainly into two standalone workspaces:
1. `client/` - A Next.js application representing the UI and Client-side Cryptographic Engine.
2. `server/` - A Node.js/Express application acting as a Zero-Knowledge backend that interfaces with PostgreSQL.

The root `package.json` orchestrates concurrent startup and package installations.

## Architecture Layers (Backend)
To provide maintainable business logic without over-engineering, the backend is split into:
- **API Controllers** (`src/api/*`): Solely responsible for mapping HTTP REST verbs to specific business processes and handling basic request validation.
- **Service Layer** (`src/services/*`): Implements domain-specific rules (e.g. rate-limiting attempts, cryptographic validation of Argon hashes, token signing).
- **Repository Pattern** (`src/repository/*`): Abstracts raw database connections. By using `vaultRepository` and `userRepository`, we keep `pool.query` SQL logic away from controllers and prevent SQL injection systematically.

## Encryption Flow & Data Path
Passman is a strict **Zero-Knowledge Architecture**.

1. **User Input:** User dictates a Master Password.
2. **Client KDF:** The client immediately processes the Key Derivation (`PBKDF2/SHA-256`, 600k iterations locally via WebCrypto APIs). This outputs a derived master key.
3. **Transmission:** 
   - Operations requiring encryption (saving a vault item) encode the payload using `AES-256-GCM` with the locally derived key.
   - Operations requiring authentication construct a hashed blob of the derived key to send as a login verification payload.
4. **Server Storage:** The server receives the AES-encrypted blobs perfectly encrypted. It derives an `Argon2` hash on the authentication token before placing it in the DB (double-hash technique avoiding rainbow table vulnerabilities on server leak).
5. **Retrieval:** The server returns ciphertext. The client validates the session, obtains the `salt`, reconstructs the PBKDF2 derived key locally, and securely decrypts the payload inside browser memory.

Data never hits Next.js servers (`SSR` is skipped for vault logic). Secrets never traverse network interfaces unencrypted.
