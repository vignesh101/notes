# Technical Specification Document
## Visa Direct API Simulation — mTLS + MLE

**Version:** 1.0.0
**Date:** 2025
**Status:** Final
**Author:** Vignesh

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [System Architecture](#2-system-architecture)
3. [Technology Stack](#3-technology-stack)
4. [Module Breakdown](#4-module-breakdown)
   - 4.1 [visa-server](#41-visa-server)
   - 4.2 [visa-client](#42-visa-client)
5. [Security Architecture](#5-security-architecture)
   - 5.1 [Layer 1 — Mutual TLS (mTLS)](#51-layer-1--mutual-tls-mtls)
   - 5.2 [Layer 2 — HTTP Basic Authentication](#52-layer-2--http-basic-authentication)
   - 5.3 [Layer 3 — Message Level Encryption (MLE)](#53-layer-3--message-level-encryption-mle)
6. [Certificate and Key Infrastructure (PKI)](#6-certificate-and-key-infrastructure-pki)
7. [API Specification](#7-api-specification)
   - 7.1 [Push Funds Transaction (OCT)](#71-push-funds-transaction-oct)
   - 7.2 [Transaction Query](#72-transaction-query)
8. [Data Flow — End to End](#8-data-flow--end-to-end)
9. [Component-Level Design](#9-component-level-design)
   - 9.1 [MLEService (Server)](#91-mleservice-server)
   - 9.2 [MLEService (Client)](#92-mleservice-client)
   - 9.3 [FundsTransferController](#93-fundstransfercontroller)
   - 9.4 [TransactionStore](#94-transactionstore)
   - 9.5 [VisaApiService](#95-visaapiservice)
   - 9.6 [SSLConfig](#96-sslconfig)
   - 9.7 [SecurityConfig](#97-securityconfig)
10. [Configuration Reference](#10-configuration-reference)
11. [JWE Internals — Technical Deep Dive](#11-jwe-internals--technical-deep-dive)
12. [Key Rotation Design](#12-key-rotation-design)
13. [Certificate Generation](#13-certificate-generation)
14. [Error Handling](#14-error-handling)
15. [Sequence Diagrams](#15-sequence-diagrams)
16. [Dependency Reference](#16-dependency-reference)
17. [Directory Structure](#17-directory-structure)
18. [Security Assumptions and Limitations](#18-security-assumptions-and-limitations)

---

## 1. Project Overview

This project is a **production-grade simulation of the Visa Direct API** implemented as two independent Spring Boot applications. It demonstrates how financial institutions integrate with Visa's payment network using the exact security protocols mandated by Visa:

- **Mutual TLS (mTLS)** for transport-layer authentication
- **HTTP Basic Authentication** for application-layer identity
- **Message Level Encryption (MLE)** using JWE for payload-level confidentiality

The system simulates two core Visa Direct operations:

| Operation | HTTP Method | Description |
|-----------|-------------|-------------|
| Push Funds Transaction (OCT) | POST | Transfer money to a recipient card |
| Transaction Query | GET | Retrieve status of a previously submitted transaction |

The project mirrors the coding patterns found in Visa's official SDK sample code (`PushFundsAndQueryAPIWithMLE`) but replaces the live Visa sandbox (`sandbox.api.visa.com`) with a locally running server.

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        visa-client                              │
│                   Spring Boot (port 8080)                       │
│                                                                 │
│  VisaClientApplication (CommandLineRunner)                      │
│       │                                                         │
│       ├── VisaApiService         (orchestrates calls)           │
│       ├── MLEService (client)    (JWE encrypt/decrypt)          │
│       └── SSLConfig              (mTLS SSLContext)              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                    HTTPS (mTLS)
                    TLSv1.2 / TLSv1.3
                    Basic Auth header
                    {"encData": "<JWE>"}
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                        visa-server                              │
│                   Spring Boot (port 8443)                       │
│                                                                 │
│  FundsTransferController   (REST endpoints)                     │
│       │                                                         │
│       ├── SecurityConfig         (Basic Auth filter)            │
│       ├── MLEService (server)    (JWE encrypt/decrypt)          │
│       └── TransactionStore       (in-memory storage)            │
└─────────────────────────────────────────────────────────────────┘
```

Both applications are **stateless** — no HTTP sessions or cookies are created. Every request carries its own authentication credentials and encryption keys.

---

## 3. Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Java | 17+ |
| Framework | Spring Boot | 3.2.5 |
| Build Tool | Apache Maven | 3.x |
| JWE (MLE) | Nimbus JOSE+JWT | 9.37.3 |
| RSA Key Parsing | Bouncy Castle | 1.77 (bcprov-jdk18on) |
| Security Framework | Spring Security | 6.x (via Boot 3.2.5) |
| TLS Runtime | Java TLS (JSSE) | Built-in |
| HTTP Client | java.net.HttpURLConnection | Built-in JDK |
| JSON Processing | Jackson (via Spring Boot) | 2.x |
| Certificate Tooling | OpenSSL + Java Keytool | System |

---

## 4. Module Breakdown

### 4.1 visa-server

**Purpose:** HTTPS REST server that simulates Visa's payment API endpoint.

**Maven artifact:** `com.visa:visa-server:1.0.0`

```
visa-server/
├── pom.xml
└── src/main/
    ├── java/com/visa/server/
    │   ├── VisaServerApplication.java
    │   ├── config/
    │   │   └── SecurityConfig.java
    │   ├── controller/
    │   │   └── FundsTransferController.java
    │   ├── model/
    │   │   └── EncryptedPayload.java
    │   └── service/
    │       ├── MLEService.java
    │       └── TransactionStore.java
    └── resources/
        └── application.yml
```

**Startup:** Listens on HTTPS port `8443`. On boot, `MLEService.init()` (annotated `@PostConstruct`) loads the RSA private key and client public cert into memory. Spring Security registers the Basic Auth filter with BCrypt-hashed credentials.

---

### 4.2 visa-client

**Purpose:** Spring Boot application that drives the demo flow — calls visa-server using mTLS + MLE.

**Maven artifact:** `com.visa:visa-client:1.0.0`

```
visa-client/
├── pom.xml
└── src/main/
    ├── java/com/visa/client/
    │   ├── VisaClientApplication.java
    │   ├── config/
    │   │   └── SSLConfig.java
    │   ├── model/
    │   │   └── EncryptedPayload.java
    │   └── service/
    │       ├── MLEService.java
    │       └── VisaApiService.java
    └── resources/
        └── application.yml
```

**Startup:** Runs on HTTP port `8080`. On boot, `SSLConfig.sslContext()` constructs a mutual-auth `SSLContext` from the PKCS12 keystore and truststore. `MLEService` loads RSA keys. The `CommandLineRunner` in `VisaClientApplication` fires automatically after context initialization and executes:

1. `pushFunds()` — OCT (Original Credit Transaction)
2. `queryTransaction()` — lookup the previously submitted transaction

---

## 5. Security Architecture

The system enforces a **three-layer nested security model**. Each layer is independent — a breach of one layer does not compromise the others.

```
┌───────────────────────────────────────────────────────────────┐
│  Layer 3 — MLE (Payload)                                      │
│  {"encData": "eyJhbGci..."}                                   │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Layer 2 — Basic Auth (Identity Header)                 │  │
│  │  Authorization: Basic <base64(userId:password)>         │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │  Layer 1 — mTLS (Transport)                       │  │  │
│  │  │  TLS 1.2 / 1.3 with mutual X.509 certificates    │  │  │
│  │  └───────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

---

### 5.1 Layer 1 — Mutual TLS (mTLS)

**What it protects:** Transport channel — encrypts all bytes on the wire, and ensures both parties are who they claim to be at the network level.

**Standard TLS vs mTLS:**

| Aspect | TLS | mTLS |
|--------|-----|------|
| Server presents cert | Yes | Yes |
| Client presents cert | No | **Yes** |
| Server verifies client | No | **Yes** |

**Configuration (server-side `application.yml`):**

```yaml
server:
  ssl:
    enabled: true
    key-store: file:.../certs/server-keystore.p12
    key-store-password: changeit
    key-store-type: PKCS12
    key-alias: server
    client-auth: need                              # enforces mTLS
    trust-store: file:.../certs/server-truststore.p12
    trust-store-password: changeit
    trust-store-type: PKCS12
    protocol: TLS
    enabled-protocols: TLSv1.2,TLSv1.3
```

`client-auth: need` instructs Spring Boot's embedded Tomcat to reject any connection that does not present a valid X.509 certificate signed by the configured CA.

**Client-side configuration (`SSLConfig.java`):**

```java
// 1. Load client keystore (client cert + private key)
KeyStore keyStore = KeyStore.getInstance("PKCS12");
keyStore.load(new FileInputStream(keyStorePath), keyStorePassword.toCharArray());
KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
kmf.init(keyStore, keyStorePassword.toCharArray());

// 2. Load truststore (CA cert to verify server)
KeyStore trustStore = KeyStore.getInstance("PKCS12");
trustStore.load(new FileInputStream(trustStorePath), trustStorePassword.toCharArray());
TrustManagerFactory tmf = TrustManagerFactory.getInstance("PKIX");
tmf.init(trustStore);

// 3. Build SSLContext
SSLContext sslContext = SSLContext.getInstance("TLS");
sslContext.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);
```

The resulting `SSLContext` bean is injected into `VisaApiService` and applied per-connection:

```java
if (con instanceof HttpsURLConnection httpsConn) {
    httpsConn.setSSLSocketFactory(sslContext.getSocketFactory());
}
```

**TLS Handshake Sequence:**

```
Client                                  Server
  │                                        │
  │──── ClientHello ──────────────────────►│
  │     (TLS versions, cipher suites)      │
  │                                        │
  │◄─── ServerHello ───────────────────────│
  │◄─── Certificate (server cert) ─────────│
  │◄─── CertificateRequest ────────────────│  ← mTLS-specific
  │◄─── ServerHelloDone ───────────────────│
  │                                        │
  │──── Certificate (client cert) ────────►│
  │──── ClientKeyExchange ────────────────►│
  │──── CertificateVerify ────────────────►│
  │──── ChangeCipherSpec ─────────────────►│
  │──── Finished ─────────────────────────►│
  │                                        │
  │◄─── ChangeCipherSpec ───────────────────│
  │◄─── Finished ───────────────────────────│
  │                                        │
  │════ Encrypted Application Data ════════│
```

**Certificate chain:**

```
Visa Local CA (ca.crt)
    ├── server-tls.crt  (CN=localhost,  SAN=DNS:localhost,IP:127.0.0.1)
    └── client-tls.crt  (CN=visa-client)
```

---

### 5.2 Layer 2 — HTTP Basic Authentication

**What it protects:** Application-level identity. Verifies the caller has valid API credentials, separate from the TLS certificate.

**Implementation (`SecurityConfig.java`):**

```java
@Bean
public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
    http
        .csrf(csrf -> csrf.disable())
        .sessionManagement(session ->
            session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
        .httpBasic(basic -> {});
    return http.build();
}

@Bean
public UserDetailsService userDetailsService(PasswordEncoder encoder) {
    var user = User.builder()
            .username(userId)
            .password(encoder.encode(password))  // BCrypt hashed
            .roles("API_USER")
            .build();
    return new InMemoryUserDetailsManager(user);
}

@Bean
public PasswordEncoder passwordEncoder() {
    return new BCryptPasswordEncoder();
}
```

**Key design decisions:**

| Decision | Rationale |
|----------|-----------|
| `SessionCreationPolicy.STATELESS` | No server-side session; every request re-authenticates |
| BCrypt password encoding | Salted hash — not stored plain-text even in memory |
| CSRF disabled | REST APIs using Basic Auth + stateless sessions are not vulnerable to CSRF |
| `InMemoryUserDetailsManager` | Sufficient for this simulation; production would use a DB or LDAP |

**Client-side credential injection (`VisaApiService.java`):**

```java
byte[] encodedAuth = Base64.getEncoder().encode(
    (userId + ":" + password).getBytes(StandardCharsets.UTF_8));
con.setRequestProperty("Authorization", "Basic " + new String(encodedAuth));
```

**Credentials:**

| Field | Value |
|-------|-------|
| userId | `1WM2TT4IHPXC8DQ5I3CH21n1rEBGK-Eyv_oLdzE2VZpDqRn_U` |
| password | `19JRVdej9` |

---

### 5.3 Layer 3 — Message Level Encryption (MLE)

**What it protects:** The JSON payload — ensures payload confidentiality even if TLS is terminated at an intermediate proxy, load balancer, or API gateway. This is the primary protection mandated by Visa for PCI-DSS scope data (cardholder PANs, amounts, etc.).

**Algorithm:** JWE (JSON Web Encryption) — RFC 7516

| Parameter | Value | Role |
|-----------|-------|------|
| `alg` | `RSA-OAEP-256` | Key wrapping: RSA with OAEP padding using SHA-256 |
| `enc` | `A128GCM` | Content encryption: AES-128 in GCM mode |
| `kid` | `7f591161-6b5f-4136-80b8-2ae8a44ad9eb` | Key identifier for rotation support |
| `iat` | `System.currentTimeMillis()` | Issued-at timestamp (ms) — anti-replay |

**Wire format:**

The encrypted payload is transmitted as:
```json
{
  "encData": "<JWE compact serialization>"
}
```

Where JWE compact serialization is:
```
Base64URL(Header) . Base64URL(EncryptedKey) . Base64URL(IV) . Base64URL(Ciphertext) . Base64URL(AuthTag)
```

**Key assignment by direction:**

| Direction | Encrypt With | Decrypt With | Rationale |
|-----------|-------------|-------------|-----------|
| Client → Server (Request) | `mle-server-public.pem` | `mle-server-private.pem` | Only server can read the request |
| Server → Client (Response) | `mle-client-public.pem` | `mle-client-private.pem` | Only client can read the response |

This asymmetric assignment means **each party can only decrypt messages intended for them**.

---

## 6. Certificate and Key Infrastructure (PKI)

### 6.1 File Inventory

| File | Format | Used By | Purpose |
|------|--------|---------|---------|
| `ca.crt` | X.509 PEM | Both | Root CA — trust anchor |
| `server-keystore.p12` | PKCS12 | Server | Server TLS cert + private key |
| `server-truststore.p12` | PKCS12 | Server | CA cert to verify client TLS certs |
| `client-keystore.p12` | PKCS12 | Client | Client TLS cert + private key |
| `client-truststore.p12` | PKCS12 | Client | CA cert to verify server TLS cert |
| `mle-server-private.pem` | RSA PKCS#1 | Server | MLE: decrypt incoming requests |
| `mle-server-public.pem` | X.509 PEM | Client | MLE: encrypt outgoing requests |
| `mle-client-private.pem` | RSA PKCS#1 | Client | MLE: decrypt incoming responses |
| `mle-client-public.pem` | X.509 PEM | Server | MLE: encrypt outgoing responses |

### 6.2 Trust Relationships

```
mTLS Trust:
  ca.crt ──signs──► server-tls.crt   (in server-keystore.p12)
  ca.crt ──signs──► client-tls.crt   (in client-keystore.p12)

  server-truststore.p12 contains ca.crt → verifies client-tls.crt
  client-truststore.p12 contains ca.crt → verifies server-tls.crt

MLE Trust (direct key exchange, no CA chain):
  mle-server-private.pem  ←paired→  mle-server-public.pem
  mle-client-private.pem  ←paired→  mle-client-public.pem
```

### 6.3 Certificate Properties

| Certificate | Subject CN | Key Usage | Extended Key Usage | SAN |
|-------------|-----------|-----------|-------------------|-----|
| CA | Visa Local CA | Certificate Sign, CRL Sign | — | — |
| Server TLS | localhost | Digital Signature, Key Encipherment | serverAuth | DNS:localhost, IP:127.0.0.1 |
| Client TLS | visa-client | Digital Signature, Key Encipherment | clientAuth | — |
| MLE Server | mle-server | — | — | — |
| MLE Client | mle-client | — | — | — |

**Key parameters:**
- Algorithm: RSA-2048 for all keys
- Validity: 365 days from generation
- Keystore password: `changeit`
- Private key format for MLE: PKCS#1 (`-----BEGIN RSA PRIVATE KEY-----`)

---

## 7. API Specification

### 7.1 Push Funds Transaction (OCT)

**Endpoint:** `POST /visadirect/fundstransfer/v1/pushfundstransactions`

**Description:** Submits an Original Credit Transaction (OCT) — pushes funds to a recipient's card account.

**Request Headers:**

| Header | Type | Required | Example |
|--------|------|----------|---------|
| `Authorization` | Basic Auth | Yes | `Basic <base64(userId:password)>` |
| `Content-Type` | string | Yes | `application/json` |
| `keyId` | UUID string | Yes | `7f591161-6b5f-4136-80b8-2ae8a44ad9eb` |

**Request Body (encrypted):**

```json
{
  "encData": "<JWE compact serialization of request payload>"
}
```

**Decrypted Request Payload (example):**

```json
{
  "amount": "124.05",
  "senderAddress": "901 Metro Center Blvd",
  "localTransactionDateTime": "2025-01-15T10:30:00",
  "pointOfServiceData": {
    "panEntryMode": "90",
    "posConditionCode": "00",
    "motoECIIndicator": "0"
  },
  "recipientPrimaryAccountNumber": "4957030420210496",
  "cardAcceptor": {
    "address": {
      "country": "USA",
      "zipCode": "94404",
      "county": "San Mateo",
      "state": "CA"
    },
    "idCode": "CA-IDCode-77765",
    "name": "Visa Inc. USA-Foster City",
    "terminalId": "TID-9999"
  },
  "transactionIdentifier": "381228649430015",
  "acquirerCountryCode": "840",
  "acquiringBin": "408999",
  "retrievalReferenceNumber": "412770451018",
  "senderCity": "Foster City",
  "senderStateCode": "CA",
  "systemsTraceAuditNumber": "451018",
  "senderName": "Mohammed Qasim",
  "businessApplicationId": "AA",
  "settlementServiceIndicator": "9",
  "merchantCategoryCode": "6012",
  "transactionCurrencyCode": "USD",
  "recipientName": "rohan",
  "senderCountryCode": "124",
  "sourceOfFundsCode": "05",
  "senderAccountNumber": "4653459515756154"
}
```

**Response Body (encrypted):**

```json
{
  "encData": "<JWE compact serialization of response payload>"
}
```

**Decrypted Response Payload:**

```json
{
  "transactionIdentifier": "381228649430015",
  "actionCode": "00",
  "approvalCode": "123456",
  "responseCode": "5",
  "transmissionDateTime": "2025-01-15T10:30:01",
  "amount": "124.05",
  "recipientPrimaryAccountNumber": "4957****0496",
  "senderName": "Mohammed Qasim",
  "recipientName": "rohan",
  "merchantCategoryCode": "6012",
  "acquiringBin": "408999",
  "feeProgramIndicator": "123"
}
```

**Response Codes:**

| `actionCode` | Meaning |
|------------|---------|
| `00` | Approved |

**HTTP Status Codes:**

| Status | Meaning |
|--------|---------|
| `200 OK` | Transaction processed successfully |
| `401 Unauthorized` | Invalid Basic Auth credentials |
| `500 Internal Server Error` | Processing error (MLE failure, parse error) |

---

### 7.2 Transaction Query

**Endpoint:** `GET /visadirect/v1/transactionquery`

**Description:** Retrieves the status and details of a previously submitted Push Funds transaction.

**Request Headers:**

| Header | Type | Required | Example |
|--------|------|----------|---------|
| `Authorization` | Basic Auth | Yes | `Basic <base64(userId:password)>` |
| `keyId` | UUID string | Yes | `7f591161-6b5f-4136-80b8-2ae8a44ad9eb` |

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `acquiringBIN` | string | Yes | Acquiring BIN (e.g., `408999`) |
| `transactionIdentifier` | string | Yes | Transaction ID from OCT response |

**No encrypted request body for GET** — query parameters are passed in the URL.

**Response Body (encrypted):**

```json
{
  "encData": "<JWE compact serialization of response payload>"
}
```

**Decrypted Response — Found:**

```json
{
  "statusIdentifier": "COMPLETED",
  "transactionIdentifier": "381228649430015",
  "acquiringBin": "408999",
  "actionCode": "00",
  "approvalCode": "123456",
  "responseCode": "5",
  "transmissionDateTime": "2025-01-15T10:30:01",
  "originalAmount": "124.05",
  "recipientPrimaryAccountNumber": "4957****0496"
}
```

**Decrypted Response — Not Found:**

```json
{
  "statusIdentifier": "NOT_FOUND",
  "transactionIdentifier": "381228649430015",
  "acquiringBin": "408999",
  "errorMessage": "Transaction not found"
}
```

---

## 8. Data Flow — End to End

```
visa-client (port 8080)                        visa-server (port 8443)
─────────────────────────────────────────────────────────────────────

1. BUILD PLAIN JSON PAYLOAD
   {amount, senderName, recipientPAN, ...}
             │
             ▼
2. MLE ENCRYPT (client MLEService)
   - Key: mle-server-public.pem
   - Algo: RSA-OAEP-256 + A128GCM
   - JWE header: {alg, enc, kid, iat}
   - Output: {"encData": "eyJhbGci..."}
             │
             ▼
3. BUILD HTTP REQUEST
   - Method: POST
   - URL: https://localhost:8443/visadirect/...
   - Header: Authorization: Basic <base64>
   - Header: keyId: 7f591161-...
   - Header: Content-Type: application/json
   - Body: {"encData": "eyJhbGci..."}
             │
             ▼
4. mTLS HANDSHAKE
   - Client presents client-keystore.p12 cert
   - Server verifies against server-truststore.p12 (CA)
   - Client verifies server cert against client-truststore.p12 (CA)
   - Session keys derived; channel encrypted
             │
             │   ════ TLS Encrypted Tunnel ════
             │
             ▼
5. SERVER: mTLS VERIFICATION (Tomcat)
   - Validates client X.509 cert chain to CA
   - Rejects if cert is invalid/expired/untrusted
             │
             ▼
6. SERVER: BASIC AUTH CHECK (Spring Security)
   - Decodes Authorization header
   - BCrypt.matches(inputPassword, storedHash)
   - Returns 401 if invalid
             │
             ▼
7. SERVER: MLE DECRYPT (server MLEService)
   - Key: mle-server-private.pem
   - Parses JWE compact serialization
   - Decrypts CEK with RSA private key
   - Decrypts ciphertext with AES-128-GCM
   - Returns plain JSON payload
             │
             ▼
8. SERVER: PROCESS TRANSACTION (FundsTransferController)
   - Parses JSON into Map<String, Object>
   - Generates approval code (6 digits)
   - Masks PAN (first 4 + **** + last 4)
   - Stores in TransactionStore (ConcurrentHashMap)
   - Builds response Map
             │
             ▼
9. SERVER: MLE ENCRYPT RESPONSE (server MLEService)
   - Key: mle-client-public.pem
   - Algo: RSA-OAEP-256 + A128GCM
   - Returns {"encData": "eyJhbGci..."}
             │
             │   ════ TLS Encrypted Tunnel ════
             │
             ▼
10. CLIENT: MLE DECRYPT RESPONSE (client MLEService)
    - Key: mle-client-private.pem
    - Returns decrypted response JSON
             │
             ▼
11. CLIENT: DISPLAY RESULTS
    Transaction ID, Action Code, Approval Code, Amount, Masked PAN
```

---

## 9. Component-Level Design

### 9.1 MLEService (Server)

**Package:** `com.visa.server.service`
**Annotation:** `@Service`

**Fields loaded at startup (`@PostConstruct`):**

| Field | Type | Loaded From |
|-------|------|------------|
| `serverPrivateKey` | `PrivateKey` | `mle-server-private.pem` (PKCS#1 RSA) |
| `clientPublicKey` | `RSAPublicKey` | `mle-client-public.pem` (X.509 cert) |
| `keyId` | `String` | `application.yml` → `mle.key-id` |

**Methods:**

```
decryptPayload(String jweToken) → String
  └─ JWEObject.parse(jweToken)
  └─ jweObject.decrypt(new RSADecrypter(serverPrivateKey))
  └─ return jweObject.getPayload().toString()

encryptPayload(String plaintext) → String
  └─ Build JWEHeader {alg=RSA_OAEP_256, enc=A128GCM, kid, iat}
  └─ new JWEObject(header, new Payload(plaintext))
  └─ jweObject.encrypt(new RSAEncrypter(clientPublicKey))
  └─ return jweObject.serialize()
```

**Key loading — PKCS#1 private key parsing (via BouncyCastle):**

```
PEM content → strip headers → Base64 decode → raw DER bytes
DER bytes → ASN1Sequence.fromByteArray()
ASN1Sequence contains (per RFC 3447 RSAPrivateKey):
  [0] version        (INTEGER, must be 0)
  [1] modulus        (INTEGER)
  [2] publicExponent (INTEGER)  ← skipped
  [3] privateExponent(INTEGER)  ← extracted
  ...
RSAPrivateKeySpec(modulus, privateExponent)
KeyFactory.getInstance("RSA").generatePrivate(spec)
```

**Why BouncyCastle?** Java's standard `KeyFactory` does not natively parse PKCS#1 format (it only understands PKCS#8). BouncyCastle's ASN1 parser reads the raw DER structure of a PKCS#1 key to manually reconstruct the `RSAPrivateKeySpec`.

---

### 9.2 MLEService (Client)

**Package:** `com.visa.client.service`
**Annotation:** `@Service`

Mirror of server's MLEService with reversed key assignment:

| Field | Type | Loaded From |
|-------|------|------------|
| `serverPublicKey` | `RSAPublicKey` | `mle-server-public.pem` |
| `clientPrivateKey` | `PrivateKey` | `mle-client-private.pem` |

```
encryptPayload(String plaintext) → String
  └─ Encrypts with serverPublicKey (so server can decrypt)

decryptPayload(String jweToken) → String
  └─ Decrypts with clientPrivateKey (only client can decrypt server's response)
```

---

### 9.3 FundsTransferController

**Package:** `com.visa.server.controller`
**Annotation:** `@RestController`

**Dependencies injected:**
- `MLEService` — for decrypt/encrypt
- `TransactionStore` — for read/write
- `ObjectMapper` — Jackson JSON serializer

**POST `/visadirect/fundstransfer/v1/pushfundstransactions`:**

```
Receive EncryptedPayload (@RequestBody)
Read @RequestHeader("keyId")
  → mleService.decryptPayload(encData)  → plain JSON string
  → objectMapper.readValue()            → Map<String, Object>
  → processTransaction(requestData)     → response Map
  → objectMapper.writeValueAsString()   → response JSON string
  → mleService.encryptPayload()         → JWE string
  → ResponseEntity.ok(new EncryptedPayload(jwe))
```

**`processTransaction()` logic:**

1. Reads `transactionIdentifier` from request (or generates a 15-digit random ID)
2. Generates 6-digit random `approvalCode`
3. Masks PAN: `4957030420210496` → `4957****0496`
4. Sets `actionCode = "00"` (always approved — simulation)
5. Sets `transmissionDateTime` = current timestamp
6. Saves full transaction data to `TransactionStore`
7. Returns response map

**GET `/visadirect/v1/transactionquery`:**

```
Read @RequestParam acquiringBIN and transactionIdentifier
Read @RequestHeader("keyId")
  → transactionStore.findByIdentifierAndBin()
  → Build response map (COMPLETED or NOT_FOUND)
  → mleService.encryptPayload()
  → ResponseEntity.ok(new EncryptedPayload(jwe))
```

---

### 9.4 TransactionStore

**Package:** `com.visa.server.service`
**Annotation:** `@Service`

**Storage:** `ConcurrentHashMap<String, Map<String, Object>>`

- Key: `transactionIdentifier` (String)
- Value: merged map of request + response data

**Thread-safety:** `ConcurrentHashMap` is thread-safe for concurrent reads and writes without explicit synchronization.

**Lookup logic (`findByIdentifierAndBin`):**

```java
Map<String, Object> txn = transactions.get(transactionIdentifier);
if (txn != null) {
    String storedBin = String.valueOf(txn.get("acquiringBin"));
    if (storedBin.equals(acquiringBin)) {
        return txn;  // double-key validation
    }
}
return null;
```

The double-key validation (transactionIdentifier AND acquiringBIN) matches Visa's real API behavior where both fields are required to retrieve a transaction.

---

### 9.5 VisaApiService

**Package:** `com.visa.client.service`
**Annotation:** `@Service`

**Dependencies:**
- `SSLContext` — from `SSLConfig` bean
- `MLEService` — for encrypt/decrypt
- `ObjectMapper` — for JSON
- Config values: `visa.base-url`, `visa.auth.user-id`, `visa.auth.password`

**`invokeAPI(resourcePath, httpMethod, payload)` — core HTTP method:**

```
1. Build URL: visaBaseUrl + resourcePath
2. HttpURLConnection con = new URL(url).openConnection()
3. If HttpsURLConnection:
     httpsConn.setSSLSocketFactory(sslContext.getSocketFactory())
4. Set headers:
     Content-Type: application/json
     Accept: application/json
     keyId: <from MLEService>
     Authorization: Basic <base64(userId:password)>
5. If payload != null:
     con.setDoOutput(true)
     Write payload bytes to OutputStream
6. Read response:
     If 200: read InputStream
     Else: read ErrorStream + log error
7. Return response as String
```

---

### 9.6 SSLConfig

**Package:** `com.visa.client.config`
**Annotation:** `@Configuration`

Creates a `@Bean SSLContext` from configuration properties:

| Property | Description |
|----------|-------------|
| `ssl.key-store` | Path to PKCS12 keystore (client cert + key) |
| `ssl.key-store-password` | Keystore password |
| `ssl.key-store-type` | `PKCS12` |
| `ssl.trust-store` | Path to PKCS12 truststore (CA cert) |
| `ssl.trust-store-password` | Truststore password |
| `ssl.trust-store-type` | `PKCS12` |

The `SSLContext` is initialized with:
- `KeyManager[]` from `SunX509` provider — handles presenting client cert during TLS handshake
- `TrustManager[]` from `PKIX` algorithm — handles validating server cert against CA

---

### 9.7 SecurityConfig

**Package:** `com.visa.server.config`
**Annotations:** `@Configuration`, `@EnableWebSecurity`

**Security filter chain behavior:**
- CSRF disabled (stateless REST — CSRF not applicable)
- No sessions created (`STATELESS`)
- All requests require authentication (`anyRequest().authenticated()`)
- HTTP Basic authentication enabled

**Password storage:**
- Credentials from `application.yml` are BCrypt-hashed at startup
- BCrypt is adaptive — work factor can be increased without changing the API
- Plain-text password is never stored after `passwordEncoder.encode(password)` is called

---

## 10. Configuration Reference

### visa-server `application.yml`

```yaml
server:
  port: 8443
  ssl:
    enabled: true
    key-store: file:C:/Users/Vignesh/visa-projects/certs/server-keystore.p12
    key-store-password: changeit
    key-store-type: PKCS12
    key-alias: server
    client-auth: need
    trust-store: file:C:/Users/Vignesh/visa-projects/certs/server-truststore.p12
    trust-store-password: changeit
    trust-store-type: PKCS12
    protocol: TLS
    enabled-protocols: TLSv1.2,TLSv1.3

spring:
  application:
    name: visa-server

visa:
  auth:
    user-id: "1WM2TT4IHPXC8DQ5I3CH21n1rEBGK-Eyv_oLdzE2VZpDqRn_U"
    password: "19JRVdej9"

mle:
  key-id: "7f591161-6b5f-4136-80b8-2ae8a44ad9eb"
  server-private-key-path: C:/Users/Vignesh/visa-projects/certs/mle-server-private.pem
  client-public-cert-path: C:/Users/Vignesh/visa-projects/certs/mle-client-public.pem

logging:
  level:
    com.visa.server: DEBUG
```

### visa-client `application.yml`

```yaml
server:
  port: 8080

spring:
  application:
    name: visa-client

visa:
  base-url: "https://localhost:8443"
  auth:
    user-id: "1WM2TT4IHPXC8DQ5I3CH21n1rEBGK-Eyv_oLdzE2VZpDqRn_U"
    password: "19JRVdej9"

ssl:
  key-store: C:/Users/Vignesh/visa-projects/certs/client-keystore.p12
  key-store-password: changeit
  key-store-type: PKCS12
  trust-store: C:/Users/Vignesh/visa-projects/certs/client-truststore.p12
  trust-store-password: changeit
  trust-store-type: PKCS12

mle:
  key-id: "7f591161-6b5f-4136-80b8-2ae8a44ad9eb"
  server-public-cert-path: C:/Users/Vignesh/visa-projects/certs/mle-server-public.pem
  client-private-key-path: C:/Users/Vignesh/visa-projects/certs/mle-client-private.pem

logging:
  level:
    com.visa.client: DEBUG
```

---

## 11. JWE Internals — Technical Deep Dive

### 11.1 JWE Compact Serialization Structure

```
eyJhbGciOiJSU0EtT0FFUC0yNTYiLCJlbmMiOiJBMTI4R0NNIiwia2lkIjoiN2Y1OTExNjEtNmI1Zi00MTM2LTgwYjgtMmFlOGE0NGFkOWViIiwiaWF0IjoxNzcxNTE4NjgwMjE0fQ
.
<Base64URL(RSA-encrypted CEK, ~256 bytes for RSA-2048>
.
<Base64URL(IV, 96 bits = 12 bytes)>
.
<Base64URL(AES-128-GCM ciphertext)>
.
<Base64URL(GCM auth tag, 128 bits = 16 bytes)>
```

### 11.2 Decoded JWE Header

```json
{
  "alg": "RSA-OAEP-256",
  "enc": "A128GCM",
  "kid": "7f591161-6b5f-4136-80b8-2ae8a44ad9eb",
  "iat": 1771518680214
}
```

| Field | Type | Description |
|-------|------|-------------|
| `alg` | string | Key wrapping algorithm. RSA-OAEP-256 = RSAES-OAEP with SHA-256 and MGF1-SHA-256 |
| `enc` | string | Content encryption algorithm. A128GCM = AES-128 in GCM mode |
| `kid` | string | Key ID — UUID identifying the RSA key pair |
| `iat` | number | Issued-at in milliseconds — for anti-replay detection |

### 11.3 Encryption Algorithm: RSA-OAEP-256

RSA-OAEP-256 is used to wrap (encrypt) the CEK (Content Encryption Key):

```
CEK (128-bit random AES key)
     │
     ▼
OAEP Padding:
  seed = random 160-bit seed
  pHash = SHA-256("") = fixed hash of empty label
  DB = pHash || PS || 0x01 || CEK   (PS = zero-padding)
  maskedDB = DB XOR MGF1(seed)
  maskedSeed = seed XOR MGF1(maskedDB)
  EM = 0x00 || maskedSeed || maskedDB
     │
     ▼
RSA encrypt: EM^e mod n   (e=publicExponent, n=modulus from public cert)
     │
     ▼
Encrypted CEK (~256 bytes for RSA-2048) → Base64URL encoded
```

### 11.4 Content Encryption: AES-128-GCM

```
Inputs:
  K = CEK (128-bit AES key)
  P = plaintext JSON bytes
  IV = 96-bit random nonce (12 bytes)
  A = Base64URL(JWE header)  ← Additional Authenticated Data

GCM Operation:
  (C, T) = AES-GCM-Encrypt(K, IV, P, A)

Where:
  C = ciphertext (same length as P)
  T = 128-bit authentication tag

Both C and T → Base64URL encoded → part of JWE compact form

On decrypt:
  P = AES-GCM-Decrypt(K, IV, C, A, T)
  If T verification fails → throw exception (tamper detected)
```

The GCM authentication tag protects both the ciphertext AND the JWE header — any tampering with either is detected.

### 11.5 Code Path: Nimbus JOSE+JWT

**Encrypt:**
```java
JWEHeader header = new JWEHeader.Builder(JWEAlgorithm.RSA_OAEP_256, EncryptionMethod.A128GCM)
    .keyID(keyId)
    .customParam("iat", System.currentTimeMillis())
    .build();

JWEObject jweObject = new JWEObject(header, new Payload(plaintext));
jweObject.encrypt(new RSAEncrypter(rsaPublicKey));
String compactJWE = jweObject.serialize();
```

**Decrypt:**
```java
JWEObject jweObject = JWEObject.parse(compactJWE);
jweObject.decrypt(new RSADecrypter(rsaPrivateKey));
String plaintext = jweObject.getPayload().toString();
```

---

## 12. Key Rotation Design

### 12.1 Current State

The system has **one MLE key pair per direction** with a single `kid`:

```yaml
mle:
  key-id: "7f591161-6b5f-4136-80b8-2ae8a44ad9eb"
```

### 12.2 How Key Rotation Works with `kid`

The `kid` is included in the **unencrypted JWE header**. The decryptor reads `kid` BEFORE attempting decryption — it uses this to select the correct private key.

**Rotation steps (zero-downtime):**

```
Phase 1 — Add new key (no disruption):
  Server key store:
    "7f591161-..." → old_private_key_A   (still active)
    "9a3bc421-..." → new_private_key_B   (newly added)

  Publish: mle-server-public-B.pem to clients

Phase 2 — Clients migrate (transition period):
  Some clients still send kid="7f591161-..." (encrypted with public_A)
  New clients send kid="9a3bc421-..."       (encrypted with public_B)

  Server decrypts BOTH successfully using kid lookup.

Phase 3 — Complete rotation:
  All clients confirmed on public_B
  Remove old_private_key_A from key store
  Only "9a3bc421-..." remains
```

### 12.3 Production Implementation Pattern

```java
// Production pattern (not in current code — for reference)
Map<String, PrivateKey> keyStore = new ConcurrentHashMap<>();
keyStore.put("7f591161-...", privateKeyA);
keyStore.put("9a3bc421-...", privateKeyB);

public String decryptPayload(String jweToken) {
    JWEObject jweObject = JWEObject.parse(jweToken);
    String kid = jweObject.getHeader().getKeyID();
    PrivateKey key = keyStore.get(kid);
    if (key == null) throw new JOSEException("Unknown kid: " + kid);
    jweObject.decrypt(new RSADecrypter(key));
    return jweObject.getPayload().toString();
}
```

---

## 13. Certificate Generation

**Script:** `certs/generate-certs.sh`

**Prerequisites:** OpenSSL, Java `keytool`, Bash (Git Bash on Windows)

**Generation steps:**

```bash
# 1. CA Certificate
openssl genrsa -out ca.key 2048
openssl req -new -x509 -key ca.key -out ca.crt -days 365 \
  -subj "/C=US/ST=California/L=Foster City/O=Visa Inc/OU=Visa CA/CN=Visa Local CA"

# 2. Server TLS Cert + Keystore
openssl genrsa -out server-tls.key 2048
openssl req -new -key server-tls.key -out server-tls.csr \
  -subj "/C=US/.../CN=localhost"
# Sign with CA (includes SAN: DNS:localhost, IP:127.0.0.1)
openssl x509 -req -in server-tls.csr -CA ca.crt -CAkey ca.key \
  -out server-tls.crt -days 365 -extfile server-ext.cnf
# Package into PKCS12
openssl pkcs12 -export -in server-tls.crt -inkey server-tls.key \
  -out server-keystore.p12 -name server -passout pass:changeit

# 3. Client TLS Cert + Keystore (same pattern, CN=visa-client, clientAuth EKU)

# 4. Server Truststore (contains CA cert)
keytool -importcert -alias ca -file ca.crt \
  -keystore server-truststore.p12 -storetype PKCS12 -storepass changeit

# 5. Client Truststore (same as server truststore — same CA)

# 6. MLE Server RSA Key Pair
openssl genrsa -out mle-server-private.key 2048
openssl req -new -x509 -key mle-server-private.key -out mle-server-public.pem \
  -days 365 -subj ".../CN=mle-server"
# Convert to PKCS#1 format
openssl rsa -in mle-server-private.key -out mle-server-private.pem

# 7. MLE Client RSA Key Pair (same pattern, CN=mle-client)
```

**Important note on SAN:** Server TLS cert includes `subjectAltName=DNS:localhost,IP:127.0.0.1`. Modern Java TLS clients require SAN; CN-only matching is deprecated and rejected.

---

## 14. Error Handling

### Controller Error Handling

Both controller endpoints wrap all logic in try-catch:

```java
try {
    // decrypt → process → encrypt → return 200
} catch (Exception e) {
    log.error("Error processing...", e);
    return ResponseEntity.internalServerError().build();  // 500
}
```

Possible exceptions and their causes:

| Exception | Cause |
|-----------|-------|
| `ParseException` | Malformed JWE compact serialization |
| `JOSEException` | Wrong key, tampered ciphertext, GCM auth tag failure |
| `JsonProcessingException` | Invalid JSON after decryption |
| `IOException` | MLE key file not found or unreadable at startup |
| `InvalidKeySpecException` | Corrupted RSA key file |

### Client Error Handling

```java
int status = con.getResponseCode();
if (status != 200) {
    // Read error stream and log
    log.error("API call failed with status: {}", status);
}
```

---

## 15. Sequence Diagrams

### Push Funds (OCT) — Complete Sequence

```
VisaClientApp   VisaApiService   ClientMLEService   [Network]   ServerSecurity   ServerMLE   Controller   TransactionStore
     │                │                  │              │              │              │            │              │
     │──pushFunds()──►│                  │              │              │              │            │              │
     │                │──encryptPayload()►│              │              │              │            │              │
     │                │◄── JWE token ────│              │              │              │            │              │
     │                │                  │              │              │              │            │              │
     │                │──── POST /visadirect/... ───────►│              │              │            │              │
     │                │     {encData: JWE}               │              │              │            │              │
     │                │     + Basic Auth header          │              │              │            │              │
     │                │     + keyId header               │              │              │            │              │
     │                │                  │    mTLS verify client cert  │              │            │              │
     │                │                  │              │──────────────►│              │            │              │
     │                │                  │              │    Basic Auth check          │            │              │
     │                │                  │              │──────────────►│              │            │              │
     │                │                  │              │              │──decryptPayload()──────────►│              │
     │                │                  │              │              │              │◄─plain JSON─│              │
     │                │                  │              │              │              │──process()──►──────────────►│
     │                │                  │              │              │              │             │◄─stored───────│
     │                │                  │              │              │              │◄─response──►│              │
     │                │                  │              │              │──encryptPayload()──────────►│              │
     │                │                  │              │◄── {encData: JWE} ──────────│            │              │
     │                │◄─ {encData: JWE} ───────────────│              │              │            │              │
     │                │──decryptPayload()►│              │              │              │            │              │
     │                │◄── response JSON ─│              │              │              │            │              │
     │◄── response ───│                  │              │              │              │            │              │
```

---

## 16. Dependency Reference

### visa-server `pom.xml`

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.5</version>
</parent>

<dependencies>
    <!-- Spring MVC + Embedded Tomcat + Jackson -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <!-- Spring Security: Basic Auth, BCrypt, filter chain -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-security</artifactId>
    </dependency>

    <!-- JWE (RSA-OAEP-256 + A128GCM) -->
    <dependency>
        <groupId>com.nimbusds</groupId>
        <artifactId>nimbus-jose-jwt</artifactId>
        <version>9.37.3</version>
    </dependency>

    <!-- PKCS#1 RSA key parsing via ASN1 -->
    <dependency>
        <groupId>org.bouncycastle</groupId>
        <artifactId>bcprov-jdk18on</artifactId>
        <version>1.77</version>
    </dependency>
</dependencies>
```

### Why Each Library?

| Library | Why Needed |
|---------|-----------|
| `spring-boot-starter-web` | Embedded Tomcat, Spring MVC `@RestController`, Jackson JSON |
| `spring-boot-starter-security` | Basic Auth filter, BCrypt, `SecurityFilterChain` |
| `nimbus-jose-jwt` | Full JWE support: RSA-OAEP-256 + A128GCM, compact serialization |
| `bcprov-jdk18on` | Parse PKCS#1 (`BEGIN RSA PRIVATE KEY`) format — Java stdlib only supports PKCS#8 |

---

## 17. Directory Structure

```
visa-projects/
├── TECHNICAL-SPECIFICATION.md       ← this document
├── README.md                        ← project overview
├── MTLS-AND-MLE-FLOW.md             ← flow documentation
│
├── certs/
│   ├── generate-certs.sh            ← certificate generation script
│   ├── CERTIFICATES.md              ← cert generation guide
│   ├── ca.crt                       ← root CA certificate
│   ├── server-keystore.p12          ← server TLS identity (cert + key)
│   ├── server-truststore.p12        ← server's CA trust (verifies client)
│   ├── client-keystore.p12          ← client TLS identity (cert + key)
│   ├── client-truststore.p12        ← client's CA trust (verifies server)
│   ├── mle-server-private.pem       ← server MLE private key (PKCS#1)
│   ├── mle-server-public.pem        ← server MLE public cert (X.509)
│   ├── mle-client-private.pem       ← client MLE private key (PKCS#1)
│   └── mle-client-public.pem        ← client MLE public cert (X.509)
│
├── visa-server/
│   ├── pom.xml
│   ├── README.md
│   └── src/main/
│       ├── java/com/visa/server/
│       │   ├── VisaServerApplication.java
│       │   ├── config/
│       │   │   └── SecurityConfig.java
│       │   ├── controller/
│       │   │   └── FundsTransferController.java
│       │   ├── model/
│       │   │   └── EncryptedPayload.java
│       │   └── service/
│       │       ├── MLEService.java
│       │       └── TransactionStore.java
│       └── resources/
│           └── application.yml
│
└── visa-client/
    ├── pom.xml
    ├── README.md
    └── src/main/
        ├── java/com/visa/client/
        │   ├── VisaClientApplication.java
        │   ├── config/
        │   │   └── SSLConfig.java
        │   ├── model/
        │   │   └── EncryptedPayload.java
        │   └── service/
        │       ├── MLEService.java
        │       └── VisaApiService.java
        └── resources/
            └── application.yml
```

---

## 18. Security Assumptions and Limitations

### Assumptions

| Assumption | Implication |
|------------|-------------|
| Private key files are secured at the OS level | The PEM files on disk are the trust root — file system permissions are critical |
| Both parties obtained each other's MLE public cert through a secure out-of-band channel | Prevents MITM during key exchange |
| CA private key (`ca.key`) is deleted or secured after cert generation | If CA key is leaked, an attacker can issue fake TLS certs |

### Limitations (Simulation vs Production)

| Area | Current (Simulation) | Production Visa |
|------|---------------------|----------------|
| Transaction storage | In-memory `ConcurrentHashMap` (lost on restart) | Persistent database |
| Key storage | PEM files on disk | HSM (Hardware Security Module) or vault |
| Approval logic | Always returns `actionCode: 00` | Real payment network routing |
| Replay protection | `iat` in JWE header (not enforced) | Strict timestamp window validation |
| Certificate lifecycle | Self-signed, 365 days | Visa-issued certs, automated renewal |
| Audit logging | `SLF4J` logs to console | Immutable audit trail with SIEM |
| High availability | Single instance, no failover | Load-balanced, geo-redundant |
| PAN data | Masked in response but present in logs | PCI-DSS tokenization |

### Strengths of Current Implementation

1. **Correct cryptographic algorithms** — RSA-OAEP-256 + A128GCM matches Visa's production MLE spec
2. **Correct key directionality** — separate key pairs for request vs response
3. **Dual-format key loading** — supports both PKCS#1 and PKCS#8 PEM files
4. **Stateless design** — horizontally scalable without sticky sessions
5. **Production-grade libraries** — Nimbus JOSE+JWT and BouncyCastle are industry standard
6. **kid support** — architecture ready for key rotation without code changes

---

*End of Technical Specification*
