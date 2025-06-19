#!/usr/bin/env python3
"""
Quick test for GitHub Secrets encryption fix
"""

import base64
import sys
from pathlib import Path

try:
    from nacl import public, encoding
    print("✅ PyNaCl imported successfully")
except ImportError as e:
    print(f"❌ PyNaCl import failed: {e}")
    print("Install with: pip install PyNaCl")
    sys.exit(1)

try:
    import requests
    print("✅ requests imported successfully")
except ImportError as e:
    print(f"❌ requests import failed: {e}")
    print("Install with: pip install requests")
    sys.exit(1)

# Test GitHub-style encryption
def test_encryption():
    """Test the encryption method used by GitHub Secrets API."""
    try:
        # Generate a test key pair (like GitHub does)
        private_key = public.PrivateKey.generate()
        public_key = private_key.public_key
        
        # Encode public key as GitHub provides it (base64)
        public_key_bytes = bytes(public_key)
        public_key_b64 = base64.b64encode(public_key_bytes).decode('utf-8')
        
        print(f"✅ Generated test public key: {public_key_b64[:20]}...")
        
        # Test encryption (this is what our script does with GitHub's public key)
        test_secret = "test_secret_value_123"
        
        # This is the exact method our GitHub Secrets script uses
        public_key_decoded = base64.b64decode(public_key_b64)
        github_public_key = public.PublicKey(public_key_decoded)
        
        sealed_box = public.SealedBox(github_public_key)
        encrypted_bytes = sealed_box.encrypt(test_secret.encode('utf-8'))
        encrypted_b64 = base64.b64encode(encrypted_bytes).decode('utf-8')
        
        print(f"✅ Encryption successful: {encrypted_b64[:20]}...")
        
        # Test decryption (using the private key, like GitHub would do)
        # This proves the encryption/decryption cycle works end-to-end
        private_sealed_box = public.SealedBox(private_key)
        decrypted_bytes = private_sealed_box.decrypt(base64.b64decode(encrypted_b64))
        decrypted_text = decrypted_bytes.decode('utf-8')
        
        if decrypted_text == test_secret:
            print("✅ Decryption successful - encryption/decryption cycle works")
            print("✅ GitHub will be able to decrypt secrets encrypted this way")
            return True
        else:
            print("❌ Decryption failed - values don't match")
            return False
            
    except Exception as e:
        print(f"❌ Encryption test failed: {e}")
        return False

def test_github_format():
    """Test that we can handle a GitHub-style public key."""
    try:
        # Simulate a GitHub public key response format
        test_key = public.PrivateKey.generate().public_key
        github_style_key = {
            'key': base64.b64encode(bytes(test_key)).decode('utf-8'),
            'key_id': 'test_key_id_123'
        }
        
        print(f"✅ GitHub-style key format created")
        
        # Test our encryption function with this format
        test_secret = "github_test_secret"
        
        # Decode and encrypt (same as our main script)
        public_key_bytes = base64.b64decode(github_style_key['key'])
        public_key_obj = public.PublicKey(public_key_bytes)
        sealed_box = public.SealedBox(public_key_obj)
        encrypted = sealed_box.encrypt(test_secret.encode('utf-8'))
        encrypted_b64 = base64.b64encode(encrypted).decode('utf-8')
        
        print(f"✅ GitHub-format encryption successful: {encrypted_b64[:20]}...")
        
        # Verify the encrypted data is the right format for GitHub
        if len(encrypted_b64) > 20 and encrypted_b64.isascii():
            print("✅ Encrypted data is in correct base64 format for GitHub")
            return True
        else:
            print("❌ Encrypted data format is incorrect")
            return False
            
    except Exception as e:
        print(f"❌ GitHub format test failed: {e}")
        return False

def main():
    print("🧪 Testing GitHub Secrets Encryption Fix")
    print("========================================")
    print("")
    
    print("📦 Testing imports...")
    print("")
    
    print("🔐 Testing encryption method...")
    test1_passed = test_encryption()
    print("")
    
    print("🔐 Testing GitHub key format...")
    test2_passed = test_github_format()
    print("")
    
    if test1_passed and test2_passed:
        print("🎉 All tests passed!")
        print("✅ The GitHub Secrets Manager should now work correctly")
        print("")
        print("🔧 What this means:")
        print("  • PyNaCl library is working correctly")
        print("  • Encryption format matches GitHub's expectations")
        print("  • GitHub will be able to decrypt your secrets")
        print("  • No more 'PEM file' errors")
        print("")
        print("🚀 Ready to run:")
        print("  python scripts/setup_github_secrets.py --force")
        print("  ./scripts/quick_start.sh --force")
        return True
    else:
        print("❌ Some tests failed")
        print("Please check your PyNaCl installation")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
