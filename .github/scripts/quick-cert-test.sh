#!/bin/bash
# Quick certificate validation script

PASSWORD="x2G2srk2RHtp"

echo "🔍 Quick Certificate Test"
echo "========================"
echo "Password: $PASSWORD"
echo ""

# Test app certificate
echo "Testing app_cert.p12..."
if openssl pkcs12 -in app_cert.p12 -noout -passin pass:"$PASSWORD" 2>/dev/null; then
    echo "✅ app_cert.p12 - VALID"
    # Show certificate details
    echo "Subject:"
    openssl pkcs12 -in app_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -subject
else
    echo "❌ app_cert.p12 - INVALID"
    echo "Full error:"
    openssl pkcs12 -in app_cert.p12 -noout -passin pass:"$PASSWORD"
fi

echo ""

# Test installer certificate  
echo "Testing installer_cert.p12..."
if openssl pkcs12 -in installer_cert.p12 -noout -passin pass:"$PASSWORD" 2>/dev/null; then
    echo "✅ installer_cert.p12 - VALID"
    # Show certificate details
    echo "Subject:"
    openssl pkcs12 -in installer_cert.p12 -nokeys -passin pass:"$PASSWORD" 2>/dev/null | openssl x509 -noout -subject
else
    echo "❌ installer_cert.p12 - INVALID"
    echo "Full error:"
    openssl pkcs12 -in installer_cert.p12 -noout -passin pass:"$PASSWORD"
fi

echo ""
echo "🔍 File sizes:"
ls -la *.p12

echo ""
echo "🔍 File types:"
file *.p12
