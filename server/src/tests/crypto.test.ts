import test from 'node:test';
import assert from 'node:assert';
import argon2 from 'argon2';

test('Password Manager Cryptography (Server)', async (t) => {
  await t.test('Argon2 should correctly hash and verify master passwords', async () => {
    // Simulated input from client
    const clientHashedPassword = "sha256_mock_hash_string";
    
    // Server hashes it again
    const hash = await argon2.hash(clientHashedPassword, {
        type: argon2.argon2id,
        memoryCost: 4096, // Reduced for test speed
        timeCost: 3,
        parallelism: 1,
    });

    assert.ok(hash.startsWith('$argon2id$'), 'Should produce a valid Argon2 hash');

    // Verification
    const isValid = await argon2.verify(hash, clientHashedPassword);
    assert.strictEqual(isValid, true, 'Verification of correct password should succeed');

    // Wrong verification
    const isInvalid = await argon2.verify(hash, "wrong_password");
    assert.strictEqual(isInvalid, false, 'Verification of incorrect password should fail');
  });
});
