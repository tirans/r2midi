#!/bin/bash

echo "🔍 Testing P12 certificates..."
echo "=============================="
echo ""

PASSWORD="x2G2srk2RHtp"

# Check if files exist
echo "📁 Checking files:"
if [ -f "app_cert.p12" ]; then
    echo "✅ app_cert.p12 exists ($(wc -c < app_cert.p12) bytes)"
else
    echo "❌ app_cert.p12 not found"
    exit 1
fi

if [ -f "installer_cert.p12" ]; then
    echo "✅ installer_cert.p12 exists ($(wc -c < installer_cert.p12) bytes)"
else
    echo "❌ installer_cert.p12 not found"
    exit 1
fi

echo ""

# Test app certificate
echo "🔐 Testing app_cert.p12 with password..."
if openssl pkcs12 -in app_cert.p12 -noout -passin pass:"$PASSWORD" 2>/dev/null; then
    echo "✅ app_cert.p12 - Password is VALID"
    
    # Get certificate details
    echo "📋 Certificate details:"
    openssl pkcs12 -in app_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null
    
else
    echo "❌ app_cert.p12 - Password validation FAILED"
    echo "Detailed error:"
    openssl pkcs12 -in app_cert.p12 -noout -passin pass:"$PASSWORD" 2>&1
fi

echo ""

# Test installer certificate
echo "🔐 Testing installer_cert.p12 with password..."
if openssl pkcs12 -in installer_cert.p12 -noout -passin pass:"$PASSWORD" 2>/dev/null; then
    echo "✅ installer_cert.p12 - Password is VALID"
    
    # Get certificate details
    echo "📋 Certificate details:"
    openssl pkcs12 -in installer_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null
    
else
    echo "❌ installer_cert.p12 - Password validation FAILED"
    echo "Detailed error:"
    openssl pkcs12 -in installer_cert.p12 -noout -passin pass:"$PASSWORD" 2>&1
fi

echo ""

# Test alternative password possibilities
echo "🔍 Testing common password variations..."

# Test empty password
echo "Testing empty password..."
if openssl pkcs12 -in app_cert.p12 -noout -passin pass:"" 2>/dev/null; then
    echo "⚠️ app_cert.p12 has EMPTY password!"
fi

# Test without password (prompted)
echo "Testing if certificates require no password..."
if openssl pkcs12 -in app_cert.p12 -noout -nodes 2>/dev/null; then
    echo "⚠️ app_cert.p12 might not require a password"
fi

echo ""
echo "🔍 Certificate file format verification..."

# Check if files are valid PKCS#12 format
echo "Checking file format with 'file' command:"
file app_cert.p12
file installer_cert.p12

echo ""
echo "Checking file headers (hex dump):"
echo "app_cert.p12 header:"
hexdump -C app_cert.p12 | head -3

echo "installer_cert.p12 header:"
hexdump -C installer_cert.p12 | head -3
