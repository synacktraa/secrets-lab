"""Count how many files inside a `docker save` tarball contain a string.

Walks every blob in the saved image (layer tars, gzip-compressed or not, plus
the JSON config and manifests) and every file inside each layer.

usage: python scan_image.py image.tar NEEDLE
prints the hit count on stdout and the matching paths on stderr
"""
import gzip
import io
import sys
import tarfile

path, needle = sys.argv[1], sys.argv[2].encode()
hits = []


def scan_blob(name, data):
    if data[:4] == b"\x28\xb5\x2f\xfd":
        sys.exit(f"{name}: zstd-compressed layer, can't scan with the stdlib")
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    try:
        with tarfile.open(fileobj=io.BytesIO(data)) as layer:
            for member in layer:
                if member.isfile() and needle in layer.extractfile(member).read():
                    hits.append(f"{name} -> {member.name}")
        return
    except tarfile.ReadError:
        pass  # not a tar: config JSON, manifest, index
    if needle in data:
        hits.append(name)


with tarfile.open(path) as saved:
    for member in saved:
        if member.isfile():
            scan_blob(member.name, saved.extractfile(member).read())

print(len(hits))
for hit in hits:
    print("   ", hit, file=sys.stderr)
