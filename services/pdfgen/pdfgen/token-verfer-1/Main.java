import com.sun.net.httpserver.Headers;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import javax.crypto.Cipher;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.*;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.concurrent.Executors;

public class Main {
    private static PrivateKey privateKey;
    private static PublicKey publicKey;

    private static final Path PUBLIC_KEY_FILE = Path.of("keys", "public.key");
    private static final Path PRIVATE_KEY_FILE = Path.of("keys", "private.key");


    public static void main(String[] args) throws Exception {
        if (!Files.exists(PUBLIC_KEY_FILE) || !Files.exists(PRIVATE_KEY_FILE)) {
            KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA");
            kpg.initialize(512);
            KeyPair kp = kpg.generateKeyPair();

            savePublicKey(kp.getPublic(), PUBLIC_KEY_FILE);
            savePrivateKey(kp.getPrivate(), PRIVATE_KEY_FILE);

            publicKey = kp.getPublic();
            privateKey = kp.getPrivate();

            System.out.println("Keys generated and saved.");
        } else {
            publicKey = loadPublicKey(PUBLIC_KEY_FILE);
            privateKey = loadPrivateKey(PRIVATE_KEY_FILE);

            System.out.println("Keys loaded from files.");
        }

        if (privateKey == null || publicKey == null) {
            throw new IllegalStateException("Load privateKey/publicKey before starting server");
        }

        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", 8082), 0);
        server.createContext("/sign", Main::handleSign);
        server.createContext("/validate", Main::handleValidate);
        server.setExecutor(Executors.newFixedThreadPool(8));
        server.start();

        System.out.println("Server started on http://0.0.0.0:8082");
    }

    private static void handleSign(HttpExchange exchange) throws IOException {
        try {
            if (!"POST".equalsIgnoreCase(exchange.getRequestMethod())) {
                sendJson(exchange, 405, "{\"error\":\"method_not_allowed\"}");
                return;
            }

            String body = readBody(exchange);
            String message = extractJsonString(body, "message");
            if (message == null) {
                sendJson(exchange, 400, "{\"error\":\"missing_message\"}");
                return;
            }

            byte[] block = buildRsaBlockFromMessage(message, publicKey);

            Cipher dec = Cipher.getInstance("RSA/ECB/NoPadding");
            dec.init(Cipher.DECRYPT_MODE, privateKey);
            byte[] signature = dec.doFinal(block);

            String signatureB64 = Base64.getEncoder().encodeToString(signature);
            sendJson(exchange, 200, "{\"signature\":\"" + jsonEscape(signatureB64) + "\"}");
        } catch (Exception e) {
            e.printStackTrace();
            sendJson(exchange, 500, "{\"error\":\"" + jsonEscape(e.toString()) + "\"}");
        }
    }

    private static void handleValidate(HttpExchange exchange) throws IOException {
        try {
            if (!"POST".equalsIgnoreCase(exchange.getRequestMethod())) {
                sendJson(exchange, 405, "{\"error\":\"method_not_allowed\"}");
                return;
            }

            String body = readBody(exchange);
            String message = extractJsonString(body, "message");
            String signatureB64 = extractJsonString(body, "signature");

            if (message == null) {
                sendJson(exchange, 400, "{\"error\":\"missing_message\"}");
                return;
            }
            if (signatureB64 == null) {
                sendJson(exchange, 400, "{\"error\":\"missing_signature\"}");
                return;
            }

            byte[] signature = Base64.getDecoder().decode(signatureB64);
            byte[] expectedBlock = buildRsaBlockFromMessage(message, publicKey);

            Cipher enc = Cipher.getInstance("RSA/ECB/NoPadding");
            enc.init(Cipher.ENCRYPT_MODE, publicKey);
            byte[] actualBlock = enc.doFinal(signature);

            boolean valid = constantTimeEquals(expectedBlock, actualBlock);
            sendJson(exchange, 200, "{\"valid\":" + valid + "}");
        } catch (IllegalArgumentException e) {
            sendJson(exchange, 400, "{\"error\":\"bad_base64_or_json\"}");
        } catch (Exception e) {
            e.printStackTrace();
            sendJson(exchange, 500, "{\"error\":\"" + jsonEscape(e.toString()) + "\"}");
        }
    }

    private static byte[] buildRsaBlockFromMessage(String message, PublicKey publicKey) throws Exception {
        byte[] data = message.getBytes(StandardCharsets.UTF_8);
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(data);

        int k = (((RSAPublicKey) publicKey).getModulus().bitLength() + 7) / 8;
        byte[] block = new byte[k];

        // Кладём SHA-256 в конец блока, слева нули
        System.arraycopy(hash, 0, block, k - hash.length, hash.length);
        return block;
    }

    private static boolean constantTimeEquals(byte[] a, byte[] b) {
        if (a == null || b == null || a.length != b.length) {
            return false;
        }
        int diff = 0;
        for (int i = 0; i < a.length; i++) {
            diff |= (a[i] ^ b[i]);
        }
        return diff == 0;
    }

    private static String readBody(HttpExchange exchange) throws IOException {
        try (InputStream in = exchange.getRequestBody()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private static void sendJson(HttpExchange exchange, int status, String json) throws IOException {
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        Headers headers = exchange.getResponseHeaders();
        headers.set("Content-Type", "application/json; charset=utf-8");
        headers.set("Cache-Control", "no-store");
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    // Очень простой парсер только для JSON вида {"field":"value"}
    // Хватает для message/signature, если не тащить библиотеку.
    private static String extractJsonString(String json, String field) {
        if (json == null) {
            return null;
        }

        String key = "\"" + field + "\"";
        int keyPos = json.indexOf(key);
        if (keyPos < 0) {
            return null;
        }

        int colonPos = json.indexOf(':', keyPos + key.length());
        if (colonPos < 0) {
            return null;
        }

        int startQuote = -1;
        for (int i = colonPos + 1; i < json.length(); i++) {
            char c = json.charAt(i);
            if (Character.isWhitespace(c)) {
                continue;
            }
            if (c == '"') {
                startQuote = i;
                break;
            }
            return null;
        }

        if (startQuote < 0) {
            return null;
        }

        StringBuilder sb = new StringBuilder();
        boolean escaped = false;
        for (int i = startQuote + 1; i < json.length(); i++) {
            char c = json.charAt(i);

            if (escaped) {
                switch (c) {
                    case '"': sb.append('"'); break;
                    case '\\': sb.append('\\'); break;
                    case '/': sb.append('/'); break;
                    case 'b': sb.append('\b'); break;
                    case 'f': sb.append('\f'); break;
                    case 'n': sb.append('\n'); break;
                    case 'r': sb.append('\r'); break;
                    case 't': sb.append('\t'); break;
                    case 'u':
                        if (i + 4 >= json.length()) {
                            throw new IllegalArgumentException("Bad unicode escape");
                        }
                        String hex = json.substring(i + 1, i + 5);
                        sb.append((char) Integer.parseInt(hex, 16));
                        i += 4;
                        break;
                    default:
                        sb.append(c);
                }
                escaped = false;
                continue;
            }

            if (c == '\\') {
                escaped = true;
                continue;
            }

            if (c == '"') {
                return sb.toString();
            }

            sb.append(c);
        }

        throw new IllegalArgumentException("Unterminated JSON string");
    }

    private static String jsonEscape(String s) {
        if (s == null) {
            return "";
        }

        StringBuilder sb = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\b': sb.append("\\b"); break;
                case '\f': sb.append("\\f"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb.toString();
    }

    private static void savePublicKey(PublicKey key, Path path) throws Exception {
        byte[] encoded = key.getEncoded(); // X.509
        Files.write(path, encoded);
    }

    private static void savePrivateKey(PrivateKey key, Path path) throws Exception {
        byte[] encoded = key.getEncoded(); // PKCS#8
        Files.write(path, encoded);
    }

    private static PublicKey loadPublicKey(Path path) throws Exception {
        byte[] encoded = Files.readAllBytes(path);
        X509EncodedKeySpec spec = new X509EncodedKeySpec(encoded);
        KeyFactory kf = KeyFactory.getInstance("RSA");
        return kf.generatePublic(spec);
    }

    private static PrivateKey loadPrivateKey(Path path) throws Exception {
        byte[] encoded = Files.readAllBytes(path);
        PKCS8EncodedKeySpec spec = new PKCS8EncodedKeySpec(encoded);
        KeyFactory kf = KeyFactory.getInstance("RSA");
        return kf.generatePrivate(spec);
    }
}