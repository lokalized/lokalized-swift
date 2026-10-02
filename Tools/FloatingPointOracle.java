// Copyright 2026 Lokalized. Licensed under the Apache License, Version 2.0.
// Development oracle only. Never compiled into or required by the Swift package.
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

public final class FloatingPointOracle {
    public static void main(String[] args) throws Exception {
        if (!System.getProperty("java.version").equals("21.0.11")
                || !System.getProperty("java.vendor").equals("Amazon.com Inc.")) {
            throw new IllegalStateException("The pinned Corretto 21.0.11 oracle is required");
        }
        var reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII));
        for (String line; (line = reader.readLine()) != null;) {
            var fields = line.split("\\t", -1);
            if (fields.length != 2) throw new IllegalArgumentException("Expected width and raw bits");
            if (fields[0].equals("float")) {
                System.out.println(Float.toString(Float.intBitsToFloat(Integer.parseUnsignedInt(fields[1], 16))));
            } else if (fields[0].equals("double")) {
                System.out.println(Double.toString(Double.longBitsToDouble(Long.parseUnsignedLong(fields[1], 16))));
            } else {
                throw new IllegalArgumentException("Unknown width: " + fields[0]);
            }
        }
    }
}
