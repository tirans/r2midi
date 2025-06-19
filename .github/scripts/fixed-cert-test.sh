#!/bin/bash
# Fixed certificate validation script with OpenSSL 3.x compatibility

PASSWORD="x2G2srk2RHtp"

echo "🔍 Fixed Certificate Test (OpenSSL 3.x Compatible)"
echo "=================================================="
echo "Password: $PASSWORD"
echo ""

# Check OpenSSL version
echo "🔍 OpenSSL version:"
openssl version
echo ""

# Test app certificate with legacy provider
echo "Testing app_cert.p12 with legacy provider..."
if openssl pkcs12 -legacy -in app_cert.p12 -noout -passin pass:"$PASSWORD" 2>/dev/null; then
    echo "✅ app_cert.p12 - VALID (with legacy provider)"
    # Show certificate details
    echo "Subject:"
    openssl pkcs12 -legacy -in app_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -subject
    echo "Issuer:"
    openssl pkcs12 -legacy -in app_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -issuer
else
    echo "❌ app_cert.p12 - STILL INVALID even with legacy provider"
    echo "Full error:"
    openssl pkcs12 -legacy -in app_cert.p12 -noout -passin pass:"$PASSWORD"
fi

echo ""

# Test installer certificate with legacy provider
echo "Testing installer_cert.p12 with legacy provider..."
if openssl pkcs12 -legacy -in installer_cert.p12 -noout -passin pass:"$PASSWORD" 2>/dev/null; then
    echo "✅ installer_cert.p12 - VALID (with legacy provider)"
    # Show certificate details
    echo "Subject:"
    openssl pkcs12 -legacy -in installer_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -subject
    echo "Issuer:"
    openssl pkcs12 -legacy -in installer_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -issuer
else
    echo "❌ installer_cert.p12 - STILL INVALID even with legacy provider"
    echo "Full error:"
    openssl pkcs12 -legacy -in installer_cert.p12 -noout -passin pass:"$PASSWORD"
fi

echo ""

# Alternative: Try using system OpenSSL instead of Homebrew
echo "🔍 Trying with system OpenSSL..."
if [ -f "/usr/bin/openssl" ]; then
    echo "Testing with system OpenSSL:"
    /usr/bin/openssl version
    
    echo "Testing app_cert.p12 with system OpenSSL:"
    if /usr/bin/openssl pkcs12 -in app_cert.p12 -noout -passin pass:"$PASSWORD" 2>/dev/null; then
        echo "✅ app_cert.p12 - VALID with system OpenSSL"
    else
        echo "❌ app_cert.p12 - INVALID with system OpenSSL"
    fi
else
    echo "System OpenSSL not found at /usr/bin/openssl"
fi

echo ""
echo "🔧 If certificates are valid with -legacy flag, updating scripts..."
