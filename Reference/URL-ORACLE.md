# Shared URL oracle snapshot

`manifest-idna-goldens.json.gz` is a frozen copy of
`lokalized-spec/generated/url-oracle/manifest-idna-goldens.json.gz`.
`manifest-idna-lock.json` preserves the canonical source/module inventory.
The portable Python modules in `Tools/URLOracle/` are copied byte-for-byte from
`lokalized-spec/tools/url_oracle/`. Their data and license inputs retain their
existing `Unicode-17.0.0/` and `IDNA-Compatibility/` paths here.

The source of truth is `lokalized-spec`. This snapshot allows the Swift repository
to qualify its resolver offline without a sibling checkout, Node, downloads or
Python packages. The production library reads none of these files.

```sh
python3 Tools/sync_url_oracle.py --check
python3 Tools/sync_url_oracle.py --check-source --source ../lokalized-spec
python3 Tools/test_idna_archive.py
python3 Tools/verify_idna_urls.py --check
```

For a reviewed shared update, change the fixed artifact pins in
`Tools/sync_url_oracle.py`, then run
`python3 Tools/sync_url_oracle.py --sync --source ../lokalized-spec`.
It verifies every canonical input before copying and never runs an oracle or Git.
Oracle refreshes belong in the canonical repository, through
`python3 tools/check-url-oracle.py --refresh-goldens --node /path/to/pinned/node`.

The archived JSON digest remains
`7f84ecb403b6e772f00dfa851d7de42e6d9556998dbb0b47feca23c8fff380db`.
The gzip occupies 731,845 bytes and reproduces all 19,308,094 original JSON bytes
and 56,513 case identities. Qualification reports continue to hash decoded JSON.
See [manifest URL evidence](../Documentation/MANIFEST-URLS.md) for the named
compatibility profile, counts and decoder limits.
